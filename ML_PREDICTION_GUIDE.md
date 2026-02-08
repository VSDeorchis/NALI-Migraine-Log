# Migraine Risk Prediction (ML) — Implementation Guide

## Overview

Headway v2.2 introduces a **machine learning–powered migraine risk prediction** system. The feature uses a hybrid two-tier architecture that provides immediate value (Tier 1 rule-based scoring) while improving over time as the user logs more entries (Tier 2 on-device CoreML).

All computation and data stay entirely on-device. No data is sent to external servers beyond the Open-Meteo weather API (free, no key).

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Data Sources                          │
│  Core Data  ·  Weather Forecast  ·  HealthKit  ·  Clock │
└────────────────────────┬────────────────────────────────┘
                         ▼
              ┌─────────────────────┐
              │  FeatureExtractor   │
              │ (normalized vector) │
              └──────────┬──────────┘
                         ▼
          ┌──────────────┴──────────────┐
          ▼                             ▼
 ┌──────────────────┐     ┌───────────────────────┐
 │ Tier 1: Rule-    │     │ Tier 2: CoreML        │
 │ Based Scoring    │     │ BoostedTreeClassifier  │
 │ (always active)  │     │ (≥ 20 entries)         │
 └────────┬─────────┘     └────────┬──────────────┘
          └──────────┬─────────────┘
                     ▼
           ┌──────────────────┐
           │ MigraineRiskScore│
           │ + Hybrid Blend   │
           └────────┬─────────┘
                    ▼
         ┌────────────────────┐
         │ MigraineRiskView   │
         │ (Predict tab)      │
         └────────────────────┘
```

---

## What Was Implemented

### 1. MigraineRiskScore (`Shared/Models/MigraineRiskScore.swift`)

Data model for all prediction outputs:

| Type | Purpose |
|------|---------|
| `MigraineRiskScore` | Overall risk (0–1), risk level, top factors, recommendations, confidence, source |
| `RiskLevel` | `.low` / `.moderate` / `.high` / `.veryHigh` with colors and icons |
| `RiskFactor` | Individual factor name, contribution weight, icon, color, detail text |
| `PredictionSource` | `.ruleBased` / `.machineLearning` / `.hybrid` |
| `MigraineFeatureVector` | Normalized input vector (temporal, weather, trigger freq, HealthKit, check-in) |
| `HourlyRiskForecast` | Per-hour risk and primary contributing factor |

### 2. FeatureExtractor (`Shared/Services/FeatureExtractor.swift`)

Converts raw data into the ML feature vector. Features extracted:

**Temporal** — day of week, hour of day, month, weekend flag

**Frequency / Recency** — days since last migraine, count in last 7 and 30 days, average pain of last 5 entries

**Weather** — current pressure, 24h pressure change, rate of change, temperature, precipitation, cloud cover, weather code, humidity

**Trigger Frequencies** — percentage of past migraines tagged with each trigger (stress, sleep, dehydration, weather, hormones, alcohol, caffeine, food, exercise, screen time)

**Medication Rebound** — triptan uses in last 7 days, NSAID uses in last 7 days

**HealthKit (optional)** — sleep hours, HRV, resting heart rate, steps, days since menstruation

**Daily Check-in (optional)** — self-reported stress (1–5), hydration (1–5), caffeine (cups)

Also provides helper methods:
- `hourlyDistribution(from:)` — probability of migraine at each hour
- `dayOfWeekDistribution(from:)` — probability by day of week
- `averageWeatherDuringMigraines(_:)` — mean pressure change, temp, precipitation

Supporting types defined here:
- `HealthKitSnapshot` — container for HealthKit readings
- `DailyCheckInData` — codable struct saved to/loaded from UserDefaults (today only)

### 3. WeatherForecastService (`Shared/Services/WeatherForecastService.swift`)

Forward-looking weather using the **Open-Meteo Forecast API** (free, no key):

- Endpoint: `https://api.open-meteo.com/v1/forecast`
- Fetches 48-hour forecast: temperature, pressure, precipitation, cloud cover, weather code, **humidity**
- 30-minute cache to avoid redundant requests
- `currentWeatherSnapshot()` converts forecast into the same `WeatherSnapshot` format used by historical data so the prediction engine consumes both identically
- `maxPressureChange(inNext:)` for quick risk checks
- `next(hours:)` returns upcoming forecast hours

### 4. HealthKitManager (`Shared/Services/HealthKitManager.swift`)

Reads health data for prediction features. All data stays on-device.

| Method | Data | HealthKit Type |
|--------|------|---------------|
| `getLastNightSleep()` | Total sleep hours (6 PM–noon window) | `HKCategoryType.sleepAnalysis` |
| `getLatestHRV()` | SDNN in ms (last 24h) | `HKQuantityType.heartRateVariabilitySDNN` |
| `getRestingHeartRate()` | BPM (last 48h) | `HKQuantityType.restingHeartRate` |
| `getStepsYesterday()` | Step count for yesterday | `HKQuantityType.stepCount` |
| `getDaysSinceMenstruation()` | Days since last flow (60-day window) | `HKCategoryType.menstrualFlow` |

- `fetchSnapshot()` runs all queries concurrently and returns a `HealthKitSnapshot`
- Authorization requested via `requestAuthorization()` (read-only permissions)
- Gracefully returns `nil` per metric when data is unavailable
- `isAvailable` guard for devices without HealthKit

### 5. MigrainePredictionService (`Shared/Services/MigrainePredictionService.swift`)

Central prediction engine.

#### Tier 1 — Rule-Based Scoring

Weighted formula using 15+ evidence-based risk factors. Works immediately, even with 0 entries.

| Factor | Weight | Condition |
|--------|--------|-----------|
| Rapid pressure drop | 0.25 | > 5 hPa in 24h |
| Moderate pressure drop | 0.15 | 3–5 hPa in 24h |
| Very poor sleep | 0.25 | < 5 hours |
| Poor sleep | 0.20 | < 6 hours |
| High recent frequency | 0.15 | ≥ 3 in last 7 days |
| Recent migraine | 0.10 | Within last 2 days |
| High stress | 0.15 | Self-reported ≥ 4/5 |
| Low HRV | 0.12 | < 30 ms |
| Elevated RHR | 0.08 | > 80 bpm |
| Menstrual window | 0.15 | Days 1–3 of cycle |
| Triptan overuse | 0.12 | ≥ 3 uses this week |
| NSAID overuse | 0.10 | ≥ 4 uses this week |
| Adverse weather | 0.10 | Weather code ≥ 61 |
| Low hydration | 0.10 | Self-reported ≤ 2/5 |
| High caffeine | 0.08 | > 4 cups |
| Low activity | 0.05 | < 2,000 steps |
| Weekend effect | 0.05 | Schedule change |
| Peak time window | 0.08 | Current hour matches historical peak |
| Peak day of week | 0.05 | Current day matches historical peak |
| Personal trigger pattern | 0.10 | Trigger present in > 40% of migraines (top 3) |

Risk is clamped to 0–1 and mapped to four levels:
- **Low** (0–24%): green
- **Moderate** (25–49%): yellow
- **High** (50–74%): orange
- **Very High** (75–100%): red

Each factor generates a human-readable `RiskFactor` with icon and actionable detail text.

#### Tier 2 — On-Device CoreML

- Activates automatically after **20+ migraine entries**
- Uses `MLBoostedTreeClassifier` via CreateML (iOS 15.4+, macOS 12+)
- Training data: one row per day over the user's history (migraine yes/no + feature vector)
- Re-trains weekly or when 5+ new entries added
- Model saved to Documents directory as `MigrainePredictor.mlmodel`
- Falls back to Tier 1 if confidence is low or training fails
- Gated with `#if canImport(CreateML)` for watchOS compatibility
- `MLModel.compileModel(at:)` gated with `#if os(watchOS)` to avoid unavailable API

#### Hybrid Blending

When both tiers are active, scores are blended:
- ML weight = ML confidence × 0.6
- Rule weight = 1.0 − ML weight
- Explanations always come from the rule-based tier (ML is a black box)

#### 24-Hour Risk Forecast

`generate24HourForecast(migraines:forecastHours:healthData:dailyCheckIn:)` runs the rule-based scorer against each upcoming forecast hour to produce a timeline of predicted risk.

### 6. MigraineRiskView (`NALI Migraine Log/Views/MigraineRiskView.swift`)

New **Predict** tab in the main tab bar (brain icon). iOS only.

**Sections:**
1. **Risk Gauge** — animated circular ring (green → red), percentage, risk level label, prediction source badge, confidence progress bar
2. **Data Source Badges** — horizontal scroll of pills showing active inputs (entries, weather, HealthKit, check-in). Tapping an inactive badge opens setup
3. **Contributing Factors** — card listing top 6 factors with icon, color, name, detail, and contribution bar
4. **24-Hour Risk Forecast** — SwiftUI Charts area/line chart colored by risk level, with Catmull-Rom interpolation
5. **Recommendations** — actionable advice cards (e.g., "Stay hydrated", "Consider preventive medication")
6. **Quick Actions** — Daily Check-in button and Refresh button
7. **Model Status** — shows current engine (Pattern Analysis / Training ML / ML Active) and entries needed for ML activation

### 7. DailyCheckInView (`NALI Migraine Log/Views/DailyCheckInView.swift`)

Optional daily check-in sheet accessible from the Predict tab. iOS only.

- **Stress Level** (1–5 scale with descriptive labels)
- **Hydration Level** (1–5 scale)
- **Caffeine Intake** (cup counter with +/- buttons)
- Stored in UserDefaults, valid for today only
- Automatically feeds into the next risk calculation

### 8. Info.plist & Entitlements Updates

**Info.plist:**
- Added `NSHealthShareUsageDescription`: *"Headway reads sleep, heart rate variability, resting heart rate, step count, and menstrual cycle data to improve migraine risk predictions. All data stays on your device."*

**NALI Migraine Log.entitlements:**
- Added `com.apple.developer.healthkit` = `true`
- Added `com.apple.developer.healthkit.access` = `[]` (empty — read only)

**Note:** You must also enable the **HealthKit** capability in Xcode's Signing & Capabilities tab for the iOS target.

### 9. Tab Integration

`NALI_Migraine_LogApp.swift` — added the Predict tab between Calendar and Analytics:

```swift
MigraineRiskView(viewModel: viewModel)
    .tabItem {
        Label("Predict", systemImage: "brain.head.profile")
    }
```

### 10. Xcode Project Updates

`project.pbxproj` — all 4 new `Shared/Services/` files added:
- `PBXFileReference` entries
- Added to `Services` PBXGroup
- `PBXBuildFile` entries for iOS, macOS, and Watch targets
- Views (`MigraineRiskView`, `DailyCheckInView`) are iOS-only via the synchronized root group

---

## How It Works

### For the Patient

1. **Open the Predict tab** — the risk gauge immediately shows current risk
2. **Risk auto-calculates** using:
   - Your migraine history (frequency, patterns, triggers)
   - Current and forecast weather (barometric pressure, temperature)
   - HealthKit data if connected (sleep, HRV, heart rate, steps, cycle)
   - Today's check-in if completed (stress, hydration, caffeine)
3. **Contributing factors** explain *why* the risk is at its level in plain language
4. **24-hour forecast chart** shows when risk peaks during the day
5. **Recommendations** provide actionable advice tailored to current factors
6. **Tap Refresh** to recalculate with the latest data
7. **Complete a Daily Check-in** to improve accuracy

### Under the Hood

1. `MigraineRiskView.refreshPrediction()` orchestrates the flow
2. Fetches 48h weather forecast via `WeatherForecastService`
3. Fetches HealthKit snapshot if authorized
4. Loads today's daily check-in from UserDefaults
5. `FeatureExtractor` converts all data to a `MigraineFeatureVector`
6. `MigrainePredictionService.calculateRiskScore()` runs Tier 1 (always) and Tier 2 (if available)
7. Results published to the view via `@Published` properties
8. 24-hour forecast runs the scorer against each upcoming weather hour

---

## Phased Rollout

| Phase | What | Status |
|-------|------|--------|
| **Phase 1** | Rule-based scoring + weather forecast + risk dashboard | **Implemented** |
| **Phase 2** | HealthKit integration (sleep, HRV, HR, steps, cycle) | **Implemented** |
| **Phase 3** | On-device CoreML training (auto after 20+ entries) | **Implemented** |
| **Phase 4** | Daily check-in (stress, hydration, caffeine) | **Implemented** |

---

## Recommended Additional Metrics

| Metric | Source | Impact | Difficulty | Status |
|--------|--------|--------|------------|--------|
| Sleep duration/quality | HealthKit (Apple Watch) | Very High | Medium | Implemented |
| Heart rate variability | HealthKit (Apple Watch) | High | Medium | Implemented |
| Resting heart rate | HealthKit (Apple Watch) | Medium | Medium | Implemented |
| Weather forecast (future) | Open-Meteo Forecast API | Very High | Low | Implemented |
| Menstrual cycle | HealthKit | High (if applicable) | Medium | Implemented |
| Step count / activity | HealthKit | Medium | Low | Implemented |
| Humidity | Open-Meteo (forecast) | Medium | Low | Implemented |
| User stress level | Daily check-in | High | Low | Implemented |
| User hydration level | Daily check-in | Medium | Low | Implemented |
| Caffeine intake | Daily check-in | Medium | Low | Implemented |
| Medication rebound risk | Derived from existing data | High | Low | Implemented |
| Migraine cycle patterns | Derived from existing data | Very High | Low | Implemented |

---

## Files Created

| File | Location | Purpose |
|------|----------|---------|
| `MigraineRiskScore.swift` | `Shared/Models/` | Risk score data model and feature vector |
| `FeatureExtractor.swift` | `Shared/Services/` | Raw data → normalized features |
| `WeatherForecastService.swift` | `Shared/Services/` | 48h weather forecast (Open-Meteo) |
| `HealthKitManager.swift` | `Shared/Services/` | HealthKit read access (sleep, HRV, HR, steps, cycle) |
| `MigrainePredictionService.swift` | `Shared/Services/` | Two-tier prediction engine |
| `MigraineRiskView.swift` | `NALI Migraine Log/Views/` | Risk dashboard UI (iOS only) |
| `DailyCheckInView.swift` | `NALI Migraine Log/Views/` | Stress/hydration/caffeine check-in (iOS only) |

## Files Modified

| File | Changes |
|------|---------|
| `Info.plist` | Added `NSHealthShareUsageDescription` |
| `NALI Migraine Log.entitlements` | Added HealthKit entitlement |
| `NALI_Migraine_LogApp.swift` | Added Predict tab to TabView |
| `project.pbxproj` | Added all new file references and build phases |
| `WEATHER_FEATURE_GUIDE.md` | Marked forecast/ML items as implemented |

---

## Troubleshooting

### Risk score shows 0% with no factors
- Ensure you have migraine entries logged
- Tap Refresh to recalculate
- Complete a Daily Check-in for additional data points
- Connect HealthKit if you have an Apple Watch

### HealthKit data not appearing
- Tap the HealthKit badge on the Predict tab to connect
- Approve read permissions in the system dialog
- Ensure Apple Watch has synced overnight sleep data
- HealthKit is not available on iPad (no Watch pairing)

### ML model not activating
- Requires 20+ migraine entries
- Trains automatically once per week
- Check Model Status card at the bottom of the Predict tab
- iOS 15.4+ required for on-device training
- Not available on watchOS (rule-based only)

### Weather forecast not loading
- Ensure location permission is granted
- Check internet connectivity
- Forecast caches for 30 minutes — tap Refresh after cache expires

### Build errors on watchOS
- `MigraineRiskView` and `DailyCheckInView` are iOS-only
- `MLModel.compileModel(at:)` is gated with `#if os(watchOS)`
- CreateML training is gated with `#if canImport(CreateML)`
- If watchOS errors persist, verify these files are NOT in the Watch target membership

---

## Privacy

- **All data stays on-device** — no prediction data leaves the phone
- **HealthKit read-only** — the app never writes to HealthKit
- **Weather API** — only latitude/longitude are sent to Open-Meteo (no personal data)
- **No analytics** — no usage tracking or telemetry
- **ML model** — trained and stored locally in the app's Documents directory
