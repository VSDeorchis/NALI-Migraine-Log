# Changelog

Versions come from `Config/Shared.xcconfig` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`). The in-app "What's New" sheet is keyed separately by `WhatsNew.currentRelease`.

## 3.01 (build 15) — in submission

Everything below landed on `main` through PRs #25–#40. Submission still requires the CloudKit Production schema to include `CD_modifiedAt`, the iCloud entitlement at `Production`, and a fresh-install smoke test on a physical iPhone + Watch.

### For users

- **Apple Watch**: log an attack in three taps (pain → your usual triggers/symptoms → save) with the full form behind *More*; entries sync both ways and survive being logged offline; the risk score now updates whenever the Watch asks, the iPhone app comes to the foreground or refreshes in the background — not only when the Predict tab is open. The Watch remembers the last synced score and says "No risk score yet — open Headway on iPhone" instead of showing 0%.
- **Cycle-aware insights (optional)**: perimenstrual badge on entries, a "Perimenstrual Window" contributing factor (with detail and recommendation) in the risk score, and a Statistics card with a rate ratio ("2.4× more likely around period start"), confidence tier, "in n of your last 3 cycles" pattern and a cycle-aligned chart. Offered only when Apple Health reports biological sex as female or real cycle history exists; nothing about the cycle is stored, synced or exported.
- **Redesigned Statistics**: hero migraine-days number with trend chips, KPI strip, severity heatmap, scrollable 12-month chart, medication-days gauge, patterns switcher, insights, sleep/HRV correlations, "Details ›" affordances, a one-time tip and chart tap hints.
- **Settings hub**: Data & Privacy / Integrations / Notifications / Appearance / About with permission status chips and deep links; two-pane on iPad; explains how to share Sex/Cycle Tracking later if it was skipped.
- **Logging**: medications named `generic (Brand)` with pinned favourites, haptic on save, drafts preserved on accidental dismiss.
- **First launch**: must-accept disclaimer (no more `exit(0)`), progress splash that dismisses when migrations finish, Apple Health primer before the location prompt, one-time What's New after updates.
- **iPad & Mac**: sidebar + list + detail layouts, keyboard shortcuts (⌘N, ⌘1–⌘4), hover effects, Pencil-friendly notes; macOS gets a sortable `Table`, menu commands, search and `fileExporter`.
- **Accessibility & localization**: Dynamic Type everywhere (custom fonts included), Audio Graphs for charts, Differentiate Without Colour glyphs, Reduce Motion honoured, String Catalogs for all three apps.
- **Siri & Spotlight**: "Log a migraine" / "Open new entry" intents and searchable entries.

### Privacy & security

- Core Data store protected with `completeUntilFirstUserAuthentication`; exports and ML training files use complete protection and are deleted after use.
- Weather coordinates coarsened to two decimals (~1 km) before storage and API calls; existing entries are backfilled once on first launch of 3.01 (`MigrationCoordinator` step `v3.01-coarsen-weather-coordinates`).
- Watch payloads are versioned, validated `Codable` records; snapshots omit notes, coordinates and weather; reproductive-health context is stripped from risk factors before leaving the phone.
- Delete-all now also removes mirrored Health samples, Watch tombstones and on-disk files.
- HealthKit purpose strings state that biological sex is read only to decide whether cycle insights apply.
- Network hygiene for Open-Meteo: timeouts, response-size cap, content-type check, validated parsers (no force-unwraps).
- Log privacy: error descriptions and PII interpolate as `.private`.

### Engineering

- **Swift 6 language mode** with `SWIFT_STRICT_CONCURRENCY = complete` and no unsafe suppression: `@MainActor` ownership for persistence, store, location, Health, notifications and Watch connectivity; `nonisolated` framework callbacks hop with `Sendable` values; framework completion handlers are explicitly `@Sendable` (fixes a runtime `dispatch_assert_queue_fail` trap); `Task` loops replace `Timer`s.
- `MigraineStore` (shared) extracted from the iOS view model; iOS view model split into Weather/CloudSync/Analytics/Debug extensions; macOS view model reuses the shared store.
- `modifiedAt` added to the Core Data model (new model version) for last-writer-wins Watch sync.
- ML confidence derived from hold-out skill over the majority-class baseline instead of a constant 75%.
- `Config/Shared.xcconfig` holds versions, deployment targets (iOS 18.2 / watchOS 11.2 / macOS 15.2) and Swift settings for all targets; empty macOS model and unused Info.plist removed.
- CI: SwiftLint (0.65.0, `--strict`) job added; Xcode 16.4 and the iPhone 16 / iOS 18.5 simulator pinned; runs on every PR regardless of base; xcresult + raw log artifacts.
- Tests: 22 Swift Testing suites (~190 tests) covering sync records and resolution, Watch risk persistence, burden metrics, cycle analysis, weather parsing, coordinate privacy, delete-all, CSV encoding, What's New gating, accessibility semantics and ML confidence.

## 2.75 (build 11 iOS / 12 watchOS / 13 macOS)

Last build accepted by App Store Connect (2026-04-28). Established the privacy-manifest shape documented in `PRIVACY_MANIFEST_NOTES.md`.
