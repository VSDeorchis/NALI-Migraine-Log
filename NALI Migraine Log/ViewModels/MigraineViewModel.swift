import CoreData
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif
import OSLog

/// iOS/watchOS view model. `MigraineStore` owns the Core Data primitives;
/// this class layers the fetched-results controller, CloudKit status
/// bookkeeping, weather lookups, Watch sync and Health mirroring on top.
/// The extensions live alongside this file:
///  - `MigraineViewModel+Weather.swift`   — weather fetch/backfill
///  - `MigraineViewModel+CloudSync.swift` — CloudKit status + auto-sync timer
///  - `MigraineViewModel+Analytics.swift` — time-frame filtering and chart cache
///  - `MigraineViewModel+Debug.swift`     — DEBUG-only diagnostics
final class MigraineViewModel: MigraineStore {
    /// Mirrors `PersistenceController.syncStatus`, plus the local
    /// "pending changes" state driven by `noteLocalChangePendingSync()`.
    /// Written only by `+CloudSync`; views read it.
    @Published var syncStatus: SyncStatus = .notConfigured
    @Published var lastSyncTime: Date?
    @Published var weatherFetchStatus: WeatherFetchStatus = .idle

    enum WeatherFetchStatus: Equatable {
        case idle
        case fetching
        case success
        case failed(String)
        case locationDenied
    }

    private var cancellables = Set<AnyCancellable>()
    private var fetchedResultsController: NSFetchedResultsController<MigraineEvent>?

    /// Alias kept for source compatibility — all logging now flows through
    /// the shared `AppLogger.coreData` channel so it appears under one
    /// bundle-id-derived subsystem in Console.app instead of a hardcoded one.
    let migraineLog = AppLogger.coreData

    // Stored state for the extensions (Swift extensions cannot add storage).
    var pendingChanges = 0
    var autoSyncTask: Task<Void, Never>?
    let autoSyncInterval: TimeInterval = 300 // 5 minutes

    /// Weather lookups that are still running for a freshly-saved entry,
    /// keyed by the entry's object ID so a delete can cancel the lookup
    /// instead of letting it write into a dead managed object.
    var weatherTasks: [NSManagedObjectID: Task<Void, Never>] = [:]

    var chartCache = ChartCache()
    let chartCacheTimeout: TimeInterval = 5 // 5 seconds

    override init(context: NSManagedObjectContext) {
        super.init(context: context)
        setupFetchedResultsController()
        fetchMigraines()

        // Observe sync status changes
        PersistenceController.shared.$syncStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleSyncStatusChange(status)
            }
            .store(in: &cancellables)

        // Start auto-sync timer
        setupAutoSync()

        // Observe app lifecycle for sync management
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    deinit {
        autoSyncTask?.cancel()
        for task in weatherTasks.values { task.cancel() }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Fetching

    private func setupFetchedResultsController() {
        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        // Add batch size for better memory management
        request.fetchBatchSize = 20

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: "MigraineFetchCache"
        )

        fetchedResultsController?.delegate = self
    }

    override func fetchMigraines() {
        do {
            try fetchedResultsController?.performFetch()
            let newMigraines = fetchedResultsController?.fetchedObjects ?? []

            // Only update if there are actual changes
            if newMigraines != migraines {
                // Ensure every migraine has a stable UUID for SwiftUI Identifiable
                for migraine in newMigraines where migraine.id == nil {
                    migraine.id = UUID()
                }
                // Persist any newly-assigned IDs. A swallowed failure here
                // (disk full, schema mismatch) would re-assign IDs on every
                // fetch and the user would never be told, so it surfaces
                // through `lastError` like any other save failure.
                if viewContext.hasChanges {
                    do {
                        try viewContext.save()
                    } catch {
                        lastError = .saveFailed(error)
                        viewContext.rollback()
                        AppLogger.coreData.error("Failed to persist auto-assigned UUIDs: \(error.localizedDescription, privacy: .private)")
                    }
                }
                migraines = newMigraines
                invalidateCache()
            }
        } catch {
            lastError = .fetchFailed(error)
            AppLogger.coreData.error("Error fetching migraines: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Refresh migraines from Core Data (for pull-to-refresh)
    @MainActor
    func refreshMigraines() async {
        // Refresh the context to get latest from persistent store
        viewContext.refreshAllObjects()

        // Re-fetch migraines
        fetchMigraines()

        AppLogger.coreData.debug("Migraines refreshed: \(self.migraines.count, privacy: .public) entries")
    }

    /// Fetch only recent migraines (Watch app)
    func fetchRecentMigraines(limit: Int = 10) {
        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        request.fetchLimit = limit

        do {
            migraines = try viewContext.fetch(request)
        } catch {
            lastError = .fetchFailed(error)
            AppLogger.coreData.error("Error fetching recent migraines: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Create / update / delete

    @MainActor
    @discardableResult
    func addMigraine(
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        triggers: Set<MigraineTrigger>,
        hasAura: Bool,
        hasPhotophobia: Bool,
        hasPhonophobia: Bool,
        hasNausea: Bool,
        hasVomiting: Bool,
        hasWakeUpHeadache: Bool,
        hasTinnitus: Bool,
        hasVertigo: Bool,
        missedWork: Bool,
        missedSchool: Bool,
        missedEvents: Bool,
        medications: Set<MigraineMedication>,
        notes: String?
    ) async -> MigraineEvent? {
        migraineLog.debug("addMigraine called at \(Date(), privacy: .public)")

        let draft = MigraineDraft(
            startTime: startTime,
            endTime: endTime,
            painLevel: painLevel,
            location: location,
            notes: notes,
            triggers: triggers,
            medications: medications,
            hasAura: hasAura,
            hasPhotophobia: hasPhotophobia,
            hasPhonophobia: hasPhonophobia,
            hasNausea: hasNausea,
            hasVomiting: hasVomiting,
            hasWakeUpHeadache: hasWakeUpHeadache,
            hasTinnitus: hasTinnitus,
            hasVertigo: hasVertigo,
            missedWork: missedWork,
            missedSchool: missedSchool,
            missedEvents: missedEvents
        )

        guard let migraine = insertMigraine(draft) else { return nil }

        migraines.insert(migraine, at: 0)

        if let id = migraine.id {
            WatchConnectivityManager.shared.recordChange(of: id)
        }

        // Bump the engagement counter that gates the in-app review prompt.
        // Done only on the *initial* successful save (not on subsequent
        // weather/edit saves) so that a single user action produces a
        // single +1 — see `ReviewPromptCoordinator.swift` for the policy.
        ReviewPromptCoordinator.recordEntryLogged()

        // Mirror to Apple Health as a `.headache` sample if the user has
        // opted in via Settings. Fully no-ops when disabled or unauthorized
        // — see `HealthKitManager.writeMigraineToHealth` for the gate
        // cascade. Detached so a slow Health save never blocks the UI.
        if #available(iOS 17.0, watchOS 10.0, *) {
            Task { @MainActor in
                await HealthKitManager.shared.writeMigraineToHealth(migraine)
            }
        }

        startWeatherFetch(for: migraine)

        migraineLog.debug("addMigraine returning")
        return migraine
    }

    @MainActor
    func updateMigraine(
        _ migraine: MigraineEvent,
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        triggers: Set<MigraineTrigger>,
        medications: Set<MigraineMedication>,
        hasAura: Bool,
        hasPhotophobia: Bool,
        hasPhonophobia: Bool,
        hasNausea: Bool,
        hasVomiting: Bool,
        hasWakeUpHeadache: Bool,
        hasTinnitus: Bool,
        hasVertigo: Bool,
        missedWork: Bool,
        missedSchool: Bool,
        missedEvents: Bool,
        notes: String
    ) async {
        let draft = MigraineDraft(
            startTime: startTime,
            endTime: endTime,
            painLevel: painLevel,
            location: location,
            notes: notes,
            triggers: triggers,
            medications: medications,
            hasAura: hasAura,
            hasPhotophobia: hasPhotophobia,
            hasPhonophobia: hasPhonophobia,
            hasNausea: hasNausea,
            hasVomiting: hasVomiting,
            hasWakeUpHeadache: hasWakeUpHeadache,
            hasTinnitus: hasTinnitus,
            hasVertigo: hasVertigo,
            missedWork: missedWork,
            missedSchool: missedSchool,
            missedEvents: missedEvents
        )

        guard updateMigraine(migraine, with: draft) else { return }
        noteLocalChangePendingSync()

        if let id = migraine.id {
            WatchConnectivityManager.shared.recordChange(of: id)
        }

        // Mirror the edited migraine to Apple Health, replacing any sample
        // we previously wrote for the same id. `writeMigraineToHealth` is
        // delete-then-write internally, so this stays idempotent even if
        // the user toggles sync off and back on between edits.
        if #available(iOS 17.0, watchOS 10.0, *) {
            Task { @MainActor in
                await HealthKitManager.shared.writeMigraineToHealth(migraine)
            }
        }
    }

    /// Deletes the entry, cancels any weather lookup still running for it,
    /// and propagates the deletion to the Watch and to Apple Health.
    @MainActor
    @discardableResult
    override func deleteMigraine(_ migraine: MigraineEvent) -> Bool {
        guard let id = migraine.id else { return false }
        // Captured before the Core Data delete so the Health sample can
        // still be addressed after the managed object goes away.
        let mirroredID = id.uuidString

        weatherTasks.removeValue(forKey: migraine.objectID)?.cancel()

        guard super.deleteMigraine(migraine) else { return false }

        WatchConnectivityManager.shared.recordDeletion(of: id)
        if #available(iOS 17.0, watchOS 10.0, *) {
            Task { @MainActor in
                await HealthKitManager.shared.mirrorDeletion(ofMigraineUUID: mirroredID)
            }
        }
        return true
    }

    /// Adds Watch tombstones and export cleanup to the shared delete-all.
    @MainActor
    override func deleteAllData() async throws -> DeleteAllOutcome {
        for task in weatherTasks.values { task.cancel() }
        weatherTasks.removeAll()

        let outcome = try await super.deleteAllData()
        invalidateCache()
        return outcome
    }

    @MainActor
    override func migrainesWereErased(ids: [UUID]) {
        WatchConnectivityManager.shared.recordDeletions(of: ids)
        Self.removeExportFiles()
    }

    /// File name prefix shared by CSV and PDF exports; used to find and
    /// remove leftover exports without touching anything else in tmp.
    static let exportFilePrefix = "Headway_Migraine_"

    /// Deletes export files left in the temporary directory after a share
    /// sheet was dismissed. Safe to call any time; exports are rebuilt on
    /// demand.
    static func removeExportFiles() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let contents = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(exportFilePrefix) {
            do {
                try fm.removeItem(at: url)
            } catch {
                AppLogger.coreData.debug("Could not remove stale export: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func getUserNotes(from migraine: MigraineEvent) -> String? {
        migraine.notes
    }

    /// Counts a local save toward the "pending changes" CloudKit state.
    func noteLocalChangePendingSync() {
        pendingChanges += 1
        if case .enabled = syncStatus {
            syncStatus = .pendingChanges(pendingChanges)
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension MigraineViewModel: NSFetchedResultsControllerDelegate {
    /// The controller is bound to the main-queue `viewContext`, so Core Data
    /// delivers this on the main thread; `assumeIsolated` makes that contract
    /// explicit and keeps the managed objects from crossing an isolation
    /// boundary.
    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        MainActor.assumeIsolated {
            let newMigraines = controller.fetchedObjects as? [MigraineEvent] ?? []
            // Only publish when data actually changed to avoid unnecessary re-renders
            if newMigraines.count != migraines.count ||
               newMigraines.map({ $0.objectID }) != migraines.map({ $0.objectID }) {
                migraines = newMigraines
            }
        }
    }
}
