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

import CoreData
import SwiftUI

public final class PersistenceController: ObservableObject {
    @Published public var syncStatus: SyncStatus = .notConfigured
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
            
            // Enable CloudKit sync if user has opted in
            if UserDefaults.standard.bool(forKey: "useICloudSync") {
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.nali.migrainelog"
                )
                syncStatus = .syncing(0.0)
            } else {
                // Explicitly disable CloudKit sync
                description.cloudKitContainerOptions = nil
            }
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                AppLogger.coreData.error("Core Data failed to load: \(error.localizedDescription, privacy: .public)")
                self.handlePersistentStoreError(error)
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
        
        // Listen for CloudKit remote change notifications
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main) { [weak self] _ in
                self?.container.viewContext.refreshAllObjects()
                self?.syncStatus = .enabled
        }
    }
    
    /// UserDefaults key under which the path to the most recently moved-aside
    /// store is recorded. A future "Recover from backup" UI in Settings can
    /// surface this so users can hand the file to support or attempt re-import.
    public static let lastRecoveryFileDefaultsKey = "lastCoreDataRecoveryFilePath"

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

            try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: nil
            )
        } catch {
            // Even on recovery failure we have NOT deleted user data.
            // The original store (if it still exists) is untouched on disk.
            AppLogger.coreData.fault("Failed to recover from persistent store error: \(error.localizedDescription, privacy: .public)")
            fatalError("Unresolvable Core Data error: \(error)")
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
    
    func migrateDataToNewStore(completion: @escaping (Result<Void, Error>) -> Void) {
        // Implement migration logic here
        completion(.success(()))
    }
} 