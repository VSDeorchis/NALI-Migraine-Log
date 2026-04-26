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
    enum TimeFrame {
        case week
        case month
        case year
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
    
    // Add caching for chart data
    private var chartDataCache: [String: Any] = [:]
    private var lastChartUpdateTime: Date?
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

            // Bump the engagement counter that gates the in-app review
            // prompt. Done only on the *initial* successful save (not on
            // subsequent weather/edit saves) so that a single user action
            // produces a single +1 — see `ReviewPromptCoordinator.swift`
            // for the full gating policy. Wrapped in `assumeIsolated`
            // because the coordinator is `@MainActor`-isolated and this
            // method itself isn't.
            MainActor.assumeIsolated {
                ReviewPromptCoordinator.recordEntryLogged()
            }
        } catch {
            viewContext.automaticallyMergesChangesFromParent = originalMergesSetting
            migraineLog.error("Failed to save migraine: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Kick off weather fetch on a MainActor-isolated task. The
        // `@MainActor` annotation is load-bearing under Swift 6 strict
        // concurrency: `MigraineEvent` is a non-Sendable NSManagedObject, so
        // it can only be captured into a closure that shares its actor with
        // the call site. Running the whole task on MainActor lets us pass the
        // object reference safely (the NSManagedObjectContext it belongs to
        // is the main-thread `viewContext`, so all access stays on the same
        // thread the object was fetched on — Core Data's actual rule).
        Task { @MainActor [weak self] in
            self?.migraineLog.debug("Starting weather fetch task")
            await self?.fetchWeatherData(for: migraine)
            do {
                self?.migraineLog.debug("Saving weather data for migraine id \(migraine.id?.uuidString ?? "nil", privacy: .public)")
                try self?.viewContext.save()
                self?.migraineLog.debug("Weather data save succeeded")
            } catch {
                self?.migraineLog.error("Failed to save weather data: \(error.localizedDescription, privacy: .public)")
            }
        }

        migraineLog.debug("addMigraine returning")
        return migraine
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
            
            // Coordinates are private user data — keep at default privacy.
            AppLogger.weather.debug("Fetching weather for location: \(latitude), \(longitude)")
            
            // Fetch weather snapshot with timeout
            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
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
    
    /// Helper function to add timeout to async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            let result = try await group.next()!
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

        do {
            try viewContext.save()
            AppLogger.weather.notice("Weather data saved after retry")
        } catch {
            AppLogger.weather.error("Failed to save weather data after retry: \(error.localizedDescription, privacy: .public)")
        }
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
            // Coordinates are private user data — keep at default privacy.
            AppLogger.weather.debug("Fetching weather for custom location: \(latitude), \(longitude)")

            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
            }

            // Update migraine with weather data
            migraine.updateWeatherData(from: snapshot)
            migraine.updateWeatherLocation(latitude: latitude, longitude: longitude)
            weatherFetchStatus = .success

            // Save changes
            try viewContext.save()
            AppLogger.weather.notice("Weather data updated with custom location")

            // Reset status after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle

        } catch {
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
            // Update progress
            await MainActor.run {
                progressCallback(index + 1, total)
            }

            // Fetch weather data
            await fetchWeatherData(for: migraine)

            // Check if successful
            if migraine.hasWeatherData {
                successCount += 1
            } else {
                failedCount += 1
            }

            // Save after each fetch to avoid losing data
            do {
                try viewContext.save()
            } catch {
                AppLogger.weather.error("Failed to save after backfill iteration: \(error.localizedDescription, privacy: .public)")
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
        await MainActor.run {
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

            save()
        }
    }
    
    @MainActor
    func deleteMigraine(_ migraine: MigraineEvent) {
        guard let id = migraine.id else { return }
        
        // Just delete the migraine - no need to handle relationships since we're using strings
        viewContext.delete(migraine)
        
        do {
            try viewContext.save()
            // Record the deletion for syncing
            Task { @MainActor in
                WatchConnectivityManager.shared.recordDeletion(of: id)
            }
            fetchMigraines()  // Refresh the list
        } catch {
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error deleting migraine: \(error.localizedDescription, privacy: .public)")
            viewContext.rollback()
        }
    }
    
    private func save() {
        guard viewContext.hasChanges else { return }
        
        viewContext.perform { [weak self] in
            do {
                try self?.viewContext.save()
                self?.pendingChanges += 1
                if case .enabled = self?.syncStatus {
                    self?.syncStatus = .pendingChanges(self?.pendingChanges ?? 0)
                }
            } catch {
                self?.lastError = .saveFailed(error)
                AppLogger.coreData.error("Error saving context: \(error.localizedDescription, privacy: .public)")
                self?.viewContext.rollback()
            }
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
    /// Dev-only diagnostic dump of the in-memory migraine list. Field values
    /// pass through default privacy so user-entered text is redacted in any
    /// non-DEBUG path that might invoke this.
    func printDebugInfo() {
        AppLogger.coreData.debug("=== Current Migraines (\(self.migraines.count, privacy: .public)) ===")
        for migraine in migraines {
            let triggerNames = migraine.orderedTriggers.map(\.displayName).joined(separator: ", ")
            let medNames = migraine.orderedMedications.map(\.displayName).joined(separator: ", ")
            AppLogger.coreData.debug(
                "id=\(migraine.id?.uuidString ?? "nil", privacy: .public) start=\(migraine.startTime?.description ?? "nil", privacy: .public) pain=\(migraine.painLevel, privacy: .public) loc=\(migraine.location ?? "nil") triggers=[\(triggerNames, privacy: .public)] meds=[\(medNames, privacy: .public)] notes=\(self.getUserNotes(from: migraine) ?? "")"
            )
        }
    }
    #endif
    
    func clearAllData() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "MigraineEvent")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try viewContext.execute(deleteRequest)
            try viewContext.save()
            fetchMigraines()
        } catch {
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error clearing data: \(error.localizedDescription, privacy: .public)")
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
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
        
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
        if case .enabled = syncStatus {
            if case .pendingChanges = syncStatus {
                syncPendingChanges()
            }
        }
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
        case .error:
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
        let cacheKey = "triggers-\(timeFilter)"
        if let cached = chartDataCache[cacheKey] as? [(String, Int)],
           let lastUpdate = lastChartUpdateTime,
           Date().timeIntervalSince(lastUpdate) < chartCacheTimeout {
            return cached
        }

        var triggerCounts: [String: Int] = [:]
        for migraine in filteredMigraines(for: timeFilter) {
            for trigger in migraine.triggers {
                triggerCounts[trigger.displayName, default: 0] += 1
            }
        }

        let result = triggerCounts.sorted { $0.value > $1.value }
        chartDataCache[cacheKey] = result
        lastChartUpdateTime = Date()
        return result
    }

    func getMedicationFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        let cacheKey = "medications-\(timeFilter)"
        if let cached = chartDataCache[cacheKey] as? [(String, Int)],
           let lastUpdate = lastChartUpdateTime,
           Date().timeIntervalSince(lastUpdate) < chartCacheTimeout {
            return cached
        }

        var medicationCounts: [String: Int] = [:]
        for migraine in filteredMigraines(for: timeFilter) {
            for medication in migraine.medications {
                medicationCounts[medication.displayName, default: 0] += 1
            }
        }

        let result = medicationCounts.sorted { $0.value > $1.value }
        chartDataCache[cacheKey] = result
        lastChartUpdateTime = Date()
        return result
    }
    
    // Add safe navigation state management
    func clearNavigationSelections() {
        // This should be called when navigation state needs to be reset
        chartDataCache.removeAll()
        lastChartUpdateTime = nil
    }
    
    // Optimize filtered migraines
    private func filteredMigraines(for timeFrame: TimeFrame) -> [MigraineEvent] {
        let cacheKey = "filtered-\(timeFrame)"
        if let cached = chartDataCache[cacheKey] as? [MigraineEvent],
           let lastUpdate = lastChartUpdateTime,
           Date().timeIntervalSince(lastUpdate) < chartCacheTimeout {
            return cached
        }
        
        let filtered = migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return isDate(startTime, inTimeFrame: timeFrame)
        }
        
        chartDataCache[cacheKey] = filtered
        lastChartUpdateTime = Date()
        return filtered
    }
    
    // Add cache invalidation
    func invalidateCache() {
        chartDataCache.removeAll()
        lastChartUpdateTime = nil
        objectWillChange.send()
    }
    
    private func isDate(_ date: Date, inTimeFrame timeFrame: TimeFrame) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeFrame {
        case .week:
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            return date >= weekStart && date < weekEnd
        
        case .month:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            return date >= monthStart && date < monthEnd
        
        case .year:
            let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart)!
            return date >= yearStart && date < yearEnd
        }
    }
    
    /// Dev-only data dump. Each field passes through default privacy so the
    /// log is automatically scrubbed in release. ID/dates/counts are marked
    /// `.public` because they're not user-identifying.
    func verifyMigraineData(_ migraine: MigraineEvent) {
        let triggers = migraine.orderedTriggers.map(\.displayName).joined(separator: ", ")
        let meds = migraine.orderedMedications.map(\.displayName).joined(separator: ", ")
        AppLogger.coreData.debug(
            "verifyMigraineData id=\(migraine.id?.uuidString ?? "nil", privacy: .public) start=\(migraine.startTime?.description ?? "nil", privacy: .public) pain=\(migraine.painLevel, privacy: .public) loc=\(migraine.location ?? "nil") triggers=[\(triggers, privacy: .public)] meds=[\(meds, privacy: .public)] notes=\(self.getUserNotes(from: migraine) ?? "")"
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
            AppLogger.coreData.debug("Trigger frequency (month): \(self.getTriggerFrequency(for: .month).description, privacy: .public)")
            AppLogger.coreData.debug("Medication frequency (month): \(self.getMedicationFrequency(for: .month).description, privacy: .public)")
        } catch {
            AppLogger.coreData.error("Error verifying test data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func debugPrintAllMigraines() {
        AppLogger.coreData.debug("=== All Migraines (\(self.migraines.count, privacy: .public)) ===")
        for migraine in migraines {
            let triggers = migraine.orderedTriggers.map(\.displayName).joined(separator: ", ")
            let meds = migraine.orderedMedications.map(\.displayName).joined(separator: ", ")
            AppLogger.coreData.debug(
                "id=\(migraine.id?.uuidString ?? "unknown", privacy: .public) date=\(migraine.startTime?.description ?? "unknown", privacy: .public) triggers=[\(triggers, privacy: .public)] meds=[\(meds, privacy: .public)]"
            )
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
    
    @MainActor
    func loadChartData(for timeFilter: TimeFrame) async {
        // Throttle: skip if cached data is still fresh.
        guard lastChartUpdateTime == nil ||
              Date().timeIntervalSince(lastChartUpdateTime!) > chartCacheTimeout else {
            return
        }

        // Surrounding `func` is already `@MainActor`, and every reachable
        // helper here (`filteredMigraines`, `getTriggerFrequency`,
        // `getMedicationFrequency`) only touches in-memory caches and
        // already-fetched `migraines`. The previous `await Task { … }.value`
        // wrapper hopped to a non-isolated executor and back for no benefit
        // — it just added a context switch and risked a Sendable warning on
        // `chartDataCache` mutation. Inline the work.
        let filtered = filteredMigraines(for: timeFilter)
        chartDataCache["filtered-\(timeFilter)"] = filtered
        chartDataCache["triggers-\(timeFilter)"] = getTriggerFrequency(for: timeFilter)
        chartDataCache["medications-\(timeFilter)"] = getMedicationFrequency(for: timeFilter)

        lastChartUpdateTime = Date()
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