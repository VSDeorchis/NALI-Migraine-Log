# NALI Migraine Log

A privacy-first migraine tracker for iPhone, Apple Watch, and Mac. Logs are stored on-device with Core Data and synced exclusively through the user's own iCloud account via `NSPersistentCloudKitContainer` — no developer-side servers, no analytics, no third-party SDKs.

The app combines a manual logging UI with a hybrid risk-prediction engine (rule-based + on-device CoreML) that uses the user's history and a free public weather API ([Open-Meteo](https://open-meteo.com/)) to surface a forecast risk score.

---

## Repository layout

```
.
├── Shared/                                  # Code compiled into all 3 targets
│   ├── Models/                              # Core Data classes + enum facades
│   ├── Services/                            # Logger, persistence, prediction, weather, location, HealthKit, migration
│   ├── NALI_Migraine_Log.xcdatamodeld/      # The single source of truth for the schema
│   └── WatchConnectivityManager.swift       # iPhone ↔ Watch payload bridge
│
├── NALI Migraine Log/                       # iOS app (synchronized root group; ALSO consumed by macOS + Watch targets)
│   ├── Views/, ViewModels/, Utilities/      # iOS-specific UI
│   ├── PrivacyInfo.xcprivacy                # Shared privacy manifest (one per .app bundle)
│   ├── Info.plist
│   └── NALI_Migraine_LogApp.swift           # @main entry point
│
├── NALI Migraine Log macOS/                 # macOS app target (synchronized root)
│   ├── Views/, ViewModels/, Commands/, Utilities/
│   └── NALI_Migraine_Log_macOSApp.swift
│
├── NALI Migraine Log Watch App Watch App/   # watchOS app target (synchronized root)
│   ├── Views/
│   └── NALI_Migraine_Log_Watch_AppApp.swift
│
├── NALI Migraine LogTests/                  # Unit tests (run on iOS simulator, ~48 tests)
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
| **Logging** | `Shared/Services/AppLogger.swift` | Thin `os.Logger` wrapper with categories (`general`, `coreData`, `prediction`, `weather`, `migration`, …). Use it instead of `print` / `NSLog`. |
| **Risk prediction** | `Shared/Services/{FeatureExtractor,MigrainePredictionService}.swift` | Two-tier hybrid (rule-based + CoreML). See [`ML_PREDICTION_GUIDE.md`](./ML_PREDICTION_GUIDE.md). |
| **Weather** | `Shared/Services/{WeatherService,WeatherForecastService}.swift` | Open-Meteo (no key). See [`WEATHER_FEATURE_GUIDE.md`](./WEATHER_FEATURE_GUIDE.md). |
| **Watch ↔ iPhone** | `Shared/WatchConnectivityManager.swift` | Bidirectional message + application-context bridge. |
| **Migration coordinator** | `Shared/Services/MigrationCoordinator.swift` | Per-launch version-change hook. Empty `upgradeSteps` registry today; documented for one-line future additions. |

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

Currently ~48 real unit tests live in `NALI Migraine LogTests/`:

| File | What it covers |
|---|---|
| `FeatureExtractorTests.swift` | Frequency/recency windows, trigger/med counts, weather pass-through, hour/day-of-week histograms |
| `MigrainePredictionServiceTests.swift` | Empty-history guard, score clamping, monotonicity, prediction source labels |
| `MigraineEventFacadeTests.swift` | Round-trip behavior for `Set<MigraineTrigger>` / `Set<MigraineMedication>` and canonical ordering |
| `MigraineTriggerTests.swift` | Display names, search keywords, legacy aliases, whitespace tolerance, `allCases` order |
| `MigraineMedicationTests.swift` | Display names, search keywords, legacy spelling tolerance (e.g. `ibuprofin`) |

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
