# Privacy Manifest Notes

Engineering rationale for the three `PrivacyInfo.xcprivacy` files that ship
with this project. The `.xcprivacy` files themselves are kept comment-free
on purpose — see "Why no comments in the .xcprivacy files" below — so
this document is the canonical reference. **If you change a manifest,
update this file too.**

## Hard rules — read these first

If you remember nothing else from this document, remember these. Each
of these rules was learned by getting `ITMS-91056` rejection emails
from App Store Connect, and the combination below was confirmed
accepted on **Version 2.75 Build 11 (iOS) / Build 12 (watchOS) / Build
13 (macOS)** uploaded on 2026-04-28.

1. **Never put a comment anywhere in `PrivacyInfo.xcprivacy` — not
   inside `<plist>`, not in the XML prolog, not even between
   `<?xml ... ?>` and `<!DOCTYPE ...>`.** All rationale lives in this
   Markdown file. `plutil -lint` accepts comments; ASC's server-side
   validator does not, in any position we have tried. The accepted
   shape contains zero `<!-- ... -->` blocks.
2. **Never ship `NSPrivacyTrackingDomains` or `NSPrivacyCollectedDataTypes`
   as an empty array (`<array/>`).** Both must be either absent or
   populated. Empty arrays are documented (TN3181) and observed
   triggers for `ITMS-91056`.
3. **Never ship an empty `NSPrivacyAccessedAPITypes` array either.** If
   no required-reason API is used, omit the key entirely. (This app
   does use required-reason API, so this case shouldn't arise.)
4. **Ignore Xcode's "Generate Privacy Report" warning that says
   "Missing an expected key: 'NSPrivacyCollectedDataTypes'".** That
   tool is informational and is _not_ the same validator that produces
   `ITMS-91056`. The warning is expected and the build is fine.
5. **Use the reason codes verified below.** `CA92.1` and `C617.1` are
   correct for this codebase as long as `UserDefaults.standard` is the
   only `UserDefaults` API in use (no App Groups) and the only file-
   timestamp consumer is `SettingsView`'s recovery section. If either
   assumption changes, update both the manifest(s) and this document.
6. **Re-run the validation checklist at the bottom of this file
   before every release.**

## Sibling files that must stay in lockstep

There is exactly one `PrivacyInfo.xcprivacy` per shipped `.app` bundle:

- `NALI Migraine Log/PrivacyInfo.xcprivacy`            — iOS / iPadOS bundle
- `NALI Migraine Log macOS/PrivacyInfo.xcprivacy`      — macOS bundle
- `NALI Migraine Log Watch App Watch App/PrivacyInfo.xcprivacy` — watchOS bundle

Each one is auto-included in its target's bundle resources via the
project's `PBXFileSystemSynchronizedRootGroup`s (Xcode 16+). They are
**not** referenced explicitly in `project.pbxproj` and they are not
shared across targets — each `.app` ships its own copy.

Apple does not allow under-declaration of required-reason API. Over-
declaration is harmless. The iOS file lists the most surface area
because that target also surfaces the recovery-file UI in
`SettingsView` (which reads file modification timestamps); macOS and
watchOS list only what they actually use today. If you ever port the
recovery surface to those targets, add the file-timestamp entry to
their manifests at the same time.

## Top-level keys, and why each is or is not present

### `NSPrivacyTracking` — present, set to `false`

We do not link any data collected by this app with data collected by
other companies' apps, websites, or properties. All migraine, weather,
and HealthKit data either stays on-device or is synced exclusively
through the user's own iCloud account via
`NSPersistentCloudKitContainer`.

### `NSPrivacyTrackingDomains` — omitted

Per TN3181, when `NSPrivacyTracking` is `false` this key must be omitted
entirely. An empty array here is the documented trigger for ITMS-91056.

### `NSPrivacyCollectedDataTypes` — omitted

We do not collect data and send it to a server we control. iCloud sync
uses the user's own private CloudKit database; the watch app
additionally relays new entries to the paired iPhone via
`WatchConnectivity`, which is a peer-to-peer hand-off and not
developer-side collection. Apple's TN3181 does not require this key,
and the TN3183 example template omits it.

An earlier revision of these manifests shipped the key as `<array/>`
because Xcode's "Generate Privacy Report" tool emits "Missing an
expected key: 'NSPrivacyCollectedDataTypes'" when it is absent. That
warning is purely informational and does **not** block uploads. App
Store Connect's server-side validator, which **does** block uploads,
has been observed to reject the empty array, so the key is omitted
here. If we ever start collecting data, add the key back with one or
more populated dictionaries — never as an empty array.

### `NSPrivacyAccessedAPITypes` — required-reason API declarations

Each dictionary in this array contains exactly two keys
(`NSPrivacyAccessedAPIType` and `NSPrivacyAccessedAPITypeReasons`)
and nothing else. Reason codes are taken from Apple's published list
in TN3183.

#### `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`

Used by every target. `CA92.1` is the code for "user defaults that are
only accessible to the app itself" — the right code as long as we use
plain `UserDefaults.standard` and **not** a shared App Group.

If a future change introduces a shared `UserDefaults(suiteName:)` for
an App Group (e.g. to share data with a widget), switch the code to
`1C8F.1` everywhere and update this document.

Current call sites (non-exhaustive — grep `UserDefaults.standard` for
the live list):

- `Shared/Models/PersistenceController.swift` — iCloud-sync opt-in
  flag and last recovery-file path.
- `Shared/Services/MigrationCoordinator.swift` — last-launched-version
  stamp and data-migration completion flag.
- `Shared/Services/MigrainePredictionService.swift` — last ML training
  date.
- `Shared/Services/FeatureExtractor.swift` — daily check-in
  serialization.
- `Shared/WatchConnectivityManager.swift` — pending risk payload and
  the deleted-IDs set used to suppress re-sync of tombstoned entries.
- `NALI Migraine Log/NALI_Migraine_LogApp.swift` — disclaimer-accepted
  flag.
- `NALI Migraine Log macOS/Views/DisclaimerView.swift` — disclaimer-
  accepted flag.
- `Shared/Services/ReviewPromptCoordinator.swift` — first-launch date,
  engagement counters, and last enjoyment-prompt outcome.

All values are read and written exclusively by this app.

#### `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1` — iOS only

Used in `NALI Migraine Log/Views/SettingsView.swift` (the recovery
section), which calls `FileManager.attributesOfItem(atPath:)` and reads
the `.modificationDate` attribute to display the modification date of a
moved-aside Core Data store so the user can confirm which backup
they're about to share with support. `C617.1` is the code for "display
file timestamps to the person using the device". Timestamps are shown
in the UI and never sent off-device or used to derive other signals.

The macOS and watchOS bundles do not surface this UI today, so their
manifests omit this entry. **Re-add it on any platform whose target
gains code that reads file timestamps.**

## Why no comments in the `.xcprivacy` files

`plutil -lint` happily accepts XML comments anywhere in a privacy
manifest. App Store Connect's server-side validator (the code path
that emits `ITMS-91056`) is a **separate** parser, and we have
observed it reject manifests that lint cleanly. The full sequence of
attempts (April 2026 release of v2.75) was:

1. Manifests shipped with `NSPrivacyCollectedDataTypes` and
   `NSPrivacyTrackingDomains` as empty arrays, plus comments
   interleaved between `<key>`/`<value>`/`<dict>`/`<array>` nodes
   inside the plist body. **ASC rejected with `ITMS-91056`.**
2. Empty arrays removed; comments inside the plist body kept. **ASC
   still rejected with `ITMS-91056`.**
3. All comments moved out of the plist body and into the XML prolog
   (between `<?xml ... ?>` and `<!DOCTYPE ...>`). **ASC still rejected
   with `ITMS-91056` (this was Build 9 of v2.75).**
4. Every comment removed — including the prolog block — so each file
   is the bare TN3183 shape: XML declaration, DOCTYPE, `<plist>`,
   nothing else. **ASC accepted (Build 11 of v2.75 on 2026-04-28).**

The takeaway is that ASC's validator does not tolerate comments in
this file at all, regardless of whether they are technically inside
the plist data. Apple's own TN3183 reference manifests confirm this
shape: zero comments anywhere. All rationale lives in this Markdown
document instead, and the validation checklist below enforces the
rule on every release.

## Validation checklist before any release

1. **Comment audit.** `grep -n '<!--' "NALI Migraine Log"/PrivacyInfo.xcprivacy
   "NALI Migraine Log macOS"/PrivacyInfo.xcprivacy "NALI Migraine Log Watch App Watch App"/PrivacyInfo.xcprivacy`
   must return zero hits. If anything matches, strip it before
   archiving. (See "Hard rules" rule 1.)
2. **`plutil -lint`** all three files; all three must report `OK`.
3. **`plutil -convert json -o -`** on each file and confirm the
   payload contains exactly `NSPrivacyTracking: false` plus the
   declared `NSPrivacyAccessedAPITypes` entries — no
   `NSPrivacyCollectedDataTypes`, no `NSPrivacyTrackingDomains`.
4. **`Product → Archive` → `Distribute → Generate Privacy Report`** in
   the Xcode Organizer and confirm the report lists exactly the
   categories declared above for each platform — no more, no fewer.
   Expect a "Missing an expected key: 'NSPrivacyCollectedDataTypes'"
   note for both the iOS app and the embedded watch app — this is
   informational and does **not** block the upload (see "Hard rules"
   rule 4). Any _other_ message in this dialog should be investigated.
5. **Third-party SDK audit.** Confirm no SwiftPM dependency or other
   embedded framework was added since the last release that ships its
   own `PrivacyInfo.xcprivacy`. `ITMS-91056` will surface broken
   nested manifests too, with their full embedded path. Today the
   project has zero SwiftPM / CocoaPods dependencies, so this is a
   no-op until that changes — but the moment it does, this step is no
   longer a no-op.
6. **App Store Connect → My Apps → App Privacy** answers must remain
   consistent with the manifest:
   - Data Types: "Data Not Collected" (HealthKit data is read/written
     locally and synced via the user's own iCloud private database;
     none of it is sent to a server we control).
   - Privacy Policy URL: must be present.
   Inconsistency here causes a separate App Review rejection — not
   `ITMS-91056` — but is worth checking in the same pass.
