# Privacy Manifest Notes

Engineering rationale for the three `PrivacyInfo.xcprivacy` files that ship
with this project. The `.xcprivacy` files themselves are kept comment-free
on purpose — see "Why no comments in the .xcprivacy files" below — so
this document is the canonical reference. **If you change a manifest,
update this file too.**

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
that emits ITMS-91056) is a **separate** parser, and we have observed
it reject manifests that lint cleanly:

1. First we shipped `NSPrivacyCollectedDataTypes` and
   `NSPrivacyTrackingDomains` as empty arrays, with comments
   interleaved between `<key>`/`<value>`/`<dict>`/`<array>` nodes
   inside the plist body. ASC rejected with ITMS-91056.
2. We removed the empty arrays but kept the comments inside the plist
   body. ASC still rejected with ITMS-91056.
3. We moved all comments out of the plist body and into the XML prolog
   (between `<?xml ... ?>` and `<!DOCTYPE ...>`). ASC still rejected
   with ITMS-91056 on Build 9.

Apple's own TN3183 reference manifests contain zero comments anywhere
in the file. To stay safely compatible with both validators we now
ship comment-free manifests and keep all rationale in this Markdown
document instead.

## Validation checklist before any release

1. Run `plutil -lint` on all three files; all three must report `OK`.
2. Run `plutil -convert json -o -` on each file and confirm the
   payload contains exactly `NSPrivacyTracking: false` plus the
   declared `NSPrivacyAccessedAPITypes` entries.
3. After `Product → Archive`, choose `Distribute → Generate Privacy
   Report` in the Xcode Organizer and confirm the report lists exactly
   the categories declared above for each platform — no more, no
   fewer.
4. Confirm no third-party SDK (SwiftPM dependency or otherwise) was
   added since the last release that ships its own
   `PrivacyInfo.xcprivacy`. ITMS-91056 will surface those too, with
   their full embedded path. Today the project has zero SwiftPM /
   CocoaPods dependencies, so this should remain a no-op until that
   changes.
