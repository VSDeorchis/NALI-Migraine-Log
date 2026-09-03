import CoreData
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import OSLog

enum MigraineError: LocalizedError {
    case saveFailed(Error)
    case fetchFailed(Error)
    case invalidData(String)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save migraine: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch migraines: \(error.localizedDescription)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        }
    }
}

class MigraineViewModel: NSObject, ObservableObject {
    enum TimeFrame: Hashable {
        case week
        case month
        case year
    }

    /// Result of `deleteAllData()`. Core Data, Watch bookkeeping, ML
    /// artifacts and stale exports are always cleared or the call throws;
    /// Health is the one dependency whose failure is reported instead,
    /// because the local wipe already happened and the user can finish
    /// the job in the Health app.
    struct DeleteAllOutcome {
        var deletedCount: Int
        var healthCleanupError: Error?
    }
    
    @Published private(set) var migraines: [MigraineEvent] = []
    @Published private(set) var lastError: MigraineError?
    @Published private(set) var syncStatus: SyncStatus = .notConfigured
    @Published private(set) var lastSyncTime: Date?
    @Published var weatherFetchStatus: WeatherFetchStatus = .idle
    private var pendingChanges: Int = 0
    
    enum WeatherFetchStatus: Equatable {
        case idle
        case fetching
        case success
        case failed(String)
        case locationDenied
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private let viewContext: NSManagedObjectContext
    private var fetchedResultsController: NSFetchedResultsController<MigraineEvent>?
    
    /// Alias kept for source compatibility — all logging now flows through
    /// the shared `AppLogger.coreData` channel so it appears under one
    /// bundle-id-derived subsystem in Console.app instead of a hardcoded one.
    private let migraineLog = AppLogger.coreData
    
    // Update these constants
    let locations = [
        "Frontal",
        "Whole Head",
        "Left Side",
        "Right Side",
        "Occipital/Back of Head"
    ]

    let triggers = [
        "Stress",
        "Lack of Sleep",
        "Dehydration",
        "Weather",
        "Menstrual",
        "Alcohol",
        "Caffeine",
        "Food",
        "Exercise",
        "Screen Time",
        "Other"
    ]
    
    let medications = [
        "Ibuprofen",
        "Excedrin",
        "Tylenol",
        "Sumatriptan",
        "Rizatriptan",
        "Naproxen",
        "Frovatriptan",
        "Naratriptan",
        "Nurtec",
        "Symbravo",
        "Ubrelvy",
        "Reyvow",
        "Trudhesa",
        "Elyxyb",
        "Other"
    ]
    
    private var autoSyncTimer: Timer?
    private let autoSyncInterval: TimeInterval = 300 // 5 minutes

    /// Weather lookups that are still running for a freshly-saved entry,
    /// keyed by the entry's object ID so a delete can cancel the lookup
    /// instead of letting it write into a dead managed object.
    private var weatherTasks: [NSManagedObjectID: Task<Void, Never>] = [:]

    private struct ChartCache {
        var filtered: [TimeFrame: [MigraineEvent]] = [:]
        var triggers: [TimeFrame: [(String, Int)]] = [:]
        var medications: [TimeFrame: [(String, Int)]] = [:]
        var updatedAt: Date?

        func isFresh(within timeout: TimeInterval) -> Bool {
            guard let updatedAt else { return false }
            return Date().timeIntervalSince(updatedAt) < timeout
        }

        mutating func removeAll() {
            filtered.removeAll()
            triggers.removeAll()
            medications.removeAll()
            updatedAt = nil
        }
    }

    private var chartCache = ChartCache()
    private let chartCacheTimeout: TimeInterval = 5 // 5 seconds
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        super.init()
        setupFetchedResultsController()
        fetchMigraines()
        
        // Observe sync status changes
        PersistenceController.shared.$syncStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.syncStatus = status
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
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppForeground),
            name: NSApplication.willBecomeActiveNotification,
            object: nil
        )
        #endif
    }
    
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
    
    func fetchMigraines() {
        do {
            try fetchedResultsController?.performFetch()
            let newMigraines = fetchedResultsController?.fetchedObjects ?? []
            
            // Only update if there are actual changes
            if newMigraines != migraines {
                // Ensure every migraine has a stable UUID for SwiftUI Identifiable
                for migraine in newMigraines where migraine.id == nil {
                    migraine.id = UUID()
                }
                // Persist any newly-assigned IDs. Previously this used `try?`
                // which swallowed errors silently — meaning a failed save (e.g.
                // disk full, schema mismatch) would re-assign IDs on every
                // single fetch and the user would never be told. Surface the
                // failure through `lastError` so it bubbles up like any other
                // save failure.
                if viewContext.hasChanges {
                    do {
                        try viewContext.save()
                    } catch {
                        lastError = .saveFailed(error)
                        viewContext.rollback()
                        AppLogger.coreData.error("Failed to persist auto-assigned UUIDs: \(error.localizedDescription, privacy: .public)")
                    }
                }
                migraines = newMigraines
                invalidateCache()
            }
        } catch {
            lastError = .fetchFailed(error)
            AppLogger.coreData.error("Error fetching migraines: \(error.localizedDescription, privacy: .public)")
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

    // Add method to fetch only recent migraines for Watch app
    func fetchRecentMigraines(limit: Int = 10) {
        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        request.fetchLimit = limit

        do {
            migraines = try viewContext.fetch(request)
        } catch {
            lastError = .fetchFailed(error)
            AppLogger.coreData.error("Error fetching recent migraines: \(error.localizedDescription, privacy: .public)")
        }
    }
    
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

        let migraine = MigraineEvent(context: viewContext)
        migraine.id = UUID()
        migraine.startTime = startTime
        migraine.endTime = endTime
        migraine.painLevel = painLevel
        migraine.location = location
        migraine.notes = notes

        migraine.hasAura = hasAura
        migraine.hasPhotophobia = hasPhotophobia
        migraine.hasPhonophobia = hasPhonophobia
        migraine.hasNausea = hasNausea
        migraine.hasVomiting = hasVomiting
        migraine.hasWakeUpHeadache = hasWakeUpHeadache
        migraine.hasTinnitus = hasTinnitus
        migraine.hasVertigo = hasVertigo
        migraine.missedWork = missedWork
        migraine.missedSchool = missedSchool
        migraine.missedEvents = missedEvents

        migraine.triggers = triggers
        migraine.medications = medications
        
        // Ensure all default values are set before saving
        migraine.hasWeatherData = false
        migraine.weatherTemperature = 0
        migraine.weatherPressure = 0
        migraine.weatherPressureChange24h = 0
        migraine.weatherPrecipitation = 0
        migraine.weatherCloudCover = 0
        migraine.weatherCode = 0
        migraine.weatherLatitude = 0
        migraine.weatherLongitude = 0
        
        // Temporarily disable automatic merging to prevent deadlock
        let originalMergesSetting = viewContext.automaticallyMergesChangesFromParent
        viewContext.automaticallyMergesChangesFromParent = false
        
        do {
            migraineLog.debug("Saving initial migraine to Core Data")
            try viewContext.save()

            // Re-enable automatic merging
            viewContext.automaticallyMergesChangesFromParent = originalMergesSetting

            // Refresh the object to ensure it's not a fault
            viewContext.refresh(migraine, mergeChanges: false)
            migraines.insert(migraine, at: 0)

            migraineLog.notice("Migraine saved (initial data); id=\(migraine.id?.uuidString ?? "nil", privacy: .public); array count=\(self.migraines.count, privacy: .public)")

            if let id = migraine.id {
                WatchConnectivityManager.shared.recordChange(of: id)
            }

            // Bump the engagement counter that gates the in-app review
            // prompt. Done only on the *initial* successful save (not on
            // subsequent weather/edit saves) so that a single user action
            // produces a single +1 — see `ReviewPromptCoordinator.swift`
            // for the full gating policy. The enclosing function is
            // `@MainActor async`, and `recordEntryLogged()` has no actor
            // isolation, so a direct synchronous call is correct here —
            // wrapping in `MainActor.assumeIsolated { … }` from an async
            // context is what triggered the Swift 6 strictness warning.
            ReviewPromptCoordinator.recordEntryLogged()

            // Mirror to Apple Health as a `.headache` sample if the user
            // has opted in via Settings. Fully no-ops when disabled or
            // unauthorized — see `HealthKitManager.writeMigraineToHealth`
            // for the gate cascade. Detached so a slow Health save never
            // blocks the UI snapping closed; HealthKit calls are MainActor-
            // isolated so we hop back inside the task.
            if #available(iOS 17.0, watchOS 10.0, *) {
                Task { @MainActor in
                    await HealthKitManager.shared.writeMigraineToHealth(migraine)
                }
            }
        } catch {
            viewContext.automaticallyMergesChangesFromParent = originalMergesSetting
            viewContext.rollback()
            lastError = .saveFailed(error)
            migraineLog.error("Failed to save migraine: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        startWeatherFetch(for: migraine)

        migraineLog.debug("addMigraine returning")
        return migraine
    }

    /// Kicks off the weather lookup for a just-saved entry and keeps the
    /// task so `deleteMigraine`/`deleteAllData` can cancel it. The task is
    /// MainActor-isolated because `MigraineEvent` is a non-Sendable
    /// NSManagedObject owned by the main-queue `viewContext`.
    @MainActor
    private func startWeatherFetch(for migraine: MigraineEvent) {
        let objectID = migraine.objectID
        weatherTasks[objectID]?.cancel()
        weatherTasks[objectID] = Task { @MainActor [weak self] in
            defer { self?.weatherTasks.removeValue(forKey: objectID) }
            guard let self else { return }
            await self.fetchWeatherData(for: migraine)
            guard !Task.isCancelled, Self.isLive(migraine) else { return }
            self.saveWeatherChanges(for: migraine)
        }
    }

    /// True while the object is still attached to a context and has not
    /// been deleted; weather results for anything else are dropped.
    private static func isLive(_ migraine: MigraineEvent) -> Bool {
        !migraine.isDeleted && migraine.managedObjectContext != nil
    }

    @MainActor
    private func saveWeatherChanges(for migraine: MigraineEvent) {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            if let id = migraine.id {
                WatchConnectivityManager.shared.recordChange(of: id)
            }
        } catch {
            viewContext.rollback()
            lastError = .saveFailed(error)
            migraineLog.error("Failed to save weather data: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Weather Integration
    
    /// Fetch weather data for a migraine event.
    ///
    /// `@MainActor` is required: `MigraineEvent` is a non-Sendable
    /// NSManagedObject, so reading/writing its properties must happen on the
    /// thread that owns its context (`viewContext` is main-thread). The
    /// `await` calls below suspend the MainActor cooperatively while the
    /// network request runs on its own executor — we never block main.
    @MainActor
    private func fetchWeatherData(for migraine: MigraineEvent) async {
        migraineLog.debug("🌤️ fetchWeatherData started for migraine id \(migraine.id?.uuidString ?? "nil", privacy: .public)")
        guard let startTime = migraine.startTime else {
            migraineLog.error("No start time; aborting weather fetch")
            weatherFetchStatus = .failed("No start time available")
            return
        }
        
        weatherFetchStatus = .fetching
        
        do {
            // Try to get current location
            migraineLog.debug("Requesting current location")
            let location = try await LocationManager.shared.getCurrentLocation()
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            
            AppLogger.weather.debug("Fetching weather for current location (accuracy \(Int(location.horizontalAccuracy), privacy: .public) m)")
            
            // Fetch weather snapshot with timeout
            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
            }
            guard Self.isLive(migraine) else {
                migraineLog.debug("Weather snapshot arrived for a deleted entry; discarding")
                weatherFetchStatus = .idle
                return
            }
            migraineLog.debug("Weather snapshot received; updating migraine")
            
            // Update migraine with weather data — already on MainActor, no
            // explicit hop needed.
            migraine.updateWeatherData(from: snapshot)
            migraine.updateWeatherLocation(latitude: latitude, longitude: longitude)
            weatherFetchStatus = .success
            AppLogger.weather.notice("Weather data added: \(snapshot.weatherCondition, privacy: .public), \(Int(snapshot.temperature), privacy: .public)°F, 24h pressure change=\(String(format: "%.2f", snapshot.pressureChange24h * 0.75006), privacy: .public) mmHg")
            
            // Reset status after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
            
        } catch LocationError.unauthorized {
            AppLogger.weather.notice("Location access not authorized; weather data unavailable")
            weatherFetchStatus = .locationDenied
            // Reset after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            weatherFetchStatus = .idle
        } catch is TimeoutError {
            AppLogger.weather.error("Weather fetch timed out — API slow or unavailable")
            weatherFetchStatus = .failed("Weather service timed out")
            // Reset after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
        } catch {
            migraineLog.error("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
            weatherFetchStatus = .failed(error.localizedDescription)
            // Reset after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
        }
    }
    
    /// Helper function to add timeout to async operations.
    ///
    /// Implementation note: the throwing task group is started with two
    /// child tasks (the real `operation` and a sleep that throws
    /// `TimeoutError`), so `group.next()` is guaranteed to yield exactly
    /// one completed task before we cancel the rest. The previous
    /// implementation used `try await group.next()!` here, which was
    /// safe by construction but read like a latent crash to anyone
    /// auditing the file. The explicit `guard` documents the invariant
    /// without changing behavior — if `group.next()` ever returned
    /// `nil` (which would only happen if the group held zero tasks),
    /// we now throw `TimeoutError` rather than `fatalError`.
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
    
    struct TimeoutError: Error {}
    
    /// Retry fetching weather data for a migraine (manual retry)
    @MainActor
    func retryWeatherFetch(for migraine: MigraineEvent) async {
        guard !migraine.hasWeatherData else {
            AppLogger.weather.debug("retryWeatherFetch ignored — migraine already has weather data")
            return
        }

        AppLogger.weather.notice("Retrying weather fetch for migraine")
        await fetchWeatherData(for: migraine)
        guard Self.isLive(migraine) else { return }
        saveWeatherChanges(for: migraine)
    }

    /// Fetch weather data for a specific location (manual override)
    @MainActor
    func fetchWeatherForCustomLocation(
        for migraine: MigraineEvent,
        latitude: Double,
        longitude: Double
    ) async {
        guard let startTime = migraine.startTime else {
            AppLogger.weather.error("fetchWeatherForCustomLocation: no start time on migraine")
            weatherFetchStatus = .failed("No start time available")
            return
        }

        weatherFetchStatus = .fetching

        do {
            AppLogger.weather.debug("Fetching weather for a user-chosen location")

            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
            }

            guard Self.isLive(migraine) else {
                weatherFetchStatus = .idle
                return
            }

            // Update migraine with weather data
            migraine.updateWeatherData(from: snapshot)
            migraine.updateWeatherLocation(latitude: latitude, longitude: longitude)
            weatherFetchStatus = .success

            // Save changes
            try viewContext.save()
            if let id = migraine.id {
                WatchConnectivityManager.shared.recordChange(of: id)
            }
            AppLogger.weather.notice("Weather data updated with custom location")

            // Reset status after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle

        } catch {
            if viewContext.hasChanges { viewContext.rollback() }
            AppLogger.weather.error("Failed to fetch weather for custom location: \(error.localizedDescription, privacy: .public)")
            weatherFetchStatus = .failed(error.localizedDescription)

            // Reset after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
        }
    }

    /// Bulk fetch weather data for all migraines without weather data
    @MainActor
    func backfillWeatherData(progressCallback: @escaping (Int, Int) -> Void) async -> (success: Int, failed: Int) {
        // Get all migraines without weather data
        let migrainesWithoutWeather = migraines.filter { !$0.hasWeatherData }
        let total = migrainesWithoutWeather.count

        guard total > 0 else {
            AppLogger.weather.debug("backfillWeatherData: nothing to do")
            return (0, 0)
        }

        AppLogger.weather.notice("Starting bulk weather fetch for \(total, privacy: .public) migraines")

        var successCount = 0
        var failedCount = 0

        for (index, migraine) in migrainesWithoutWeather.enumerated() {
            if Task.isCancelled { break }
            progressCallback(index + 1, total)

            guard Self.isLive(migraine) else {
                failedCount += 1
                continue
            }

            // Fetch weather data
            await fetchWeatherData(for: migraine)

            // Check if successful
            if Self.isLive(migraine), migraine.hasWeatherData {
                successCount += 1
                saveWeatherChanges(for: migraine)
            } else {
                failedCount += 1
            }

            // Small delay to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        AppLogger.weather.notice("Bulk weather fetch complete: \(successCount, privacy: .public) success, \(failedCount, privacy: .public) failed")
        return (successCount, failedCount)
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
        migraine.startTime = startTime
        migraine.endTime = endTime
        migraine.painLevel = painLevel
        migraine.location = location
        migraine.notes = notes

        migraine.triggers = triggers
        migraine.medications = medications

        migraine.hasAura = hasAura
        migraine.hasPhotophobia = hasPhotophobia
        migraine.hasPhonophobia = hasPhonophobia
        migraine.hasNausea = hasNausea
        migraine.hasVomiting = hasVomiting
        migraine.hasWakeUpHeadache = hasWakeUpHeadache
        migraine.hasTinnitus = hasTinnitus
        migraine.hasVertigo = hasVertigo
        migraine.missedWork = missedWork
        migraine.missedSchool = missedSchool
        migraine.missedEvents = missedEvents

        guard save() else { return }

        if let id = migraine.id {
            WatchConnectivityManager.shared.recordChange(of: id)
        }

        // Mirror the edited migraine to Apple Health, replacing any
        // sample we previously wrote for the same id. The
        // `writeMigraineToHealth` path is delete-then-write internally,
        // so this stays idempotent even if the user toggles sync off
        // and back on between edits.
        if #available(iOS 17.0, watchOS 10.0, *) {
            Task { @MainActor in
                await HealthKitManager.shared.writeMigraineToHealth(migraine)
            }
        }
    }
    
    @MainActor
    func deleteMigraine(_ migraine: MigraineEvent) {
        guard let id = migraine.id else { return }
        let mirroredID = id.uuidString

        weatherTasks.removeValue(forKey: migraine.objectID)?.cancel()
        
        // Just delete the migraine - no need to handle relationships since we're using strings
        viewContext.delete(migraine)
        
        do {
            try viewContext.save()
            WatchConnectivityManager.shared.recordDeletion(of: id)
            // Mirror the deletion to Apple Health if mirroring is on. Captured
            // the UUID into a local before the Core Data delete so we can
            // still address the Health sample after the managed object goes
            // away. Health-side errors are logged inside the manager and
            // never block the Core Data save we already committed.
            if #available(iOS 17.0, watchOS 10.0, *) {
                Task { @MainActor in
                    await HealthKitManager.shared.mirrorDeletion(ofMigraineUUID: mirroredID)
                }
            }
            fetchMigraines()  // Refresh the list
        } catch {
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error deleting migraine: \(error.localizedDescription, privacy: .public)")
            viewContext.rollback()
        }
    }
    
    /// Saves `viewContext` synchronously (it is a main-queue context and
    /// every caller is already on the main actor). Returns `false` and
    /// publishes `lastError` when the save fails.
    @MainActor
    @discardableResult
    private func save() -> Bool {
        guard viewContext.hasChanges else { return true }

        do {
            try viewContext.save()
            pendingChanges += 1
            if case .enabled = syncStatus {
                syncStatus = .pendingChanges(pendingChanges)
            }
            return true
        } catch {
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error saving context: \(error.localizedDescription, privacy: .public)")
            viewContext.rollback()
            return false
        }
    }
    
    private func validateMigraine(
        startTime: Date,
        endTime: Date?,
        painLevel: Int
    ) -> Result<Void, MigraineError> {
        // Validate start time is not in future
        if startTime > Date() {
            return .failure(.invalidData("Start time cannot be in the future"))
        }
        
        // Validate end time is after start time
        if let endTime = endTime {
            if endTime < startTime {
                return .failure(.invalidData("End time must be after start time"))
            }
            if endTime > Date() {
                return .failure(.invalidData("End time cannot be in the future"))
            }
        }
        
        // Validate pain level
        if painLevel < 1 || painLevel > 10 {
            return .failure(.invalidData("Pain level must be between 1 and 10"))
        }
        
        return .success(())
    }
    
    #if DEBUG
    /// Dev-only diagnostic dump of the in-memory migraine list. Only
    /// non-identifying fields (id, timestamps, pain, counts) are logged.
    func printDebugInfo() {
        AppLogger.coreData.debug("=== Current Migraines (\(self.migraines.count, privacy: .public)) ===")
        for migraine in migraines {
            AppLogger.coreData.debug(
                "id=\(migraine.id?.uuidString ?? "nil", privacy: .public) start=\(migraine.startTime?.description ?? "nil", privacy: .public) pain=\(migraine.painLevel, privacy: .public) triggers=\(migraine.triggers.count, privacy: .public) meds=\(migraine.medications.count, privacy: .public) hasNotes=\(!(migraine.notes ?? "").isEmpty, privacy: .public)"
            )
        }
    }
    #endif

    /// Erases every migraine on this device and everything derived from it:
    /// Core Data rows (deleted one by one so CloudKit mirroring propagates
    /// the deletes — batch requests bypass the mirroring pipeline), Watch
    /// sync bookkeeping (the Watch receives tombstones for every id), the
    /// Health samples this app wrote, the on-device ML training data and
    /// model, and any export files still sitting in the temp directory.
    /// Recovery backups made by `PersistenceController` are left alone;
    /// the user manages those explicitly from Settings.
    @MainActor
    func deleteAllData() async throws -> DeleteAllOutcome {
        for task in weatherTasks.values { task.cancel() }
        weatherTasks.removeAll()

        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")

        let all: [MigraineEvent]
        do {
            all = try viewContext.fetch(request)
        } catch {
            lastError = .fetchFailed(error)
            throw MigraineError.fetchFailed(error)
        }

        let ids = all.compactMap(\.id)
        for migraine in all {
            viewContext.delete(migraine)
        }

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error clearing data: \(error.localizedDescription, privacy: .public)")
            throw MigraineError.saveFailed(error)
        }

        WatchConnectivityManager.shared.recordDeletions(of: ids)
        MigrainePredictionService.shared.clearTrainedArtifacts()
        Self.removeExportFiles()

        var outcome = DeleteAllOutcome(deletedCount: all.count)
        if #available(iOS 17.0, watchOS 10.0, *) {
            do {
                try await HealthKitManager.shared.deleteAllMirroredSamples()
            } catch {
                outcome.healthCleanupError = error
                AppLogger.health.error("Delete-all could not remove Health samples: \(error.localizedDescription, privacy: .public)")
            }
        }

        migraines = []
        invalidateCache()
        fetchMigraines()

        AppLogger.coreData.notice("Deleted all migraine data (\(all.count, privacy: .public) entries)")
        return outcome
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
                AppLogger.coreData.debug("Could not remove stale export: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func getUserNotes(from migraine: MigraineEvent) -> String? {
        return migraine.notes
    }

    var commonTriggers: [(String, Int)] {
        var triggerCounts: [String: Int] = [:]
        for migraine in migraines {
            for trigger in migraine.triggers {
                triggerCounts[trigger.displayName, default: 0] += 1
            }
        }
        return triggerCounts.sorted { $0.value > $1.value }
    }

    var medicationUsage: [(String, Int)] {
        var medicationCounts: [String: Int] = [:]
        for migraine in migraines {
            for medication in migraine.medications {
                medicationCounts[medication.displayName, default: 0] += 1
            }
        }
        
        return medicationCounts.sorted { $0.value > $1.value }
    }
    
    var averagePainLevel: Double {
        guard !migraines.isEmpty else { return 0 }
        let sum = migraines.reduce(0) { $0 + Double($1.painLevel) }
        return sum / Double(migraines.count)
    }
    
    var migraineFrequency: String {
        guard !migraines.isEmpty else { return "No data" }
        
        let calendar = Calendar.current
        let now = Date()
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        
        let monthlyCount = migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return startTime >= oneMonthAgo
        }.count
        
        return "\(monthlyCount) per month"
    }
    
    var averageDuration: TimeInterval? {
        let durationsWithEndTime = migraines.compactMap { migraine -> TimeInterval? in
            guard let startTime = migraine.startTime,
                  let endTime = migraine.endTime else { return nil }
            return endTime.timeIntervalSince(startTime)
        }
        
        guard !durationsWithEndTime.isEmpty else { return nil }
        return durationsWithEndTime.reduce(0, +) / Double(durationsWithEndTime.count)
    }
    
    // Make migration actually async
    func migrateToDifferentStore() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PersistenceController.shared.migrateDataToNewStore { (result: Result<Void, Error>) in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // Add proper async error handling
    private func handleMigrationError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            AppLogger.migration.error("Migration error: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func setupAutoSync() {
        autoSyncTimer?.invalidate()
        
        // Only setup timer if sync is enabled
        guard case .enabled = syncStatus else { return }
        
        autoSyncTimer = Timer.scheduledTimer(
            withTimeInterval: autoSyncInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkAndSync()
        }
    }
    
    private func checkAndSync() {
        guard case .pendingChanges = syncStatus else { return }
        syncPendingChanges()
    }
    
    private func handleSyncStatusChange(_ status: SyncStatus) {
        syncStatus = status
        switch status {
        case .enabled:
            setupAutoSync()
        case .disabled:
            autoSyncTimer?.invalidate()
            autoSyncTimer = nil
            AppLogger.sync.notice("CloudKit sync disabled — using local storage only")
        case .error, .signInRequired:
            autoSyncTimer?.invalidate()
            autoSyncTimer = nil
        case .notConfigured, .pendingChanges, .syncing:
            break
        }
    }
    
    @objc private func handleAppBackground() {
        // Sync immediately when app goes to background
        checkAndSync()
    }
    
    @objc private func handleAppForeground() {
        // Check for changes and setup sync timer when app comes to foreground
        setupAutoSync()
        checkAndSync()
    }
    
    deinit {
        autoSyncTimer?.invalidate()
        for task in weatherTasks.values { task.cancel() }
        NotificationCenter.default.removeObserver(self)
    }
    
    // Update existing syncPendingChanges to be more robust
    func syncPendingChanges() {
        guard case .pendingChanges = syncStatus else { return }
        
        syncStatus = .syncing(0.0)
        
        // Start with a quick sync attempt
        do {
            try viewContext.save()
            
            // Mark sync as complete after a short delay
            // (Avoids rapid @Published updates that cause excessive re-renders)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.syncStatus = .enabled
                self?.lastSyncTime = Date()
                self?.pendingChanges = 0
            }
        } catch {
            syncStatus = .error("Sync failed: \(error.localizedDescription)")
            // Retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.checkAndSync()
            }
        }
    }
    
    func getTriggerFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        if chartCache.isFresh(within: chartCacheTimeout),
           let cached = chartCache.triggers[timeFilter] {
            return cached
        }

        var triggerCounts: [String: Int] = [:]
        for migraine in filteredMigraines(for: timeFilter) {
            for trigger in migraine.triggers {
                triggerCounts[trigger.displayName, default: 0] += 1
            }
        }

        let result = triggerCounts.sorted { $0.value > $1.value }
        chartCache.triggers[timeFilter] = result
        chartCache.updatedAt = Date()
        return result
    }

    func getMedicationFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        if chartCache.isFresh(within: chartCacheTimeout),
           let cached = chartCache.medications[timeFilter] {
            return cached
        }

        var medicationCounts: [String: Int] = [:]
        for migraine in filteredMigraines(for: timeFilter) {
            for medication in migraine.medications {
                medicationCounts[medication.displayName, default: 0] += 1
            }
        }

        let result = medicationCounts.sorted { $0.value > $1.value }
        chartCache.medications[timeFilter] = result
        chartCache.updatedAt = Date()
        return result
    }
    
    // Add safe navigation state management
    func clearNavigationSelections() {
        // This should be called when navigation state needs to be reset
        chartCache.removeAll()
    }
    
    // Optimize filtered migraines
    private func filteredMigraines(for timeFrame: TimeFrame) -> [MigraineEvent] {
        if chartCache.isFresh(within: chartCacheTimeout),
           let cached = chartCache.filtered[timeFrame] {
            return cached
        }
        
        let filtered = migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return isDate(startTime, inTimeFrame: timeFrame)
        }
        
        chartCache.filtered[timeFrame] = filtered
        chartCache.updatedAt = Date()
        return filtered
    }
    
    // Add cache invalidation
    func invalidateCache() {
        chartCache.removeAll()
        objectWillChange.send()
    }
    
    private func isDate(_ date: Date, inTimeFrame timeFrame: TimeFrame) -> Bool {
        guard let interval = Self.interval(for: timeFrame, containing: Date()) else {
            return false
        }
        return interval.contains(date) && date < interval.end
    }

    /// Calendar interval (week / month / year) containing `reference`, or
    /// `nil` if the calendar cannot produce one for that instant.
    private static func interval(for timeFrame: TimeFrame, containing reference: Date) -> DateInterval? {
        let component: Calendar.Component
        switch timeFrame {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return Calendar.current.dateInterval(of: component, for: reference)
    }
    
    #if DEBUG
    /// Dev-only data dump of non-identifying fields (id, dates, pain,
    /// counts). Free-text fields are never logged.
    func verifyMigraineData(_ migraine: MigraineEvent) {
        AppLogger.coreData.debug(
            "verifyMigraineData id=\(migraine.id?.uuidString ?? "nil", privacy: .public) start=\(migraine.startTime?.description ?? "nil", privacy: .public) pain=\(migraine.painLevel, privacy: .public) triggers=\(migraine.triggers.count, privacy: .public) meds=\(migraine.medications.count, privacy: .public)"
        )
    }

    private func verifyAllMigraines() {
        let fetchRequest: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "notes CONTAINS[c] %@", "test migraine")

        do {
            let testMigraines = try viewContext.fetch(fetchRequest)
            AppLogger.coreData.debug("verifyAllMigraines: found \(testMigraines.count, privacy: .public) test entries")
            for migraine in testMigraines {
                verifyMigraineData(migraine)
            }
        } catch {
            AppLogger.coreData.error("Error verifying test data: \(error.localizedDescription, privacy: .public)")
        }
    }

    func createTestData() {
        let today = Date()
        let migraine1 = MigraineEvent(context: viewContext)
        migraine1.id = UUID()
        migraine1.startTime = today
        migraine1.endTime = today.addingTimeInterval(7200)
        migraine1.painLevel = 5
        migraine1.location = "Frontal"
        migraine1.notes = "Test migraine today"
        migraine1.triggers = [.stress, .lackOfSleep]
        migraine1.medications = [.sumatriptan]

        do {
            try viewContext.save()
            AppLogger.coreData.notice("Saved test migraines")
            fetchMigraines()
            verifyAllMigraines()
        } catch {
            AppLogger.coreData.error("Error saving test data: \(error.localizedDescription, privacy: .public)")
            viewContext.rollback()
        }
    }
    #endif
    
    /// Warms the chart caches for `timeFilter`. Every helper it calls only
    /// touches in-memory state, so the work is done inline on the main
    /// actor rather than hopping to a detached task and back.
    @MainActor
    func loadChartData(for timeFilter: TimeFrame) async {
        guard !chartCache.isFresh(within: chartCacheTimeout) else { return }

        chartCache.filtered[timeFilter] = filteredMigraines(for: timeFilter)
        chartCache.triggers[timeFilter] = getTriggerFrequency(for: timeFilter)
        chartCache.medications[timeFilter] = getMedicationFrequency(for: timeFilter)
        chartCache.updatedAt = Date()
        objectWillChange.send()
    }
    
}

// Add NSFetchedResultsController delegate
extension MigraineViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let newMigraines = controller.fetchedObjects as? [MigraineEvent] ?? []
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Only publish when data actually changed to avoid unnecessary re-renders
            if newMigraines.count != self.migraines.count ||
               newMigraines.map({ $0.objectID }) != self.migraines.map({ $0.objectID }) {
                self.migraines = newMigraines
            }
        }
    }
} 