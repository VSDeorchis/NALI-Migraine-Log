//
//  PersistenceController.swift
//  NALI Migraine Log
//
//  Shared Core Data controller for the iOS, macOS, and watchOS targets.
//
//  ──────────────────────────────────────────────────────────────────────
//  CHANGING THE CORE DATA SCHEMA — READ THIS FIRST
//  ──────────────────────────────────────────────────────────────────────
//
//  This app uses `NSPersistentCloudKitContainer` with both
//  `NSMigratePersistentStoresAutomaticallyOption` and
//  `NSInferMappingModelAutomaticallyOption` enabled (see `storeOptions`
//  below). That gives us safe *lightweight* migrations for free, but
//  ONLY for additive changes:
//
//      ✓ Add a new optional attribute (or non-optional with a default)
//      ✓ Add a new entity or relationship
//      ✓ Add an index
//      ✓ Drop an attribute (column data is discarded, no failure)
//
//      ✗ Rename an attribute or entity → set the "Renaming Identifier"
//                                         in the model editor
//      ✗ Change an attribute's type    → ship an .xcmappingmodel
//      ✗ Restructure a relationship    → ship an .xcmappingmodel
//      ✗ Split or merge entities       → ship an .xcmappingmodel
//
//  Procedure for ANY schema change:
//
//   1. In Xcode, select `Shared/NALI_Migraine_Log.xcdatamodeld` and pick
//      Editor → Add Model Version. Name the new version (e.g. `V3`),
//      base it on the current one, and mark the new version as Current
//      via the file inspector ("Versioned Core Data Model" → Current).
//
//   2. Make changes in the NEW version only. Never edit the old version
//      — that's the schema users currently have on disk, and the
//      migrator needs it intact to compute the diff.
//
//   3. If anything beyond the additive list above changed, add a mapping
//      model: File → New → File → Mapping Model. Source = old version,
//      Destination = new version. Hand-tune any non-trivial property
//      mappings (custom value transformers, derived fields, etc.).
//
//   4. CloudKit step (only if `useICloudSync` is enabled for any user):
//      push the schema change to the CloudKit container BEFORE shipping
//      via Product → Scheme → Edit Scheme → Run → Arguments → check
//      "Initialize CloudKit Schema". Run once against the developer
//      container, then promote to Production from the CloudKit
//      Dashboard. CloudKit only accepts ADDITIVE changes once a record
//      type is in production — fields cannot be renamed or deleted.
//
//   5. Bump `CFBundleShortVersionString` (the Marketing Version) BEFORE
//      uploading the new build. `MigrationCoordinator` keys upgrade
//      steps off this string; if you forget to bump it, no upgrade
//      step will fire on user devices.
//
//   6. If the change requires a one-time data backfill (rebuild a
//      derived attribute, normalize free-text, re-bucket an enum), add
//      an `UpgradeStep` to `MigrationCoordinator.upgradeSteps`. That
//      hook runs once per device on the first launch after the user
//      installs the new version.
//
//  RECOVERY: If migration fails at runtime, `handlePersistentStoreError`
//  moves the user's store aside (with -wal / -shm sidecars) to a
//  timestamped recovery filename and opens a fresh, empty store so the
//  app can launch. The path is recorded under
//  `lastRecoveryFileDefaultsKey`; the recovery banner on the main log
//  view and the recovery section in `SettingsView` let the user share
//  the moved-aside file with support. We never delete user data.
//  ──────────────────────────────────────────────────────────────────────
//

import CloudKit
import CoreData
import SwiftUI

public final class PersistenceController: ObservableObject {
    @Published public var syncStatus: SyncStatus = .notConfigured

    /// Whether the currently-loaded store is mirroring to CloudKit. Reflects the
    /// live container, not just the saved preference, so onboarding/settings can
    /// avoid a redundant reload when the desired state already matches.
    public private(set) var isCloudKitEnabled: Bool = false

    /// CloudKit container that backs iCloud sync across the user's devices.
    private static let cloudKitContainerIdentifier = "iCloud.com.nali.migrainelog"

    /// CloudKit mirroring is driven from the phone/desktop only. The watch app
    /// relays its entries to the paired iPhone via `WatchConnectivity`, and the
    /// phone is the single device that writes to the shared CloudKit container.
    /// Mirroring on the watch *as well* would double-replicate the same store —
    /// CloudKit enforces no uniqueness on our `id`, so a watch-logged entry could
    /// arrive on the phone both as its own CloudKit record and as a WatchConnectivity
    /// copy, producing duplicates. Keeping it off on watchOS avoids that.
    private static var cloudKitMirroringSupported: Bool {
        #if os(watchOS)
        return false
        #else
        return true
        #endif
    }

    public static let shared = PersistenceController()
    
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
    
    let container: NSPersistentCloudKitContainer
    
    private init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "NALI_Migraine_Log")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure store
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            
            let storeOptions: [String: NSObject] = [
                NSMigratePersistentStoresAutomaticallyOption: true as NSNumber,
                NSInferMappingModelAutomaticallyOption: true as NSNumber,
                NSSQLitePragmasOption: ["journal_mode": "WAL"] as NSObject
            ]
            
            for (key, value) in storeOptions {
                description.setOption(value, forKey: key)
            }
            
            // Enable CloudKit sync unless the user has explicitly opted out
            // (see `headwayICloudSyncEnabled`, which defaults ON) so the app
            // syncs across a user's devices out of the box. Never attach
            // CloudKit to the in-memory store used by previews/tests — a
            // simulator with no signed-in iCloud account can trip CloudKit setup.
            let syncEnabled = !inMemory && Self.cloudKitMirroringSupported && UserDefaults.standard.headwayICloudSyncEnabled
            if syncEnabled {
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: Self.cloudKitContainerIdentifier
                )
                syncStatus = .syncing(0.0)
            } else {
                // Explicitly disable CloudKit sync
                description.cloudKitContainerOptions = nil
            }
            isCloudKitEnabled = syncEnabled
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                AppLogger.coreData.error("Core Data failed to load: \(error.localizedDescription, privacy: .public)")
                // If the failing store had CloudKit attached, the error may be
                // CloudKit-specific (account state, container/entitlement, etc.)
                // rather than genuine store corruption. Try loading the SAME
                // file locally first so the user keeps all their data visible,
                // and only fall back to the move-aside recovery if even a plain
                // local load fails.
                if description.cloudKitContainerOptions != nil {
                    self.loadLocallyAfterCloudKitFailure(originalError: error)
                } else {
                    self.handlePersistentStoreError(error)
                }
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.shouldDeleteInaccessibleFaults = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreRemoved),
            name: NSNotification.Name.NSPersistentStoreCoordinatorStoresWillChange,
            object: container.persistentStoreCoordinator
        )
        
        // Refresh the UI when CloudKit imports remote changes from another device.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main) { [weak self] _ in
                self?.container.viewContext.refreshAllObjects()
        }

        // Drive an accurate sync status (and surface CloudKit errors) from the
        // container's own setup/import/export events instead of guessing.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main) { [weak self] notification in
                self?.handleCloudKitEvent(notification)
        }

        // If sync is on, confirm the device actually has an iCloud account so we
        // can tell the user to sign in rather than silently failing to sync.
        if isCloudKitEnabled {
            verifyCloudAccountAvailable()
        }
    }

    /// Translates `NSPersistentCloudKitContainer` setup/import/export events into
    /// the user-facing `syncStatus`. Errors here are how we learn that, e.g.,
    /// the user isn't signed into iCloud or their storage is full.
    private func handleCloudKitEvent(_ notification: Notification) {
        guard isCloudKitEnabled,
              let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

        if let error = event.error {
            AppLogger.coreData.error("CloudKit sync event failed: \(error.localizedDescription, privacy: .public)")
            syncStatus = .error(Self.userFacingSyncMessage(for: error))
        } else if event.endDate == nil {
            // A setup/import/export is in progress.
            syncStatus = .syncing(0.0)
        } else {
            syncStatus = .enabled
        }
    }

    /// Checks the iCloud account state for the sync container and, when it isn't
    /// usable, surfaces a clear, actionable message via `syncStatus`.
    private func verifyCloudAccountAvailable() {
        CKContainer(identifier: Self.cloudKitContainerIdentifier).accountStatus { [weak self] status, _ in
            DispatchQueue.main.async {
                guard let self = self, self.isCloudKitEnabled else { return }
                switch status {
                case .available:
                    break
                case .noAccount:
                    self.syncStatus = .error("Sign in to iCloud in the Settings app to sync across your devices.")
                case .restricted:
                    self.syncStatus = .error("iCloud is restricted on this device, so sync is unavailable.")
                case .couldNotDetermine, .temporarilyUnavailable:
                    self.syncStatus = .error("iCloud is temporarily unavailable. Your data is safe on this device.")
                @unknown default:
                    break
                }
            }
        }
    }

    /// Maps a CloudKit error to a short, non-technical message for the UI.
    private static func userFacingSyncMessage(for error: Error) -> String {
        switch (error as? CKError)?.code {
        case .some(.notAuthenticated):
            return "Sign in to iCloud in the Settings app to sync across your devices."
        case .some(.quotaExceeded):
            return "Your iCloud storage is full, so new changes can't sync."
        case .some(.networkUnavailable), .some(.networkFailure):
            return "No internet connection. Sync will resume when you're back online."
        default:
            return "iCloud sync hit a problem. Your data is safe on this device."
        }
    }
    
    /// UserDefaults key under which the path to the most recently moved-aside
    /// store is recorded. A future "Recover from backup" UI in Settings can
    /// surface this so users can hand the file to support or attempt re-import.
    public static let lastRecoveryFileDefaultsKey = "lastCoreDataRecoveryFilePath"

    /// Last-resort-avoidance step when a CloudKit-attached store fails to load.
    ///
    /// Re-adds the **same** SQLite file with CloudKit detached so the user keeps
    /// every record they had (sync simply stays off for this launch). No file
    /// is moved or deleted. Only if this plain local load also fails do we
    /// escalate to `handlePersistentStoreError`, which preserves the bytes by
    /// moving them aside rather than deleting them.
    private func loadLocallyAfterCloudKitFailure(originalError: Error) {
        guard let description = container.persistentStoreDescriptions.first,
              let storeURL = description.url else {
            handlePersistentStoreError(originalError)
            return
        }

        // Detach CloudKit so the retry is a plain local store load.
        description.setOption(false as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = nil

        do {
            // Drop any partially-added store from the failed CloudKit attempt.
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }

            try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [
                    NSMigratePersistentStoresAutomaticallyOption: true as NSNumber,
                    NSInferMappingModelAutomaticallyOption: true as NSNumber,
                    NSPersistentHistoryTrackingKey: true as NSNumber,
                    NSSQLitePragmasOption: ["journal_mode": "WAL"] as NSObject
                ]
            )

            isCloudKitEnabled = false
            syncStatus = .error("iCloud sync unavailable — your data is safe and stored on this device.")
            AppLogger.coreData.notice("CloudKit store load failed; loaded the same store locally with data intact. Sync disabled for this launch. Underlying error: \(originalError.localizedDescription, privacy: .public)")
        } catch {
            // Even a plain local load failed — treat as a real store problem and
            // preserve the bytes via the move-aside recovery path.
            AppLogger.coreData.error("Local fallback load also failed: \(error.localizedDescription, privacy: .public)")
            handlePersistentStoreError(originalError)
        }
    }

    /// Recovery handler invoked when `loadPersistentStores` reports an error
    /// (corrupt store, failed migration, transient I/O glitch, etc.).
    ///
    /// **Critical:** never delete the user's database here. Instead, move it
    /// (and every sidecar SQLite produces — `-wal`, `-shm`, `-wal-N`, journal,
    /// etc.) to a timestamped `…-recovery-YYYYMMDD-HHmmss.sqlite` filename in
    /// the same folder. This way, even if recovery later goes wrong, the
    /// original bytes are still on disk and can be salvaged manually.
    private func handlePersistentStoreError(_ error: Error) {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }

        do {
            try container.persistentStoreCoordinator.persistentStores.forEach { store in
                try container.persistentStoreCoordinator.remove(store)
            }

            let recoveryURL = try moveStoreAside(at: storeURL)
            UserDefaults.standard.set(recoveryURL.path, forKey: Self.lastRecoveryFileDefaultsKey)
            // Path is on-device only and not user-identifying, so safe to log
            // as `.public` so support can ask the user to read it back.
            AppLogger.coreData.notice("Core Data store moved aside to: \(recoveryURL.path, privacy: .public)")

            // Re-add the (now fresh) store with the SAME options the app uses
            // normally — crucially keeping NSPersistentHistoryTracking on, which
            // both CloudKit mirroring and our remote-change handling require.
            // Passing `options: nil` here previously dropped history tracking and
            // left sync broken until the next cold launch.
            try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [
                    NSMigratePersistentStoresAutomaticallyOption: true as NSNumber,
                    NSInferMappingModelAutomaticallyOption: true as NSNumber,
                    NSPersistentHistoryTrackingKey: true as NSNumber,
                    NSSQLitePragmasOption: ["journal_mode": "WAL"] as NSObject
                ]
            )

            // If the user had sync on, reattach CloudKit to the fresh store via
            // the normal reload path so a recovered store keeps syncing.
            if isCloudKitEnabled {
                DispatchQueue.main.async { [weak self] in
                    self?.reloadStore(cloudKitEnabled: true)
                }
            }
        } catch {
            // Even on recovery failure we have NOT deleted user data — the
            // moved-aside bytes are intact on disk. Surface an error instead of
            // crashing the app with `fatalError`.
            AppLogger.coreData.fault("Failed to recover from persistent store error: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                self?.syncStatus = .error("Couldn't open your data store. Your data is preserved on this device \u{2014} please contact support.")
            }
        }
    }

    /// Renames the SQLite store at `storeURL` and every sidecar file SQLite
    /// uses (the `-wal`, `-shm`, `-wal-N`, etc. friends — file extensions
    /// vary by SQLite version) to a timestamped recovery name in the same
    /// directory. Returns the URL of the renamed primary file.
    ///
    /// Sidecars are matched by prefix on the original filename, which catches
    /// every variant SQLite is known to produce without us having to maintain
    /// an exhaustive list.
    private func moveStoreAside(at storeURL: URL) throws -> URL {
        let fm = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let originalName = storeURL.lastPathComponent  // e.g. "NALI_Migraine_Log.sqlite"

        let timestamp: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }()
        let recoveryStem = "\(storeURL.deletingPathExtension().lastPathComponent)-recovery-\(timestamp)"
        let primaryRecoveryURL = directory.appendingPathComponent("\(recoveryStem).sqlite")

        // Enumerate everything in the store's folder and move any file whose
        // name starts with the original store filename. This covers
        // `Store.sqlite`, `Store.sqlite-wal`, `Store.sqlite-shm`,
        // `Store.sqlite-wal-1`, journal files, etc.
        let siblings: [URL]
        do {
            siblings = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            // If we can't even list the directory, fall back to renaming just
            // the main file so we don't lose the user's data.
            try fm.moveItem(at: storeURL, to: primaryRecoveryURL)
            return primaryRecoveryURL
        }

        for sibling in siblings where sibling.lastPathComponent.hasPrefix(originalName) {
            let suffix = String(sibling.lastPathComponent.dropFirst(originalName.count))
            let destination = directory.appendingPathComponent("\(recoveryStem).sqlite\(suffix)")
            // Best-effort per-file: failing to move one sidecar shouldn't
            // abort moving the rest. The primary `.sqlite` move is the one
            // that must succeed for recovery to make sense; we re-throw if
            // it fails below.
            do {
                try fm.moveItem(at: sibling, to: destination)
            } catch {
                AppLogger.coreData.error("Could not move \(sibling.lastPathComponent, privacy: .public) aside: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Verify the primary file actually moved; if a transient error left
        // it behind, escalate so we don't end up with an empty new store
        // sharing a filename with a corrupt old one.
        if fm.fileExists(atPath: storeURL.path) {
            try fm.moveItem(at: storeURL, to: primaryRecoveryURL)
        }
        return primaryRecoveryURL
    }
    
    @objc private func handleStoreRemoved(_ notification: Notification) {
        container.viewContext.reset()
    }
    
    /// Called from the Settings "Enable iCloud Sync" flow. "Migrating to the new
    /// store" really means reloading the existing SQLite file with CloudKit
    /// mirroring attached — the bytes on disk are reused as-is, we only change
    /// whether `NSPersistentCloudKitContainer` syncs them to the user's private
    /// CloudKit database. This is what makes the toggle take effect immediately
    /// instead of only after the next cold launch.
    func migrateDataToNewStore(completion: @escaping (Result<Void, Error>) -> Void) {
        reloadStore(cloudKitEnabled: true, completion: completion)
    }

    /// Errors raised while reconfiguring the persistent store for a sync change.
    public enum SyncReconfigurationError: Error {
        case noStoreDescription
    }

    /// Tears down the currently-loaded persistent store and reloads it with (or
    /// without) CloudKit attached, so toggling iCloud sync applies to the live
    /// container without forcing a relaunch. No data is copied or deleted — the
    /// same on-disk store is reused; only the CloudKit mirroring option changes.
    public func reloadStore(cloudKitEnabled requestedCloudKit: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        // Never attach CloudKit on platforms where mirroring is intentionally
        // off (watchOS) even if a caller asks for it.
        let cloudKitEnabled = requestedCloudKit && Self.cloudKitMirroringSupported
        let coordinator = container.persistentStoreCoordinator
        guard let description = container.persistentStoreDescriptions.first else {
            completion?(.failure(SyncReconfigurationError.noStoreDescription))
            return
        }

        do {
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        } catch {
            AppLogger.coreData.error("Failed to detach store before reconfiguring iCloud sync: \(error.localizedDescription, privacy: .public)")
            completion?(.failure(error))
            return
        }

        if cloudKitEnabled {
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
        } else {
            description.setOption(false as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.cloudKitContainerOptions = nil
        }

        container.loadPersistentStores { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    AppLogger.coreData.error("Failed to reload store after toggling iCloud sync: \(error.localizedDescription, privacy: .public)")
                    self.syncStatus = .error(error.localizedDescription)
                    completion?(.failure(error))
                    return
                }
                self.isCloudKitEnabled = cloudKitEnabled
                self.container.viewContext.refreshAllObjects()
                self.syncStatus = cloudKitEnabled ? .enabled : .disabled
                if cloudKitEnabled {
                    self.verifyCloudAccountAvailable()
                }
                completion?(.success(()))
            }
        }
    }
}

extension UserDefaults {
    /// Effective default for the "Enable iCloud Sync" preference.
    ///
    /// - An explicit choice (the user toggled the switch at any point) always
    ///   wins — anyone who previously turned sync OFF persisted `false` and is
    ///   left untouched.
    /// - Otherwise the key has never been written, so we default ON. This makes
    ///   the app sync across a user's devices out of the box, including existing
    ///   users upgrading from a build where sync was off by default.
    ///
    /// Turning sync on never deletes data: the existing local store is reused
    /// in place and its records are exported to the user's private CloudKit
    /// database (see `PersistenceController.init` / `reloadStore`).
    var headwayICloudSyncEnabled: Bool {
        if let explicit = object(forKey: "useICloudSync") as? Bool {
            return explicit
        }
        return true
    }
} 