//
//  MigrationCoordinator.swift
//  NALI Migraine Log
//
//  One-time-per-launch hook that compares the running app version to the
//  version we recorded on the previous successful launch and runs any
//  registered upgrade steps for the transition.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHY THIS EXISTS
//  ──────────────────────────────────────────────────────────────────────
//  Core Data lightweight migration handles SCHEMA changes for free, but
//  there is a separate class of release that needs a one-time DATA pass:
//
//      • Backfill a derived attribute from existing rows.
//      • Normalize a free-text field whose validation rules tightened.
//      • Re-bucket old enum values that have been split or renamed.
//      • Wipe a UserDefaults flag that's no longer meaningful.
//
//  Each of those lands as one entry in `upgradeSteps`.
//
//  ──────────────────────────────────────────────────────────────────────
//  CONTRACT
//  ──────────────────────────────────────────────────────────────────────
//  Call `runLaunchSequence(context:)` exactly once from each target's
//  `@main` `App.init()` AFTER `PersistenceController.shared` has finished
//  loading the store. We compare `CFBundleShortVersionString` (and, for
//  diagnostics, `CFBundleVersion`) against values we stashed on the last
//  launch in `UserDefaults`:
//
//      • No stored value          → treat as first install. No steps.
//      • Same version + build     → quiet no-op.
//      • Same version, new build  → debug-log only (TestFlight path).
//      • Strictly newer version   → run any `appliesWhen` steps in order,
//                                   then save the context once.
//      • Older version is running → downgrade. Log warning, run nothing.
//
//  Steps are responsible for being rerun-safe (idempotent) — we update
//  the stored version even if a step throws, because looping a broken
//  step on every launch is worse than leaving the device in the new
//  marker. Each step also carries a stable string id so the log trail
//  tells us exactly which migrations a given device executed.
//

import Foundation
import CoreData

/// One step in the upgrade pipeline. Steps are pure: they read from and
/// write to the supplied Core Data context but never block on the network
/// or UI. Long-running work should fan out into a `Task` and return
/// immediately so the launch path stays responsive.
struct UpgradeStep {
    /// Stable identifier (e.g. `"v2.76-normalize-location-strings"`)
    /// used only for log lines. Keep these unique across releases so
    /// support can correlate a device's log to the steps it ran.
    let id: String

    /// Returns true when this step should run for the upgrade `from → to`.
    /// Both arguments are the raw `CFBundleShortVersionString` values and
    /// should be compared with `String.compare(_:options:.numeric)`.
    let appliesWhen: (_ from: String, _ to: String) -> Bool

    /// Performs the data work. Throwing aborts the step but never the
    /// launch — the surrounding coordinator catches and logs.
    let perform: (NSManagedObjectContext) throws -> Void
}

enum MigrationCoordinator {
    // MARK: - Tunable surface

    /// Append to this list to register a new data backfill, e.g.
    ///
    /// ```swift
    /// UpgradeStep(
    ///     id: "v2.76-normalize-location-strings",
    ///     appliesWhen: { from, _ in
    ///         from.compare("2.76", options: .numeric) == .orderedAscending
    ///     },
    ///     perform: { context in
    ///         let request: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
    ///         for event in try context.fetch(request) {
    ///             event.location = event.location?.trimmingCharacters(in: .whitespaces)
    ///         }
    ///     }
    /// )
    /// ```
    private static let upgradeSteps: [UpgradeStep] = [
        UpgradeStep(
            id: "v3.01-coarsen-weather-coordinates",
            appliesWhen: { from, _ in
                from.compare("3.01", options: .numeric) == .orderedAscending
            },
            perform: coarsenStoredWeatherCoordinates
        )
    ]

    static func upgradeStep(id: String) -> UpgradeStep? {
        upgradeSteps.first { $0.id == id }
    }

    /// Entries saved before 3.01 carry the raw GPS fix (~1 m). Rounds them
    /// to the two decimals the weather lookup actually uses so the store,
    /// iCloud and exports no longer hold street-level positions.
    static func coarsenStoredWeatherCoordinates(in context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        request.predicate = NSPredicate(format: "weatherLatitude != 0 OR weatherLongitude != 0")
        for event in try context.fetch(request) {
            let latitude = OpenMeteo.coarseCoordinate(event.weatherLatitude)
            let longitude = OpenMeteo.coarseCoordinate(event.weatherLongitude)
            if latitude != event.weatherLatitude || longitude != event.weatherLongitude {
                event.weatherLatitude = latitude
                event.weatherLongitude = longitude
            }
        }
    }

    // MARK: - Persisted launch state

    private static let lastVersionKey = "lastLaunchedAppVersion"
    private static let lastBuildKey   = "lastLaunchedAppBuild"

    /// Public, read-only accessor for the version we recorded on the
    /// previous launch. Useful for diagnostic UIs (Settings → About) and
    /// for the unit tests in `MigrationCoordinatorTests`.
    static var lastLaunchedVersion: String? {
        UserDefaults.standard.string(forKey: lastVersionKey)
    }

    // MARK: - Entry point

    /// Call once from each `@main` `App.init()`, AFTER the persistent
    /// store has been loaded. Idempotent: subsequent calls within the
    /// same process are cheap (a `UserDefaults` read + a string compare)
    /// and will not re-run an upgrade step that has already executed.
    static func runLaunchSequence(context: NSManagedObjectContext) {
        let bundle = Bundle.main
        let currentVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let currentBuild   = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        let defaults = UserDefaults.standard
        let storedVersion = defaults.string(forKey: lastVersionKey)
        let storedBuild   = defaults.string(forKey: lastBuildKey)

        // Always record the running version on the way out so that even
        // if an upgrade step throws, we don't loop forever trying to
        // re-run it on every launch. Steps own their own "I already ran"
        // semantics (or are simply idempotent).
        defer {
            defaults.set(currentVersion, forKey: lastVersionKey)
            defaults.set(currentBuild, forKey: lastBuildKey)
        }

        guard let from = storedVersion else {
            AppLogger.migration.notice("First launch detected (or first launch since version tracking was added). Recorded \(currentVersion, privacy: .public) (\(currentBuild, privacy: .public)).")
            return
        }

        switch from.compare(currentVersion, options: .numeric) {
        case .orderedSame:
            if storedBuild != currentBuild {
                AppLogger.migration.debug("Same version (\(currentVersion, privacy: .public)); build \(storedBuild ?? "?", privacy: .public) → \(currentBuild, privacy: .public).")
            }
            return

        case .orderedDescending:
            // Older binary is now running than what we recorded — happens
            // on TestFlight regressions and during local debugging. Do
            // not run forward-only upgrade steps against it.
            AppLogger.migration.notice("Downgrade detected (\(from, privacy: .public) → \(currentVersion, privacy: .public)); skipping upgrade steps.")
            return

        case .orderedAscending:
            AppLogger.migration.notice("Upgrade detected (\(from, privacy: .public) → \(currentVersion, privacy: .public)); evaluating upgrade steps.")
            runUpgradeSteps(from: from, to: currentVersion, context: context)
        }
    }

    private static func runUpgradeSteps(from: String, to: String, context: NSManagedObjectContext) {
        var anyRan = false

        for step in upgradeSteps where step.appliesWhen(from, to) {
            anyRan = true
            do {
                AppLogger.migration.notice("Running upgrade step: \(step.id, privacy: .public)")
                try step.perform(context)
            } catch {
                AppLogger.migration.error("Upgrade step \(step.id, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        guard anyRan else {
            AppLogger.migration.notice("No upgrade steps applied for \(from, privacy: .public) → \(to, privacy: .public).")
            return
        }

        if context.hasChanges {
            do {
                try context.save()
                AppLogger.migration.notice("Saved upgrade-step changes for \(from, privacy: .public) → \(to, privacy: .public).")
            } catch {
                AppLogger.migration.error("Failed to save upgrade-step changes: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
