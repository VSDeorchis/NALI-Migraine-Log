# NALI Migraine Log ("Headway")

A privacy-first migraine tracker for iPhone, iPad, Apple Watch, and Mac. Entries are stored on-device with Core Data and synced exclusively through the user's own iCloud account via `NSPersistentCloudKitContainer` — no developer-side servers, no analytics, no third-party SDKs.

The app combines a manual logging UI with a hybrid risk-prediction engine (rule-based + on-device Core ML) that uses the user's history, Apple Health signals (sleep, HRV, optional menstrual cycle) and a free public weather API ([Open-Meteo](https://open-meteo.com/)) to surface a forecast risk score, plus an analytics dashboard built around clinical burden metrics (headache days, acute-medication days, cycle association).

Current release: **3.01 (build 15)** — see [`CHANGELOG.md`](./CHANGELOG.md).

---

## Repository layout

```
.
├── Config/Shared.xcconfig                   # Versions, deployment targets, Swift 6 language mode — shared by all targets
├── Shared/                                  # Code compiled into all 3 apps
│   ├── Models/                              # Core Data classes, enum facades, drafts, risk score, sync status
│   │   └── Sync/                            # Watch wire formats: MigraineSyncRecord (entries), WatchRiskPayload (risk)
│   ├── Services/                            # Logger, launch/migration coordinators, prediction, weather, location, HealthKit,
│   │                                        #   cycle insights, ML confidence, notifications, BG-task scheduler, CSV encoding
│   ├── ViewModels/MigraineStore.swift       # Platform-neutral Core Data store the iOS/macOS view models subclass
│   ├── NALI_Migraine_Log.xcdatamodeld/      # The single source of truth for the schema (current model adds `modifiedAt`)
│   ├── AppContactInfo.swift                 # Centralized App Store ID, support email, website, privacy-policy URL
│   └── WatchConnectivityManager.swift       # iPhone ↔ Watch sync protocol (v2 deltas/snapshots/tombstones + risk)
│
├── NALI Migraine Log/                       # iOS app (synchronized root group)
│   ├── Views/                               # SwiftUI screens (Log, Calendar, Predict, Analytics, About, Settings, …)
│   ├── Views/Analytics/                     # Dashboard: computations, burden metrics, charts, cycle card, drill-downs, TipKit tips
│   ├── ViewModels/                          # MigraineViewModel + extensions (Weather, CloudSync, Analytics, Debug)
│   ├── Utilities/                           # Constants, SettingsManager, WhatsNew gating, RiskSyncCoordinator, accessibility modifiers
│   ├── AppIntents/                          # Siri / Shortcuts: LogMigraineIntent, OpenNewEntryIntent, MigraineEntity (Spotlight)
│   ├── iOSContentView.swift                 # Adaptive root: TabView on iPhone, NavigationSplitView on iPad
│   ├── Localizable.xcstrings                # String Catalog (one per app target)
│   ├── PrivacyInfo.xcprivacy                # Privacy manifest (one per .app bundle)
│   └── NALI_Migraine_LogApp.swift           # @main — registers the BG task, drives launch/migration, What's New, Health primer
│
├── NALI Migraine Log macOS/                 # macOS app target (Table-based list, Commands, fileExporter)
├── NALI Migraine Log Watch App Watch App/   # watchOS app target (3-page quick log, synced risk with persisted last score)
│
├── NALI-Migraine-Log-Info.plist             # iOS Info.plist (background modes, BG task ids, usage strings)
├── NALI-Migraine-Log-Watch-App-Watch-App-Info.plist
│
├── NALI Migraine LogTests/                  # Unit tests (Swift Testing, ~190 tests across 22 suites)
├── NALI Migraine LogUITests/                # Launch smoke tests
├── NALI Migraine Log macOSTests/            # Stub only
├── NALI Migraine Log Watch App Watch AppTests/  # Stub only
│
├── .github/workflows/ci.yml                 # SwiftLint + iOS tests + macOS/watchOS builds on every PR
├── .swiftlint.yml                           # Lint rules (CI runs --strict)
├── CHANGELOG.md                             # User-visible and engineering changes per release
├── ML_PREDICTION_GUIDE.md                   # Deep dive on the risk-scoring engine
├── WEATHER_FEATURE_GUIDE.md                 # Open-Meteo integration & caching
├── PRIVACY_MANIFEST_NOTES.md                # Why the .xcprivacy files look the way they do (read before editing them)
├── SPLASH_SCREEN_DESIGN.md                  # Launch screen rationale
└── iOS_26_LOCATION_CHANGES.md               # CoreLocation behavioral notes for iOS 26
```

The three app targets all share `Shared/` (and the iOS root for a few files) as synchronized groups. Anything dropped into `Shared/` is compiled into all three apps unless explicitly excluded in `project.pbxproj`'s `PBXFileSystemSynchronizedBuildFileExceptionSet` section; platform-only code is fenced with `#if os(iOS)` / `#if os(watchOS)`.

---

## Architecture at a glance

| Layer | Where | Notes |
|---|---|---|
| **Persistence** | `Shared/Models/PersistenceController.swift` | `@MainActor` owner of the single `NSPersistentCloudKitContainer` shared by all 3 targets. Store file is protected with `completeUntilFirstUserAuthentication`. Includes lightweight migration, store recovery (move-aside), CloudKit account/event monitoring → `SyncStatus`, and a documented schema-migration playbook at the top of the file. |
| **Schema** | `Shared/NALI_Migraine_Log.xcdatamodeld` | One entity (`MigraineEvent`). Boolean trigger/medication columns are wrapped by enum facades. `modifiedAt` drives last-writer-wins between iPhone and Watch. |
| **Enum facades** | `Shared/Models/MigraineTrigger.swift`, `MigraineMedication.swift` | Strongly-typed `Set<Enum>` views over Core Data booleans. Always read/write through the facade. Medications display as `generic (Brand)`; favourites are pinned via `MedicationFavorites`. |
| **Store / view models** | `Shared/ViewModels/MigraineStore.swift`, `NALI Migraine Log/ViewModels/MigraineViewModel*.swift`, `NALI Migraine Log macOS/ViewModels/MigraineViewModel.swift` | `MigraineStore` (`@MainActor`) owns the view context, the published entry list and every mutation (`MigraineDraft` in/out). The iOS subclass adds the fetched-results controller, weather enrichment, Health mirroring, Watch sync and CloudKit auto-sync (structured `Task` loops, not `Timer`s); the macOS subclass adds Table sorting/export. |
| **Launch & migrations** | `Shared/Services/AppLaunchCoordinator.swift`, `MigrationCoordinator.swift` | One-time launch work runs from a `.task` on the root view with a progress splash (no fixed delay). `MigrationCoordinator.upgradeSteps` is a version-gated registry of one-time data backfills — currently `v3.01-coarsen-weather-coordinates`. Steps are `@MainActor` closures over the view context. |
| **Logging** | `Shared/Services/AppLogger.swift` | Thin `os.Logger` wrapper with categories. Error descriptions default to `privacy: .private`. Use it instead of `print`. |
| **Risk prediction** | `Shared/Services/{FeatureExtractor,MigrainePredictionService,MLModelConfidence}.swift` | Two-tier hybrid (rule-based + on-device Core ML). ML confidence is derived from hold-out skill over the majority-class baseline, not a constant. See [`ML_PREDICTION_GUIDE.md`](./ML_PREDICTION_GUIDE.md). |
| **Risk publishing** | `NALI Migraine Log/Utilities/RiskSyncCoordinator.swift` | Single iPhone pipeline (forecast → Health snapshot → prediction → Watch push) used by the Predict tab, scene-active, background refresh and inbound Watch sync requests; throttled to once per 5 min. |
| **Weather** | `Shared/Services/{WeatherService,WeatherForecastService,OpenMeteoSupport}.swift` | Open-Meteo (no key). Timeouts, response-size and content-type checks, validated parsers, coordinate-keyed cache. Coordinates are coarsened to 2 decimals (~1 km) before storage and requests. See [`WEATHER_FEATURE_GUIDE.md`](./WEATHER_FEATURE_GUIDE.md). |
| **Location** | `Shared/Services/LocationManager.swift` | `@MainActor`; `CLLocationUpdate.liveUpdates()` for one-shot fixes, authorization probed off the launch path, no force-unwraps or continuous updates. |
| **HealthKit (read + write)** | `Shared/Services/HealthKitManager.swift` | Reads sleep, HRV, steps and (opt-in) menstrual flow + biological sex; writes logged migraines as `.headache` samples (deduplicated via `HKMetadataKeyExternalUUID`), mirrors deletions, detects revoked authorization, merges overlapping sleep samples. Reproductive-health values are used in memory only and never persisted, synced or exported. |
| **Cycle-aware insights** | `Shared/Services/MenstrualCycleInsights.swift` | Pure math: `CycleEligibility` (Health biological sex → `.male` hides the feature; `.undetermined` falls back to "has real cycle history"), `PerimenstrualWindow` (−2…+2 days around menses start). Feeds the log badge, the risk factor and the Analytics cycle card. |
| **Notifications** | `Shared/Services/NotificationManager.swift` (iOS-only) | Forecast-risk and re-engagement pushes behind two toggles. `UNUserNotificationCenter` is wrapped in completion-handler bridges that return only `Sendable` values (see Concurrency). |
| **Background tasks** | `Shared/Services/BackgroundTaskScheduler.swift` (iOS-only) | Single `BGAppRefreshTask` (`com.neuroli.Headway.refresh`) registered in `App.init()` on the main queue; refreshes forecast → risk → Watch → notifications. |
| **App Intents / Siri / Spotlight** | `NALI Migraine Log/AppIntents/` | `LogMigraineIntent`, `OpenNewEntryIntent`, `MigraineEntity` + query (Spotlight indexing), `HeadwayAppShortcuts`. Watch has its own intents in `WatchSiriIntents.swift`. |
| **Watch ↔ iPhone sync** | `Shared/WatchConnectivityManager.swift`, `Shared/Models/Sync/` | Protocol v2: each side sends *deltas* of its own edits via `transferUserInfo` (queued offline, acknowledged before dirty ids are cleared); the phone also publishes a compact *snapshot* through `updateApplicationContext`; deletions travel as tombstones (90-day retention). Conflicts resolve last-writer-wins on `modifiedAt`. Risk travels as a validated `WatchRiskPayload` (`riskUpdateV2`); the Watch persists the last adopted score and shows an explicit "no score yet" state instead of a fake 0%. |
| **What's New** | `NALI Migraine Log/Utilities/WhatsNew.swift`, `Views/WhatsNewView.swift` | One-time sheet per feature release (`currentRelease` key, not the marketing version); never shown on a fresh install. Rows are filtered by cycle eligibility. |
| **Review prompt / feedback** | `Shared/Services/ReviewPromptCoordinator.swift`, iOS `Views/FeedbackFormView.swift` | Native `requestReview()` gated on tenure ≥ 7 days, ≥ 5 entries, 180-day cooldown. Feedback form hands off to Mail. |
| **Adaptive root layout** | `NALI Migraine Log/iOSContentView.swift`, `AppNavigationCoordinator.swift` | `AppDestination` enum drives the iPhone `TabView` and the iPad `NavigationSplitView` sidebar, ⌘1–⌘4 shortcuts and deep links from intents. |
| **Settings hub** | `Views/SettingsView.swift` | Grouped into Data & Privacy / Integrations / Notifications / Appearance / About with permission chips and deep links to iOS Settings; two-pane on iPad. |
| **Analytics dashboard** | `Views/StatisticsView.swift` + `Views/Analytics/*` | Hero "Migraine days" card + KPI strip, Trends (severity heatmap, 12-month chart), Medication days gauge, Patterns, Insights, Cycle association, Health correlations, Life impact. See "Analytics dashboard" below. |
| **Accessibility** | `Shared/ScaledFont.swift`, `NALI Migraine Log/Utilities/AccessibilityModifiers.swift`, `Views/Analytics/BarChartAudioGraph.swift` | Dynamic Type for custom fonts, `AXChartDescriptor` audio graphs, Differentiate Without Colour glyphs (`SeverityBucket.symbolName`, `TrendSentiment.symbolName`), `motionSafeAnimation` / `motionSafeNumericTransition` for Reduce Motion. |
| **Localization** | `Localizable.xcstrings` in each app folder | String Catalogs; `Text("…")` literals are extracted at build time. Plural rules live in the catalog (e.g. heatmap summaries). |
| **Contact / app metadata** | `Shared/AppContactInfo.swift` | Single source of truth for App Store ID, support email, practice website, privacy-policy URL. |

---

## Requirements

| Tool | Version |
|---|---|
| Xcode | 16.4 (CI pins `Xcode_16.4.app`, iPhone 16 / iOS 18.5 simulator) |
| Swift | 6.0 language mode, `SWIFT_STRICT_CONCURRENCY = complete` (set in `Config/Shared.xcconfig`) |
| Deployment targets | iOS 18.2 · watchOS 11.2 · macOS 15.2 (`Config/Shared.xcconfig`) |
| SwiftLint | 0.65.0 (CI runs `swiftlint lint --strict`) |
| Devices | An iCloud-signed-in device (or simulator with iCloud) is required for the CloudKit sync path to actually exercise. |

No third-party dependencies. No package manager. No code generation step. `git clone` and open `NALI Migraine Log.xcodeproj` is the entire setup.

---

## Build & run

### From Xcode

1. Open `NALI Migraine Log.xcodeproj`.
2. Pick a scheme:
   - `NALI Migraine Log` — iOS app
   - `NALI Migraine Log Debug` — iOS app with extra logging baked in
   - `NALI Migraine Log macOS` — macOS app
   - `NALI Migraine Log Watch App Watch App` — watchOS app (needs a paired simulator)
3. Pick a destination and ⌘R.

### From the command line

```sh
# Lint (same command CI runs; Docker keeps the version pinned)
docker run --rm -v "$PWD":/work -w /work ghcr.io/realm/swiftlint:0.65.0 swiftlint lint --strict --quiet

# iOS — build & test the unit suite
xcodebuild test \
  -project "NALI Migraine Log.xcodeproj" \
  -scheme "NALI Migraine Log" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
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
- **Don't pass `CODE_SIGNING_ALLOWED=NO`**. Stripping signing also strips the `com.apple.developer.icloud-services` entitlement, which makes `NSPersistentCloudKitContainer` refuse to load the store, which crashes the host app during launch, which prevents the test runner from bootstrapping. Use ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) if you need to bypass real provisioning — that's what the CI workflow does.

---

## Tests

~190 Swift Testing tests live in `NALI Migraine LogTests/`:

| File | What it covers |
|---|---|
| `FeatureExtractorTests`, `MigrainePredictionServiceTests`, `MLModelValidationTests` | Feature windows/histograms, score clamping and monotonicity, hold-out confidence derivation (skill over baseline, clamped to floor/ceiling). |
| `MigraineEventFacadeTests`, `MigraineTriggerTests`, `MigraineMedicationTests` | `Set<Enum>` facades, display names (`generic (Brand)`), search keywords, legacy aliases. |
| `MigraineSyncRecordTests`, `WatchSyncResolutionTests`, `WatchRiskPersistenceTests` | Watch wire format round-trips and rejection of malformed payloads, last-writer-wins on `modifiedAt`, tombstones, risk payload adoption/staleness/persistence. |
| `AnalyticsBurdenMetricsTests`, `CycleAssociationAnalysisTests`, `MenstrualCycleInsightsTests` | Headache/medication days, duration median + IQR, weekday/symptom prevalence, completeness, perimenstrual window, rate ratio, confidence tiers, `n of last 3 cycles`, eligibility gate. |
| `WeatherResponseParsingTests`, `CoordinatePrivacyTests` | Open-Meteo parser validation (array lengths, timezone, units), 2-decimal coordinate coarsening and the 3.01 backfill. |
| `HealthKitSampleClampTests`, `DeleteAllDataTests`, `ICloudSyncPreferenceTests` | Severity mapping to HealthKit, delete-all completeness (Core Data, Health samples, tombstones, protected files), sync preference defaults. |
| `CSVFieldTests`, `WhatsNewGatingTests`, `ReviewPromptCoordinatorTests`, `AccessibilitySemanticsTests` | CSV quoting/injection, What's New once-per-release policy, review-prompt gates, Differentiate-Without-Colour glyph semantics. |

Suites that touch static/shared state (`WhatsNew.defaults`, `ReviewPromptCoordinator`) are `@MainActor` and/or `@Suite(.serialized)` with per-test `UserDefaults` suites. The macOS and Watch test bundles are Xcode stubs.

---

## CI

`.github/workflows/ci.yml` runs four jobs on every push to `main` and every pull request (whatever its base, so stacked PRs compile before they retarget `main`); in-flight runs for the same branch are cancelled when a newer push lands:

1. **Lint (SwiftLint)** — `swiftlint lint --strict` at the pinned version, on Ubuntu.
2. **Test (iOS)** — full unit suite on `iPhone 16, OS=18.5`, serial, Xcode 16.4.
3. **Build (macOS)** — host-Mac build.
4. **Build (watchOS)** — generic watchOS Simulator build.

Signing is ad-hoc across the board. xcresult bundles and raw logs are uploaded as artifacts on every run; when the iOS job reports "Test crashed with signal trap before starting test execution", the app crash log is inside the xcresult (`bug_type 309` JSON) — look at the `faultingThread` frames.

**Merging stacked PRs:** GitHub only retargets a stacked PR to `main` when its base PR is merged *first*. Merging the top of a stack before its base merges the code into the base *branch*, not `main` (this happened once with #38/#39 and needed a follow-up merge PR). Merge bottom-up, and check the PR's base branch before pressing Merge.

---

## Coding conventions

- **Swift 6 / concurrency**: the whole project builds in Swift 6 language mode with complete strict concurrency, and the rule is *make isolation explicit, never suppress it*.
  - `PersistenceController`, `MigraineStore`/view models, `LocationManager`, `HealthKitManager`, `NotificationManager`, `WatchConnectivityManager` and `BackgroundTaskScheduler` are `@MainActor`. Core Data contexts and `MigraineEvent`s never leave the main actor.
  - Framework callbacks that arrive on private queues (`WCSessionDelegate`, `CLLocationManagerDelegate`, `NSFetchedResultsControllerDelegate`, `NotificationCenter` blocks, `loadPersistentStores`) are `nonisolated` and hop via `MainActor.assumeIsolated` (when the queue *is* main) or `Task { @MainActor in … }`, passing only `Sendable` values (`InboundPayload`, `CloudKitEventOutcome`, `AuthorizationProbe`, plain enums/Bools).
  - Completion handlers passed to `UNUserNotificationCenter`, `CKContainer`, `HKStatisticsQuery`, `WCSession.sendMessage` **must be written `{ @Sendable … in }`**. A plain closure formed inside a `@MainActor` type inherits main-actor isolation and the compiler inserts a runtime executor check that traps when the framework calls back on its own queue (this crashed the iOS test host once — `dispatch_assert_queue_fail`).
  - No `@preconcurrency import`, no `@unchecked Sendable`, and `nonisolated(unsafe)` only for the DEBUG-only CloudKit schema hand-off, commented as such.
  - Prefer `Task` loops with `Task.sleep` and cancellation in `deinit` over `Timer`s that capture `self` in `@Sendable` blocks.
- **Logging**: `AppLogger.<category>.notice/info/debug/error("…")`. Never `print()` or `NSLog()` in shipping code. Anything that might be PII (error descriptions, notes, locations, Health values) interpolates with `privacy: .private`; use `.public` only for identifiers and counts.
- **Trigger/medication access**: read and write through `event.triggers` / `event.medications`. The boolean columns are an implementation detail.
- **Health data**: biological sex and menstrual-flow samples are read into value types, used in memory, and discarded. Never store them in Core Data/UserDefaults, include them in Watch payloads or exports, or log them.
- **Location**: only the coarsened (2-decimal) coordinate may be persisted or sent to the weather API (`OpenMeteoSupport.coarseCoordinate`).
- **Accessibility**: every interactive control gets an `.accessibilityLabel` and, where the effect isn't obvious, an `.accessibilityHint`; combine sub-elements with `.accessibilityElement(children: .combine)`. Charts ship an `AXChartDescriptor`. Any state conveyed by colour also needs a glyph or text under `accessibilityDifferentiateWithoutColor`; value animations go through `motionSafeAnimation` / `motionSafeNumericTransition`.
- **Dynamic Type for custom Optima fonts**: every `.font(.custom("Optima-…", size: N))` call must pass `relativeTo:` (or use `scaledFont(size:)`). Bare `.custom(_, size:)` is forbidden.
- **Localization**: user-visible strings are `Text("…")` / `String(localized:)` so they land in the String Catalog; don't build sentences by concatenating fragments — use format strings and plural rules.
- **SwiftLint**: CI runs `--strict`, so warnings fail the build. Run the Docker command above before pushing; rule tweaks go in `.swiftlint.yml` with a one-line justification.
- **Versions and targets** live only in `Config/Shared.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, deployment targets, `SWIFT_VERSION`). Don't re-add per-target overrides in the pbxproj.
- **Comments**: explain *intent* and *trade-offs*, not what the next line obviously does.
- **No third-party deps**: keeping the dependency graph empty is a feature. If something seems to need a library, talk it through first.
- **Contact info**: read every email, URL and App Store ID from `Shared/AppContactInfo.swift`.
- **Engagement counter**: call `ReviewPromptCoordinator.recordEntryLogged()` once per user-perceived "logged something" action.
- **Adaptive layout**: top-level destinations go through `AppDestination`; branch on `horizontalSizeClass`, not `userInterfaceIdiom`. Don't nest `NavigationSplitView`s — use `HStack { master; Divider(); detail }` inside a destination for iPad master/detail.
- **Keyboard shortcuts**: register at the root (`iOSContentView.globalKeyboardShortcuts`) with off-screen buttons so they work from every tab.
- **Hover effects**: `.hoverEffect(.highlight)` for rows/chips, `.lift` for cards, always with a matching `.contentShape`.

---

## Notifications & background tasks

The user-visible behaviour is two toggles in **Settings → Notifications**: *Forecast risk alerts* and *Re-engagement reminders*.

| Concern | Owner | Notes |
|---|---|---|
| Authorization | `NotificationManager.requestAuthorization()` | Requested lazily on the first toggle flip; never on cold launch. |
| Forecast push | `NotificationManager.scheduleForecastRiskNotificationIfNeeded(migraines:forecast:)` | Picks the first forecast hour at or above `highRiskThreshold` (0.65) and schedules one calendar trigger ~2 h before it. Requires ≥ 5 logged migraines. |
| Re-engagement push | `NotificationManager.scheduleReengagementNotificationIfNeeded(...)` | Daily at 7 pm local only after 14 quiet days; cancelled on every `.active` scene phase. Gentle copy, never a wellness check. |
| Reconcile-all | `NotificationManager.reconcileAllNotifications(migraines:forecast:)` | Idempotent entry point used by the scene-phase observer and the BG task. |
| BG task identifier | `BackgroundTaskScheduler.refreshIdentifier` | `com.neuroli.Headway.refresh`; must also appear in `NALI-Migraine-Log-Info.plist` under `BGTaskSchedulerPermittedIdentifiers`. |
| BG work | `BackgroundTaskScheduler.performRefreshWork()` | Location → forecast → `RiskSyncCoordinator` (risk + Watch push) → `reconcileAllNotifications`, inside the ~30 s budget. |

Simulating the BG task locally: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.neuroli.Headway.refresh"]` at the LLDB prompt after the app has been backgrounded once.

---

## HealthKit

- **Write-back**: with **Settings → Integrations → Apple Health → Sync to Apple Health** on, every add/update/delete mirrors a `.headache` `HKCategorySample` (severity 1–3 mild, 4–6 moderate, 7–10 severe). Samples carry `HKMetadataKeyExternalUUID = event.id` so backfill is idempotent and deletions can find their sample. Revoked authorization is detected and surfaced in Settings.
- **Reads**: sleep (overlapping samples merged per night), HRV (72 h pre-onset window), steps, and — only when cycle insights are enabled — menstrual flow and biological sex.
- **First launch**: after the disclaimer and splash the "Connect Apple Health" primer is shown, then Apple's permission sheet; the location prompt waits until that is done. Users who skipped "Sex" can grant it later from Health → Apps → Headway; Settings explains this when cycle insights aren't offered.
- **Purpose strings**: `NSHealthShareUsageDescription` (lists menstrual cycle data and states biological sex is read only to decide whether cycle insights apply) and `NSHealthUpdateUsageDescription` are required in both the iOS and Watch Info.plists.

---

## Analytics dashboard

The Analytics tab ("Overview") is a tap-to-drill-down dashboard. Every card that navigates shows a "Details ›" label or chevron, a one-time TipKit tip points at the hero card, and charts carry tap hints.

- **Hero + KPI strip**: unique **migraine days** in the period with a semantic trend chip vs. the previous period (better/worse, not just up/down), then compact chips for attacks, average pain, median duration (+ IQR), migraine-free streak and top trigger.
- **Trends**: severity heatmap stretched to the card width (Mild/Moderate/Severe/Extreme, DWC glyphs, cycle-start dots for eligible users) and a scrollable 12-month headache-days chart with a "your average" rule and scrubbing.
- **Medication**: acute-medication days per month against overuse bands (low / moderate / frequent) as a gauge.
- **Patterns**: switcher card for weekday distribution, time of day and symptom prevalence.
- **Insights**: auto-generated cards from `AnalyticsInsightGenerator` (emitted only when the signal is strong; capped at four).
- **Cycle association** (eligible users with cycle data only): rate ratio of perimenstrual vs. baseline days computed over *observed* days, confidence tier, "in n of your last 3 cycles" pattern indicator, cycle-aligned chart using the user's median cycle length, severity split, non-diagnostic copy.
- **Health correlations**: sleep on migraine eves and HRV in the 72 h prodromal window vs. the rest of the window.
- **Life impact** and the weather-correlation deep link.

Pure computations live in `Views/Analytics/AnalyticsComputations.swift` and `AnalyticsBurdenMetrics.swift` as `[MigraineEvent]` extensions; cycle math is in `Shared/Services/MenstrualCycleInsights.swift`; HealthKit comparisons sit behind `HealthCorrelationStore`, which caches per `(window, migraineCount)` and exposes pure static compute functions. Everything is computed on-device.

---

## Schema migration playbook

The full procedure lives at the top of [`Shared/Models/PersistenceController.swift`](./Shared/Models/PersistenceController.swift). Quick summary:

1. **Lightweight changes** are handled automatically by `NSPersistentCloudKitContainer`; create a new model version.
2. **Non-trivial changes** need a hand-written `.xcmappingmodel`.
3. After **any** schema change: bump the model version, run the app once against the **Development** CloudKit environment so the new fields appear in the schema (or add them in the CloudKit Console), then **Deploy Schema Changes to Production** *before* shipping — e.g. `CD_modifiedAt` for 3.01. The DEBUG-only `-InitializeCloudKitSchema` launch argument does the same via `initializeCloudKitSchema`; remove it and restore the Production entitlement before archiving.
4. **One-time data backfills** are `UpgradeStep`s in `Shared/Services/MigrationCoordinator.swift`, gated on the from/to marketing version and run by `AppLaunchCoordinator` behind the launch splash. Template and the 3.01 coordinate-coarsening step are in the file.
5. If a store ever fails to load, `PersistenceController` moves it aside, records its path in `UserDefaults`, and Settings shows a recovery banner so the user can share the file.

---

## Privacy & App Store notes

- **Data at rest**: the Core Data store uses `completeUntilFirstUserAuthentication`; exports and ML training files use complete file protection and are removed after use. Stored coordinates are coarsened to ~1 km, which lets the app declare *approximate* location.
- **What syncs where**: migraine entries sync only through the user's private CloudKit database. Watch payloads carry entries (no notes/coordinates/weather in snapshots) and an aggregate risk score; reproductive-health context is stripped from risk factors before they leave the phone. Nothing reaches a developer server.
- **Privacy manifests**: one `PrivacyInfo.xcprivacy` per `.app` bundle. Read [`PRIVACY_MANIFEST_NOTES.md`](./PRIVACY_MANIFEST_NOTES.md) before touching them — comments and empty arrays cause `ITMS-91056` rejections.
- **Privacy policy URL**: `AppContactInfo.privacyPolicyURL`, surfaced in iOS About, macOS About, iOS Settings and the macOS Help menu; must match App Store Connect → App Privacy.
- **App Privacy declaration**: Health & Fitness → Health (app functionality, not linked to identity, no tracking), approximate location, no third-party sharing.
- **Review notes**: mention that cycle-aware insights appear only when Health reports biological sex as female (or cycle history exists) and require Health permission, so reviewers on a fresh device know why they don't see it.
- **Release checklist**: bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Config/Shared.xcconfig`; bump `WhatsNew.currentRelease` if the release has an announcement; confirm the CloudKit Production schema; entitlement at `Production`; no debug launch arguments; CI green; fresh-install smoke test on a real iPhone + Watch.

---

## Deeper reading

- [`CHANGELOG.md`](./CHANGELOG.md) — what shipped in each release.
- [`ML_PREDICTION_GUIDE.md`](./ML_PREDICTION_GUIDE.md) — feature extraction, two-tier scoring, model lifecycle, hold-out confidence.
- [`WEATHER_FEATURE_GUIDE.md`](./WEATHER_FEATURE_GUIDE.md) — Open-Meteo integration, caching, coordinate privacy.
- [`PRIVACY_MANIFEST_NOTES.md`](./PRIVACY_MANIFEST_NOTES.md) — required-reason API declarations and validation checklist.
- [`SPLASH_SCREEN_DESIGN.md`](./SPLASH_SCREEN_DESIGN.md) — launch experience design notes.
- [`iOS_26_LOCATION_CHANGES.md`](./iOS_26_LOCATION_CHANGES.md) — CoreLocation API delta on iOS 26.
- Inline docblocks at the top of `PersistenceController.swift`, `MigrationCoordinator.swift` and `WatchConnectivityManager.swift` — required reading before any data-layer or sync change.

---

## License

Personal project; no public license declared yet. Treat as "all rights reserved" until that changes.
