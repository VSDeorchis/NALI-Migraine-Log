# NALI Migraine Log

A privacy-first migraine tracker for iPhone, Apple Watch, and Mac. Logs are stored on-device with Core Data and synced exclusively through the user's own iCloud account via `NSPersistentCloudKitContainer` — no developer-side servers, no analytics, no third-party SDKs.

The app combines a manual logging UI with a hybrid risk-prediction engine (rule-based + on-device CoreML) that uses the user's history and a free public weather API ([Open-Meteo](https://open-meteo.com/)) to surface a forecast risk score.

---

## Repository layout

```
.
├── Shared/                                  # Code compiled into all 3 targets
│   ├── Models/                              # Core Data classes + enum facades
│   ├── Services/                            # Logger, persistence, prediction, weather, location, HealthKit (read+write), migration, review-prompt, notifications, BG-task scheduler
│   ├── NALI_Migraine_Log.xcdatamodeld/      # The single source of truth for the schema
│   ├── AppContactInfo.swift                 # Centralized App Store ID, support email, website, privacy-policy URL
│   └── WatchConnectivityManager.swift       # iPhone ↔ Watch payload bridge
│
├── NALI Migraine Log/                       # iOS app (synchronized root group; ALSO consumed by macOS + Watch targets)
│   ├── Views/, ViewModels/, Utilities/      # iOS-specific UI (incl. EnjoymentPromptView + FeedbackFormView, both #if os(iOS))
│   ├── Views/Analytics/                     # Dashboard subviews: AnalyticsModels, AnalyticsComputations, SeverityHeatmapView, AnalyticsInsightsView, AnalyticsMetricDetailView, HealthCorrelationStore, HealthCorrelationsSectionView
│   ├── AppIntents/LogMigraineIntent.swift   # Siri / Shortcuts entry point — iOS-only, scoped via #if os(iOS)
│   ├── iOSContentView.swift                 # Adaptive root: TabView on iPhone, NavigationSplitView (sidebar+detail) on iPad
│   ├── PrivacyInfo.xcprivacy                # Privacy manifest (one per .app bundle)
│   ├── Info.plist                           # Declares background modes (fetch+processing) and BGTaskScheduler permitted identifiers
│   └── NALI_Migraine_LogApp.swift           # @main entry point — registers BackgroundTaskScheduler + reconciles notifications on scenePhase
│
├── NALI Migraine Log macOS/                 # macOS app target (synchronized root)
│   ├── Views/, ViewModels/, Utilities/
│   ├── Commands/AppCommands.swift           # macOS Help/menu commands (Visit Website, Rate, Send Feedback, Privacy Policy)
│   └── NALI_Migraine_Log_macOSApp.swift
│
├── NALI Migraine Log Watch App Watch App/   # watchOS app target (synchronized root)
│   ├── Views/
│   └── NALI_Migraine_Log_Watch_AppApp.swift
│
├── NALI Migraine LogTests/                  # Unit tests (run on iOS simulator, ~63 tests)
├── NALI Migraine Log macOSTests/            # Stub only (no real coverage yet)
├── NALI Migraine Log Watch App Watch AppTests/  # Stub only
│
├── .github/workflows/ci.yml                 # Build + test on every push/PR
├── ML_PREDICTION_GUIDE.md                   # Deep dive on the risk-scoring engine
├── WEATHER_FEATURE_GUIDE.md                 # Open-Meteo integration & caching
├── SPLASH_SCREEN_DESIGN.md                  # Launch screen rationale
└── iOS_26_LOCATION_CHANGES.md               # CoreLocation behavioral notes for iOS 26
```

The three app targets all share `NALI Migraine Log/` as a synchronized root group. Anything dropped into that folder is automatically compiled into all three apps unless explicitly excluded in `project.pbxproj`'s `PBXFileSystemSynchronizedBuildFileExceptionSet` section.

---

## Architecture at a glance

| Layer | Where | Notes |
|---|---|---|
| **Persistence** | `Shared/Models/PersistenceController.swift` | Single `NSPersistentCloudKitContainer` shared across all 3 targets. Includes lightweight migration, store recovery (move-aside), and a documented schema-migration playbook at the top of the file. |
| **Schema** | `Shared/NALI_Migraine_Log.xcdatamodeld` | One model, one entity (`MigraineEvent`). Boolean trigger/medication columns are wrapped by enum facades for type safety. |
| **Enum facades** | `Shared/Models/MigraineTrigger.swift`, `MigraineMedication.swift` | Strongly-typed `Set<Enum>` views over Core Data booleans. Always read/write through the facade — never touch the booleans directly. |
| **Logging** | `Shared/Services/AppLogger.swift` | Thin `os.Logger` wrapper with categories (`general`, `coreData`, `prediction`, `weather`, `migration`, `notifications`, `background-tasks`, …). Use it instead of `print` / `NSLog`. |
| **Risk prediction** | `Shared/Services/{FeatureExtractor,MigrainePredictionService}.swift` | Two-tier hybrid (rule-based + CoreML). See [`ML_PREDICTION_GUIDE.md`](./ML_PREDICTION_GUIDE.md). |
| **Weather** | `Shared/Services/{WeatherService,WeatherForecastService}.swift` | Open-Meteo (no key). See [`WEATHER_FEATURE_GUIDE.md`](./WEATHER_FEATURE_GUIDE.md). |
| **HealthKit (read + write)** | `Shared/Services/HealthKitManager.swift` | Reads sleep/HRV/menstruation for prediction features and **writes** logged migraines back to Apple Health as `HKCategorySample` of type `.headache` when the user opts in (Settings → Apple Health). Deduplicated via `HKMetadataKeyExternalUUID` so re-running backfill is idempotent. iOS 17+/watchOS 10+ for the write path. Also exposes `fetchSleepHoursPerNight(in:)`, `fetchHRVSamples(in:)`, `fetchMenstrualEvents(in:)`, and a cheap `hasAnyMenstrualHistory()` probe — historical fetchers used by the Analytics correlation cards (sleep, HRV, cycle-phase). |
| **Notifications** | `Shared/Services/NotificationManager.swift` (iOS-only) | Owns every `UNUserNotification` we schedule. Two independently-toggleable kinds: **forecast-risk** (fires only when the next 24 h forecast contains an hour the prediction engine scores ≥ 0.65 risk *and* the user has logged ≥ 5 migraines) and **re-engagement** (fires once a user has been silent for ≥ 14 days; never asks "how are you feeling?" per product direction). Permissions are requested lazily the first time the user enables a toggle. |
| **Background tasks** | `Shared/Services/BackgroundTaskScheduler.swift` (iOS-only) | Single `BGAppRefreshTask` (`com.neuroli.Headway.refresh`) registered in `App.init()` and rescheduled on every `scenePhase == .background`. The handler refreshes the weather forecast, recomputes risk, and lets `NotificationManager.reconcileAllNotifications()` schedule/cancel pushes. Identifier and `UIBackgroundModes` are declared in the iOS `Info.plist`. |
| **App Intents / Siri** | `NALI Migraine Log/AppIntents/LogMigraineIntent.swift` (iOS 17+) | Voice-activated "Log a migraine" with optional pain-level and notes parameters. Saves directly to the `viewContext`, calls `ReviewPromptCoordinator.recordEntryLogged()`, and mirrors to HealthKit through the same code path the in-app `addMigraine` uses. Discovered via `HeadwayAppShortcuts: AppShortcutsProvider`. |
| **Watch ↔ iPhone** | `Shared/WatchConnectivityManager.swift` | Bidirectional message + application-context bridge. |
| **Migration coordinator** | `Shared/Services/MigrationCoordinator.swift` | Per-launch version-change hook. Empty `upgradeSteps` registry today; documented for one-line future additions. |
| **Review prompt** | `Shared/Services/ReviewPromptCoordinator.swift` + iOS `Views/EnjoymentPromptView.swift` | "Enjoying Headway?" pre-prompt that gates Apple's `requestReview`. Tracks tenure (≥7 days), entries logged (≥5), and per-outcome cooldowns (180d after Yes, 365d after No) in `UserDefaults`. iOS-only UI; macOS uses an unconditional "Rate" menu command instead. |
| **In-app feedback** | iOS `Views/FeedbackFormView.swift` | Routes the "Not really" path of the enjoyment prompt to a category + star + free-text form, then hands off to `MFMailComposeViewController` (clipboard fallback if mail isn't configured). All iOS-only — guarded by `#if os(iOS)` so the file is a no-op on macOS/watchOS targets. |
| **Adaptive root layout** | `NALI Migraine Log/iOSContentView.swift` | Single source of truth for top-level navigation. The four destinations (`Log`, `Calendar`, `Analytics`, `About`) live in one `AppDestination` enum that drives both the iPhone `TabView` and the iPad `NavigationSplitView` sidebar. Adding a fifth destination is a one-line enum-case change. |
| **Analytics dashboard** | `NALI Migraine Log/Views/StatisticsView.swift` + `Views/Analytics/*` | "Overview"-style KPI grid (8 tiles) that drills into per-metric detail screens via `NavigationLink(value:)` + `navigationDestination(for: AnalyticsMetric.self)`. Replaces the old 1-10 pain histogram with a 4-bucket severity bar chart (Mild / Moderate / Severe / Extreme); adds a 60–90 day severity heatmap, an auto-generated insights section, and HealthKit-backed correlation cards (sleep on migraine eves, HRV in the 72 h prodromal window). Pure-data metric helpers (`severityBucketDistribution`, `currentMigraineFreeStreak`, `topTrigger`, `dailyPainCells(in:)`, `mostCommonWeekday`) live as `Array where Element == MigraineEvent` extensions in `AnalyticsComputations.swift` so they're trivially unit-testable. The HealthKit comparisons live in `HealthCorrelationStore` (a `@MainActor ObservableObject` that caches `(window, migraineCount)` and exposes pure `static computeSleepCorrelation` / `computeHRVCorrelation`) so the stats logic can be tested without HealthKit. |
| **Contact / app metadata** | `Shared/AppContactInfo.swift` | Single source of truth for the App Store ID, support email (`support@cicgconsulting.com`), practice website (`neuroli.com`), and privacy-policy URL. All four entry points (iOS About, iOS Settings, macOS About, macOS Help menu) read from here so updating any of them is a one-line edit. |

---

## Requirements

| Tool | Version |
|---|---|
| Xcode | 16.4 or newer (the project deploys to iOS 18.6 / macOS 15.2 / watchOS 11.6) |
| macOS | macOS 14 (Sonoma) or newer for the host machine |
| Devices | An iCloud-signed-in device (or simulator with iCloud) is required for the CloudKit sync path to actually exercise. |

No third-party dependencies. No package manager. No code generation step. `git clone` and open `NALI Migraine Log.xcodeproj` is the entire setup.

---

## Build & run

### From Xcode

1. Open `NALI Migraine Log.xcodeproj`.
2. Pick one of the four shared schemes from the toolbar:
   - `NALI Migraine Log` — iOS app
   - `NALI Migraine Log Debug` — iOS app with extra logging baked in
   - `NALI Migraine Log macOS` — macOS app
   - `NALI Migraine Log Watch App Watch App` — watchOS app (needs a paired-pair simulator)
3. Pick a destination and ⌘R.

### From the command line

```sh
# iOS — build & test the unit suite (uses your local dev signing identity)
xcodebuild test \
  -project "NALI Migraine Log.xcodeproj" \
  -scheme "NALI Migraine Log" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -parallel-testing-enabled NO \
  -skip-testing:"NALI Migraine LogUITests"

# macOS — host-Mac build
xcodebuild build \
  -project "NALI Migraine Log.xcodeproj" \
  -scheme "NALI Migraine Log macOS" \
  -destination 'platform=macOS'

# watchOS — generic build
xcodebuild build \
  -project "NALI Migraine Log.xcodeproj" \
  -scheme "NALI Migraine Log Watch App Watch App" \
  -destination 'generic/platform=watchOS Simulator'
```

Two things that are not negotiable for the iOS test path:

- **`-parallel-testing-enabled NO`**. Parallel testing clones the simulator, and the cloned simulator without an iCloud account triggers a `SIGTRAP` inside `-[PFCloudKitSetupAssistant _initializeCloudKitForObservedStore:]` on launch. Serial runs avoid it.
- **Don't pass `CODE_SIGNING_ALLOWED=NO`**. Stripping signing also strips the `com.apple.developer.icloud-services` entitlement, which makes `NSPersistentCloudKitContainer` refuse to load the store, which crashes the host app during `App.init()`, which prevents the test runner from bootstrapping. Use ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) if you need to bypass real provisioning — that's what the CI workflow does.

---

## Tests

Currently ~63 real unit tests live in `NALI Migraine LogTests/`:

| File | What it covers |
|---|---|
| `FeatureExtractorTests.swift` | Frequency/recency windows, trigger/med counts, weather pass-through, hour/day-of-week histograms |
| `MigrainePredictionServiceTests.swift` | Empty-history guard, score clamping, monotonicity, prediction source labels |
| `MigraineEventFacadeTests.swift` | Round-trip behavior for `Set<MigraineTrigger>` / `Set<MigraineMedication>` and canonical ordering |
| `MigraineTriggerTests.swift` | Display names, search keywords, legacy aliases, whitespace tolerance, `allCases` order |
| `MigraineMedicationTests.swift` | Display names, search keywords, legacy spelling tolerance (e.g. `ibuprofin`) |
| `ReviewPromptCoordinatorTests.swift` | Every gate of the review-prompt policy: baseline state, `recordLaunch` idempotency, entry-counter monotonicity, all rejection paths (tenure too short, too few entries, both cooldowns), happy-path opening, and the conservative "prompt shown but no outcome → 365-day cooldown" branch. Uses `@Suite(.serialized)` + per-test `UserDefaults` suite + injectable clock so the static coordinator is fully isolated. |

The macOS and Watch test bundles exist but contain only Xcode-generated stubs — they're targets to grow into, not coverage to rely on.

---

## CI

`.github/workflows/ci.yml` runs three jobs in parallel on every push to `main` and every pull request:

1. **`test-ios`** — full unit suite on `iPhone 16, OS=latest` simulator, serial.
2. **`build-macos`** — host-Mac build.
3. **`build-watch`** — generic watchOS Simulator build.

Code signing is disabled across the board. xcresult bundles are uploaded as artifacts on every run for postmortem.

To re-run failed jobs without a new commit, use the **Re-run jobs** button in the GitHub Actions UI, or trigger `workflow_dispatch` from the Actions tab.

---

## Coding conventions

- **Logging**: `AppLogger.<category>.notice/info/debug/error("…")`. Never `print()` or `NSLog()` in shipping code. Use Swift's privacy interpolation modifiers for anything that might be PII (`\(value, privacy: .public)` only when it's safe).
- **Trigger/medication access**: read and write through `event.triggers` / `event.medications` (the `Set<Enum>` facades on `MigraineEvent`). The underlying boolean columns are an implementation detail — touching them directly bypasses validation, ordering, and aliasing.
- **Accessibility**: every interactive control gets at minimum an `.accessibilityLabel` and `.accessibilityHint`. Combine related sub-elements with `.accessibilityElement(children: .combine)` so VoiceOver doesn't read every label individually.
- **Comments**: explain *intent* and *trade-offs*, not what the next line obviously does. A good comment is one that prevents a future reader from re-deriving a non-obvious decision.
- **Concurrency**: SwiftUI views are `MainActor`-isolated by default. Long-running work (Core Data fetches, weather requests, prediction inference) lives in services and returns to the main actor for UI updates. Don't block `@main` `App.init()`.
- **No third-party deps**: keeping the dependency graph empty is a feature, not an accident. If something seems to need a library, talk it through first.
- **Contact info**: read every email, URL, App Store ID, and support phone from `Shared/AppContactInfo.swift`. Hardcoding these inline drifts immediately and breaks the four-surface privacy/feedback parity (iOS About, iOS Settings, macOS About, macOS Help menu).
- **Engagement counter**: when adding a new "user did something meaningful with the core feature" code path (e.g. logged a migraine, completed onboarding, exported data), call `ReviewPromptCoordinator.recordEntryLogged()` after the success branch. The counter only fires on the *initial* successful save in `MigraineViewModel.addMigraine` today — additional surfaces should be conservative (one increment per user-perceived action, not per Core Data save).
- **Dynamic Type for custom Optima fonts**: every `.font(.custom("Optima-…", size: N))` call must pass `relativeTo:` so the size scales with the user's accessibility settings. The matching text-style is whatever is closest in Apple's hierarchy (`.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.subheadline`, `.callout`, `.caption`). Bare `.custom(_, size:)` without `relativeTo:` is forbidden — it ships a fixed-size font that ignores Dynamic Type and fails accessibility review.
- **Optionals over force-unwraps in concurrency**: `try await group.next()!` and similar patterns trap when a task group exits unexpectedly (cancelled parent, runtime drain, future Swift behavior changes). Always `guard let` the result and either `throw` a typed error or fall through to a sane default. The pattern in `MigraineViewModel.withTimeout` is the reference implementation.
- **Adaptive layout**: any change to top-level destinations goes through the `AppDestination` enum in `iOSContentView.swift`. Don't sprinkle `if UIDevice.current.userInterfaceIdiom == .pad` checks across views — the existing `horizontalSizeClass` switch handles iPad-vs-iPhone (and Plus/Pro Max landscape) globally and uniformly. Each destination still owns its own `NavigationStack`; that's intentional so the detail column on iPad keeps an independent back history per destination.

---

## Notifications & background tasks

The user-visible behavior is two toggles in **Settings → Notifications**: *Forecast risk alerts* and *Re-engagement reminders*. Internally that maps to:

| Concern | Owner | Notes |
|---|---|---|
| Authorization | `NotificationManager.requestAuthorization()` | Requested lazily on the first toggle flip. We deliberately don't ask on cold launch — users who don't care shouldn't see the system prompt at all. |
| Forecast push | `NotificationManager.scheduleForecastRiskNotificationIfNeeded(migraines:forecast:)` | Runs the forecast through `MigrainePredictionService.generate24HourForecast(...)`, picks the first hour at or above `highRiskThreshold` (0.65), and schedules a single `UNCalendarNotificationTrigger` ~2 hours before that hour. Identifier is derived from the trigger hour, so re-runs replace rather than stack. |
| Re-engagement push | `NotificationManager.scheduleReengagementNotificationIfNeeded(...)` | Repeats daily at 7 pm local *only after* `reengagementDays` (default 14) since the user's most recent entry. Cancelled automatically on every `.active` `scenePhase`. Body is intentionally gentle — never a wellness check, never asks how the user feels. |
| Reconcile-all | `NotificationManager.reconcileAllNotifications(migraines:forecast:)` | The single entry point used by `App.init()`'s scenePhase observer and by the BG task handler. Idempotent — safe to call on every app cycle. |
| BG task identifier | `BackgroundTaskScheduler.refreshIdentifier` | `com.neuroli.Headway.refresh`. Must also appear in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`. Adding a new BG task means **both** registering it in `BackgroundTaskScheduler.register()` *and* adding its identifier to the plist — the system rejects unregistered or unlisted identifiers silently. |
| BG scheduling cadence | `BackgroundTaskScheduler.scheduleNextRefresh()` | Submits a `BGAppRefreshTaskRequest` with a `refreshInterval` minimum gap. iOS coalesces the actual run with system-decided thermal/charge windows — we cannot force a specific delay, only a *minimum*. |
| BG work | `BackgroundTaskScheduler.performRefreshWork()` | Fetches location → forecast → recent migraines → calls `reconcileAllNotifications`. Must complete inside iOS's BG-task runtime budget (~30s). All Core Data work runs on the `viewContext` because the dataset is small; switch to a private context if a future feature crosses ~10 k rows. |

**Testing notes**

- Forecast pushes need **≥ 5 historical migraines** in the test dataset *and* a forecast-hour above 0.65 risk to fire. Below either threshold, the scheduler logs at `.debug` level and no-ops.
- Re-engagement pushes need a stale dataset — the simplest way to exercise locally is to set the system clock 15 days forward.
- BG tasks won't run in the simulator without `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.neuroli.Headway.refresh"]` from the LLDB prompt while the app is foregrounded *and* a request has already been submitted (i.e. you've backgrounded the app at least once first).
- Flipping a toggle off cancels in-flight pushes synchronously via the scheduler's `cancel*Notifications()` methods. There is no "pending" middle state.

---

## HealthKit write-back

When the user enables **Settings → Apple Health → Sync to Apple Health**, every `addMigraine` / `updateMigraine` / `deleteMigraine` call writes (or deletes) a matching `HKCategorySample` of type `.headache`. This is iOS 17+/watchOS 10+ only — older OS versions silently no-op. Implementation lives in `HealthKitManager.writeMigraineToHealth(_:)`, `mirrorDeletion(ofMigraineUUID:)`, and `backfillMigrainesToHealth()`.

- **Deduplication**: every sample is tagged with `HKMetadataKeyExternalUUID = migraineEvent.id.uuidString`, so the backfill button is idempotent — running it 100 times produces the same n samples, not 100 n.
- **Severity mapping**: app's 1–10 pain scale → `HKCategoryValueSeverity` (1–3 mild, 4–6 moderate, 7–9 severe, 10 unspecified→severe).
- **Permissions are revocable**: the user can disable HealthKit in **Settings → Privacy & Security → Health**. Our `writeTypes` request is wrapped in a `do/catch` and logs at `.error` level on denial; we do not crash and we do not retry.
- **Privacy description**: `NSHealthUpdateUsageDescription` is required in iOS `Info.plist` *in addition* to `NSHealthShareUsageDescription`. App Store review rejects builds that write without the second key.

---

## Analytics dashboard

The Analytics tab (titled **"Overview"** at the top) is structured as a tap-to-drill-down dashboard rather than a flat scroll of charts.

- **Top of screen — KPI grid (8 tiles, 2 × 4):**
  - *Total*, *Avg Pain*, *Severe Days* (unique days with pain ≥ 7), *Migraine-free* streak (days since last logged migraine, full history)
  - *Avg Duration*, *Top Trigger*, *Days Missed* (cumulative work + school + events), *Abortives Used*
  - Every tile is a `NavigationLink(value: AnalyticsMetric)`. The destination is `AnalyticsMetricDetailView`, switched on the metric, which reuses the legacy bar/pie/line charts in a focused single-metric layout.
- **Severity Distribution chart (replaces the old 10-bin pain histogram):** four buckets — *Mild* (1-3), *Moderate* (4-6), *Severe* (7-8), *Extreme* (9-10). Counts annotate each bar; bucket subtitles preserve the underlying numeric range.
- **Trends section:** a calendar-style severity heatmap (60-day window for week/month, 90-day for year/range) plus a compact "migraines per month" bar chart. The heatmap honours `Calendar.firstWeekday` for localized layout.
- **Insights section:** auto-generated cards from `AnalyticsInsightGenerator.generate(...)`. The generator only emits a card when the underlying signal is strong enough to be useful (e.g. ≥30% trigger share, ≥7-day streak, ≥50% severe-pain proportion). Cap is four cards.
- **Health Correlations section:** up to three cards (Sleep, HRV, and a full-width Cycle card) sourced from `HealthCorrelationStore`. Sleep compares average hours on the night before a migraine vs. all other nights inside the active window; HRV compares the mean SDNN in the 72 h before each onset vs. all other moments. The Cycle card buckets each migraine into the menses / follicular / ovulatory / luteal phase relative to the most recent menstrual-flow start in HealthKit — and surfaces the share that fell in the perimenstrual (days 26-3) window most associated with estrogen-withdrawal migraine. Cycle visibility is **data-driven, not identity-driven**: the card only appears when the user has actually logged menstrual flow in Apple Health (probed once per launch via `hasAnyMenstrualHistory()`), so we never gate the feature on biological-sex metadata. Cards hide when HealthKit isn't available, prompt for authorization when not yet granted, and drill into full per-metric detail screens (with cycle-day histogram + phase breakdown for the Cycle metric) via the same `AnalyticsMetric` navigation path.
- **Bottom:** existing Life Impact card + Weather Correlation deep-link, unchanged.

All migraine-only metric helpers are pure functions on `[MigraineEvent]` (see `Views/Analytics/AnalyticsComputations.swift`). HealthKit-derived comparisons live behind `HealthCorrelationStore` (`Views/Analytics/HealthCorrelationStore.swift`), which caches the latest `(window, migraineCount)` so dashboard re-renders don't re-hit HealthKit; only filter or migraine-list changes trigger a refetch. The store also tracks `cycleAvailability` (`.unknown` / `.notTracked` / `.available`) so the cycle card hides cleanly for users who don't log menstrual flow. The store calls `HealthKitManager.fetchSleepHoursPerNight(in:)`, `fetchHRVSamples(in:)`, and `fetchMenstrualEvents(in:)` — historical fetchers that complement the existing snapshot fetchers used by the prediction engine — and exposes pure `static computeSleepCorrelation` / `computeHRVCorrelation` / `computeCyclePhaseDistribution` so the stats logic is testable without HealthKit. Adding a new tile is still `enum AnalyticsMetric { case foo }` + a computed property + a switch case in `AnalyticsMetricDetailView`; if it needs HealthKit, gate `requiresHealthKit` and read from the store passed into the detail view.

---

## Schema migration playbook

The full procedure lives at the top of [`Shared/Models/PersistenceController.swift`](./Shared/Models/PersistenceController.swift) — read it before touching the `.xcdatamodeld`. Quick summary:

1. **Lightweight changes** (add an attribute, add an entity, rename via renaming identifier) are handled automatically by `NSPersistentCloudKitContainer`. Just create a new model version.
2. **Non-trivial changes** (split an entity, change a relationship's cardinality, complex value transforms) need a hand-written `.xcmappingmodel`.
3. After **any** schema change: bump the `xcdatamodel` version, set the renaming identifier where applicable, run **CloudKit Dashboard → Initialize CloudKit Schema** for the new model, bump `CFBundleShortVersionString`, and consider whether a one-time data backfill needs to land in `MigrationCoordinator.upgradeSteps`.
4. **One-time data backfills** (normalize a free-text field, re-bucket renamed enum values, wipe a stale `UserDefaults` key) live in `Shared/Services/MigrationCoordinator.swift`. The registry is empty today; the file's docblock walks through the template.
5. If a store ever fails to load, `PersistenceController.handlePersistentStoreError(...)` moves it aside, records its path in `UserDefaults`, and a banner appears at the top of the iOS log so the user can recover the file from Settings.

---

## Privacy & App Store notes

- **Privacy manifest**: each `.app` bundle ships its own `PrivacyInfo.xcprivacy` because synchronized root groups only auto-include `.xcprivacy` files in their owning target — they do **not** propagate to other targets that consume the same root. The three siblings live at:
  - [`NALI Migraine Log/PrivacyInfo.xcprivacy`](./NALI%20Migraine%20Log/PrivacyInfo.xcprivacy) — declares `UserDefaults` (`CA92.1`) **and** `FileTimestamp` (`C617.1`) for the recovery-file UI
  - [`NALI Migraine Log macOS/PrivacyInfo.xcprivacy`](./NALI%20Migraine%20Log%20macOS/PrivacyInfo.xcprivacy) — `UserDefaults` only
  - [`NALI Migraine Log Watch App Watch App/PrivacyInfo.xcprivacy`](./NALI%20Migraine%20Log%20Watch%20App%20Watch%20App/PrivacyInfo.xcprivacy) — `UserDefaults` only

  When adding a new required-reason API anywhere in the codebase, **update every file the API actually appears in**. Apple does not allow under-declaration; over-declaration is harmless.
- **No tracking, no third-party data sharing.** All HealthKit, location, weather, and migraine data either stays on-device or syncs through the user's own iCloud private database.
- **Privacy policy URL**: `https://cicgconsulting.com/headway-privacy-policy`, hosted on the developer's registered domain (`cicgconsulting.com`) — distinct from the practice site (`neuroli.com`) that the "Visit Website" / "About Practice" links point to. The single source of truth is `AppContactInfo.privacyPolicyURL`. Surfaced in four places:
  - iOS `AboutView` — link under the "Your Privacy" section
  - macOS `AboutView` — link under the "Your Privacy" section
  - iOS `SettingsView` — row in the "Help & Feedback" section
  - macOS Help menu — "Privacy Policy" command
  Apple **also requires** this URL in App Store Connect → App Privacy → Privacy Policy URL. Keep the in-app constant and the App Store Connect field in sync — they are independent surfaces and changing one does not update the other.
- **Contact info, support email, App Store ID** all live in `Shared/AppContactInfo.swift`. Update there once and every UI surface (About, Settings, Help menu, feedback `mailto:` URLs, App Store deep links) picks up the change at the next build. **Do not** hardcode any of these values inline in Views.
- **In-app review & feedback flow**: Apple's `requestReview()` is gated by the "Enjoying Headway?" pre-prompt in `EnjoymentPromptView` — `Yes` calls `requestReview()`, `Not really` opens `FeedbackFormView` (in-app form, sends via the user's mail client to `support@cicgconsulting.com`). The full gating policy (tenure, entry-count, cooldowns) lives in `ReviewPromptCoordinator`; constants are tunable at the top of that file. Both UI files are wrapped in `#if os(iOS)` because they depend on `StoreKit`/`UIKit`/`MessageUI`; macOS gets straight-shot menu commands instead.
- **Version bumps before App Store upload**: bump `MARKETING_VERSION` (visible to users, gates `MigrationCoordinator` upgrade steps) and `CURRENT_PROJECT_VERSION` (the build number, must monotonically increase per release) in **all three** targets' build settings. Forgetting either is the most common upload rejection.
- **Entitlements**: each target has its own `.entitlements` file declaring CloudKit, HealthKit, App Sandbox (macOS), etc. Don't add capabilities ad-hoc in Xcode's Signing & Capabilities tab without checking that all three targets stay in sync where it matters (specifically the iCloud container ID).

---

## Deeper reading

- [`ML_PREDICTION_GUIDE.md`](./ML_PREDICTION_GUIDE.md) — feature extraction, two-tier scoring, model lifecycle.
- [`WEATHER_FEATURE_GUIDE.md`](./WEATHER_FEATURE_GUIDE.md) — Open-Meteo integration and caching strategy.
- [`SPLASH_SCREEN_DESIGN.md`](./SPLASH_SCREEN_DESIGN.md) — launch experience design notes.
- [`iOS_26_LOCATION_CHANGES.md`](./iOS_26_LOCATION_CHANGES.md) — CoreLocation API delta we have to live with on iOS 26.
- Inline docblocks at the top of `PersistenceController.swift` and `MigrationCoordinator.swift` — required reading before any data-layer change.

---

## License

Personal project; no public license declared yet. Treat as "all rights reserved" until that changes.
