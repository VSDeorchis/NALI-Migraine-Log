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
    
    private let migraineLog = Logger(subsystem: "com.neuroli.Headway", category: "MigraineVM")
    
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
                // Persist any newly-assigned IDs
                if viewContext.hasChanges {
                    try? viewContext.save()
                }
                migraines = newMigraines
                invalidateCache()
            }
        } catch {
            lastError = .fetchFailed(error)
            #if DEBUG
            print("Error fetching migraines: \(error)")
            #endif
        }
    }
    
    /// Refresh migraines from Core Data (for pull-to-refresh)
    @MainActor
    func refreshMigraines() async {
        // Refresh the context to get latest from persistent store
        viewContext.refreshAllObjects()
        
        // Re-fetch migraines
        fetchMigraines()
        
        #if DEBUG
        print("📱 Migraines refreshed: \(migraines.count) entries")
        #endif
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
            print("Error fetching recent migraines: \(error)")
        }
    }
    
    @MainActor
    @discardableResult
    func addMigraine(
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        triggers: [String],
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
        medications: [String],
        notes: String?
    ) async -> MigraineEvent? {
        NSLog("🟢 [MigraineViewModel] addMigraine called")
        migraineLog.debug("💾 addMigraine called at \(Date(), privacy: .public)")

        // Create and save migraine - must be called from main thread
        NSLog("🟢 [MigraineViewModel] Creating migraine on MainActor")
        
        NSLog("🟢 [MigraineViewModel] Creating MigraineEvent...")
            let migraine = MigraineEvent(context: viewContext)
            migraine.id = UUID()
            migraine.startTime = startTime
            migraine.endTime = endTime
            migraine.painLevel = painLevel
            migraine.location = location
            migraine.notes = notes
            
            // Set boolean properties
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
            
            // Set trigger booleans
            migraine.isTriggerStress = triggers.contains("Stress")
            migraine.isTriggerLackOfSleep = triggers.contains("Lack of Sleep")
            migraine.isTriggerDehydration = triggers.contains("Dehydration")
            migraine.isTriggerWeather = triggers.contains("Weather")
            migraine.isTriggerHormones = triggers.contains("Menstrual")
            migraine.isTriggerAlcohol = triggers.contains("Alcohol")
            migraine.isTriggerCaffeine = triggers.contains("Caffeine")
            migraine.isTriggerFood = triggers.contains("Food")
            migraine.isTriggerExercise = triggers.contains("Exercise")
            migraine.isTriggerScreenTime = triggers.contains("Screen Time")
            migraine.isTriggerOther = triggers.contains("Other")
            
            // Set medication booleans
            migraine.tookIbuprofin = medications.contains("Ibuprofen")
            migraine.tookExcedrin = medications.contains("Excedrin")
            migraine.tookTylenol = medications.contains("Tylenol")
            migraine.tookSumatriptan = medications.contains("Sumatriptan")
            migraine.tookRizatriptan = medications.contains("Rizatriptan")
            migraine.tookNaproxen = medications.contains("Naproxen")
            migraine.tookFrovatriptan = medications.contains("Frovatriptan")
            migraine.tookNaratriptan = medications.contains("Naratriptan")
            migraine.tookNurtec = medications.contains("Nurtec")
            migraine.tookUbrelvy = medications.contains("Ubrelvy")
            migraine.tookReyvow = medications.contains("Reyvow")
            migraine.tookTrudhesa = medications.contains("Trudhesa")
            migraine.tookElyxyb = medications.contains("Elyxyb")
            migraine.tookOther = medications.contains("Other")
            
        // Save immediately - disable automatic merging temporarily to avoid deadlock
        NSLog("🟢 [MigraineViewModel] About to save to Core Data...")
        
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
            NSLog("🟢 [MigraineViewModel] Calling viewContext.save()...")
                try viewContext.save()
            NSLog("🟢 [MigraineViewModel] Core Data save succeeded")
            
            // Re-enable automatic merging
            viewContext.automaticallyMergesChangesFromParent = originalMergesSetting
            
            // Refresh the object to ensure it's not a fault
            viewContext.refresh(migraine, mergeChanges: false)
            NSLog("🟢 [MigraineViewModel] Object refreshed, isFault: \(migraine.isFault)")
            
            NSLog("🟢 [MigraineViewModel] Inserting into migraines array...")
                migraines.insert(migraine, at: 0)
            NSLog("🟢 [MigraineViewModel] Insert completed. Array now has %d items", migraines.count)
            
            migraineLog.debug("Initial save succeeded – id: \(migraine.id?.uuidString ?? "nil", privacy: .public)")
            NSLog("✅ Migraine saved (initial data) – permanent ID assigned")
            } catch {
            // Re-enable automatic merging even on error
            viewContext.automaticallyMergesChangesFromParent = originalMergesSetting
            NSLog("❌ Failed to save migraine: %@", error.localizedDescription)
                return nil
            }
        
        NSLog("🟢 [MigraineViewModel] Save succeeded, migraine ID: %@", migraine.id?.uuidString ?? "nil")

        // Kick off weather fetch on a background task; don't block caller
        NSLog("🟢 [MigraineViewModel] Starting weather fetch task...")
        Task { [weak self] in
            NSLog("🌤️ [Weather Task] Weather fetch task started")
            self?.migraineLog.debug("Starting weather fetch task")
            await self?.fetchWeatherData(for: migraine)
            NSLog("🌤️ [Weather Task] fetchWeatherData completed")
            await MainActor.run {
                do {
                    NSLog("🌤️ [Weather Task] Saving weather data to Core Data...")
                    self?.migraineLog.debug("Saving weather data for migraine id \(migraine.id?.uuidString ?? "nil", privacy: .public)")
                    try self?.viewContext.save()
                    NSLog("🌤️ [Weather Task] Weather data saved successfully")
                    self?.migraineLog.debug("Weather data save succeeded")
                } catch {
                    NSLog("🔴 [Weather Task] Failed to save weather data: %@", error.localizedDescription)
                    self?.migraineLog.error("Failed to save weather data: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        NSLog("🟢 [MigraineViewModel] addMigraine returning migraine")
        migraineLog.debug("addMigraine returning")
        return migraine
    }
    
    // MARK: - Weather Integration
    
    /// Fetch weather data for a migraine event
    private func fetchWeatherData(for migraine: MigraineEvent) async {
        migraineLog.debug("🌤️ fetchWeatherData started for migraine id \(migraine.id?.uuidString ?? "nil", privacy: .public)")
        guard let startTime = migraine.startTime else {
            migraineLog.error("No start time; aborting weather fetch")
            await MainActor.run {
                weatherFetchStatus = .failed("No start time available")
            }
            return
        }
        
        await MainActor.run {
            weatherFetchStatus = .fetching
        }
        
        do {
            // Try to get current location
            migraineLog.debug("Requesting current location")
            let location = try await LocationManager.shared.getCurrentLocation()
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            
            print("📍 Fetching weather for location: \(latitude), \(longitude)")
            
            // Fetch weather snapshot with timeout
            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
            }
            migraineLog.debug("Weather snapshot received; updating migraine")
            
            // Update migraine with weather data
            await MainActor.run {
                migraine.updateWeatherData(from: snapshot)
                migraine.updateWeatherLocation(latitude: latitude, longitude: longitude)
                weatherFetchStatus = .success
                print("🌤️ Weather data added: \(snapshot.weatherCondition), \(Int(snapshot.temperature))°F, Pressure change: \(String(format: "%.2f", snapshot.pressureChange24h * 0.75006)) mmHg")
            }
            
            // Reset status after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                weatherFetchStatus = .idle
            }
            
        } catch LocationError.unauthorized {
            print("⚠️ Location access not authorized - weather data not available")
            await MainActor.run {
                weatherFetchStatus = .locationDenied
            }
            // Reset after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                weatherFetchStatus = .idle
            }
        } catch is TimeoutError {
            print("⚠️ Weather fetch timed out - API may be slow or unavailable")
            await MainActor.run {
                weatherFetchStatus = .failed("Weather service timed out")
            }
            // Reset after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                weatherFetchStatus = .idle
            }
        } catch {
            migraineLog.error("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                weatherFetchStatus = .failed(error.localizedDescription)
            }
            // Reset after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                weatherFetchStatus = .idle
            }
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
            print("⚠️ Migraine already has weather data")
            return
        }
        
        print("🔄 Retrying weather fetch for migraine...")
        await fetchWeatherData(for: migraine)
        
        // Save after fetching
        do {
            try viewContext.save()
            print("✅ Weather data saved after retry")
        } catch {
            print("❌ Failed to save weather data after retry: \(error.localizedDescription)")
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
            print("❌ No start time available")
            weatherFetchStatus = .failed("No start time available")
            return
        }
        
        weatherFetchStatus = .fetching
        
        do {
            print("📍 Fetching weather for custom location: \(latitude), \(longitude)")
            
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
            print("✅ Weather data updated with custom location")
            
            // Reset status after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
            
        } catch {
            print("❌ Failed to fetch weather for custom location: \(error.localizedDescription)")
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
            print("ℹ️ No migraines need weather data")
            return (0, 0)
        }
        
        print("🌤️ Starting bulk weather fetch for \(total) migraines")
        
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
                print("❌ Failed to save after backfill: \(error.localizedDescription)")
            }
            
            // Small delay to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("✅ Bulk weather fetch complete: \(successCount) success, \(failedCount) failed")
        return (successCount, failedCount)
    }
    
    @MainActor
    func updateMigraine(
        _ migraine: MigraineEvent,
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        isTriggerStress: Bool,
        isTriggerLackOfSleep: Bool,
        isTriggerDehydration: Bool,
        isTriggerWeather: Bool,
        isTriggerHormones: Bool,
        isTriggerAlcohol: Bool,
        isTriggerCaffeine: Bool,
        isTriggerFood: Bool,
        isTriggerExercise: Bool,
        isTriggerScreenTime: Bool,
        isTriggerOther: Bool,
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
        tookIbuprofin: Bool,
        tookExcedrin: Bool,
        tookTylenol: Bool,
        tookSumatriptan: Bool,
        tookRizatriptan: Bool,
        tookNaproxen: Bool,
        tookFrovatriptan: Bool,
        tookNaratriptan: Bool,
        tookNurtec: Bool,
        tookUbrelvy: Bool,
        tookReyvow: Bool,
        tookTrudhesa: Bool,
        tookElyxyb: Bool,
        tookOther: Bool,
        tookEletriptan: Bool,
        notes: String
    ) async {
        await MainActor.run {
            migraine.startTime = startTime
            migraine.endTime = endTime
            migraine.painLevel = painLevel
            migraine.location = location
            migraine.notes = notes
            
            // Set trigger booleans
            migraine.isTriggerStress = isTriggerStress
            migraine.isTriggerLackOfSleep = isTriggerLackOfSleep
            migraine.isTriggerDehydration = isTriggerDehydration
            migraine.isTriggerWeather = isTriggerWeather
            migraine.isTriggerHormones = isTriggerHormones
            migraine.isTriggerAlcohol = isTriggerAlcohol
            migraine.isTriggerCaffeine = isTriggerCaffeine
            migraine.isTriggerFood = isTriggerFood
            migraine.isTriggerExercise = isTriggerExercise
            migraine.isTriggerScreenTime = isTriggerScreenTime
            migraine.isTriggerOther = isTriggerOther
            
            // Set medication booleans
            migraine.tookIbuprofin = tookIbuprofin
            migraine.tookExcedrin = tookExcedrin
            migraine.tookTylenol = tookTylenol
            migraine.tookSumatriptan = tookSumatriptan
            migraine.tookRizatriptan = tookRizatriptan
            migraine.tookNaproxen = tookNaproxen
            migraine.tookFrovatriptan = tookFrovatriptan
            migraine.tookNaratriptan = tookNaratriptan
            migraine.tookNurtec = tookNurtec
            migraine.tookUbrelvy = tookUbrelvy
            migraine.tookReyvow = tookReyvow
            migraine.tookTrudhesa = tookTrudhesa
            migraine.tookElyxyb = tookElyxyb
            migraine.tookOther = tookOther
            migraine.tookEletriptan = tookEletriptan
            
            // Set other booleans
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
            print("Error deleting migraine: \(error)")
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
                print("Error saving context: \(error)")
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
    func printDebugInfo() {
        print("Current Migraines:")
        for migraine in migraines {
            print("- ID: \(migraine.id?.uuidString ?? "nil")")
            print("  Start Time: \(migraine.startTime?.description ?? "nil")")
            print("  Pain Level: \(migraine.painLevel)")
            print("  Location: \(migraine.location ?? "nil")")
            
            print("  Triggers:")
            if migraine.isTriggerStress { print("    - Stress") }
            if migraine.isTriggerLackOfSleep { print("    - Lack of Sleep") }
            if migraine.isTriggerDehydration { print("    - Dehydration") }
            if migraine.isTriggerWeather { print("    - Weather") }
            if migraine.isTriggerHormones { print("    - Hormones") }
            if migraine.isTriggerAlcohol { print("    - Alcohol") }
            if migraine.isTriggerCaffeine { print("    - Caffeine") }
            if migraine.isTriggerFood { print("    - Food") }
            if migraine.isTriggerExercise { print("    - Exercise") }
            if migraine.isTriggerScreenTime { print("    - Screen Time") }
            if migraine.isTriggerOther { print("    - Other") }
            
            print("  Medications:")
            if migraine.tookIbuprofin { print("    - Ibuprofen") }
            if migraine.tookExcedrin { print("    - Excedrin") }
            if migraine.tookTylenol { print("    - Tylenol") }
            if migraine.tookSumatriptan { print("    - Sumatriptan") }
            if migraine.tookRizatriptan { print("    - Rizatriptan") }
            if migraine.tookNaproxen { print("    - Naproxen") }
            if migraine.tookFrovatriptan { print("    - Frovatriptan") }
            if migraine.tookNaratriptan { print("    - Naratriptan") }
            if migraine.tookNurtec { print("    - Nurtec") }
            if migraine.tookUbrelvy { print("    - Ubrelvy") }
            if migraine.tookReyvow { print("    - Reyvow") }
            if migraine.tookTrudhesa { print("    - Trudhesa") }
            if migraine.tookElyxyb { print("    - Elyxyb") }
            if migraine.tookOther { print("    - Other") }
            
            print("  User Notes: \(getUserNotes(from: migraine) ?? "")")
            print("---")
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
            print("Error clearing data: \(error)")
        }
    }

    func getUserNotes(from migraine: MigraineEvent) -> String? {
        return migraine.notes
    }

    // Update to work with booleans
    var commonTriggers: [(String, Int)] {
        var triggerCounts: [String: Int] = [:]
        
        for migraine in migraines {
            if migraine.isTriggerStress { triggerCounts["Stress", default: 0] += 1 }
            if migraine.isTriggerLackOfSleep { triggerCounts["Lack of Sleep", default: 0] += 1 }
            if migraine.isTriggerDehydration { triggerCounts["Dehydration", default: 0] += 1 }
            if migraine.isTriggerWeather { triggerCounts["Weather", default: 0] += 1 }
            if migraine.isTriggerHormones { triggerCounts["Menstrual", default: 0] += 1 }
            if migraine.isTriggerAlcohol { triggerCounts["Alcohol", default: 0] += 1 }
            if migraine.isTriggerCaffeine { triggerCounts["Caffeine", default: 0] += 1 }
            if migraine.isTriggerFood { triggerCounts["Food", default: 0] += 1 }
            if migraine.isTriggerExercise { triggerCounts["Exercise", default: 0] += 1 }
            if migraine.isTriggerScreenTime { triggerCounts["Screen Time", default: 0] += 1 }
            if migraine.isTriggerOther { triggerCounts["Other", default: 0] += 1 }
        }
        
        return triggerCounts.sorted { $0.value > $1.value }
    }
    
    var medicationUsage: [(String, Int)] {
        var medicationCounts: [String: Int] = [:]
        
        for migraine in migraines {
            if migraine.tookIbuprofin { medicationCounts["Ibuprofen", default: 0] += 1 }
            if migraine.tookExcedrin { medicationCounts["Excedrin", default: 0] += 1 }
            if migraine.tookTylenol { medicationCounts["Tylenol", default: 0] += 1 }
            if migraine.tookSumatriptan { medicationCounts["Sumatriptan", default: 0] += 1 }
            if migraine.tookRizatriptan { medicationCounts["Rizatriptan", default: 0] += 1 }
            if migraine.tookNaproxen { medicationCounts["Naproxen", default: 0] += 1 }
            if migraine.tookFrovatriptan { medicationCounts["Frovatriptan", default: 0] += 1 }
            if migraine.tookNaratriptan { medicationCounts["Naratriptan", default: 0] += 1 }
            if migraine.tookNurtec { medicationCounts["Nurtec", default: 0] += 1 }
            if migraine.tookUbrelvy { medicationCounts["Ubrelvy", default: 0] += 1 }
            if migraine.tookReyvow { medicationCounts["Reyvow", default: 0] += 1 }
            if migraine.tookTrudhesa { medicationCounts["Trudhesa", default: 0] += 1 }
            if migraine.tookElyxyb { medicationCounts["Elyxyb", default: 0] += 1 }
            if migraine.tookOther { medicationCounts["Other", default: 0] += 1 }
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
            // Handle error appropriately
            print("Migration error: \(error.localizedDescription)")
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
            print("CloudKit sync is disabled - using local storage only")
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
            
            // Simulate sync progress (replace with actual sync progress monitoring)
            var progress = 0.0
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                progress += 0.1
                if progress >= 1.0 {
                    timer.invalidate()
                    DispatchQueue.main.async {
                        self.syncStatus = .enabled
                        self.lastSyncTime = Date()
                        self.pendingChanges = 0
                    }
                } else {
                    DispatchQueue.main.async {
                        self.syncStatus = .syncing(progress)
                    }
                }
            }
        } catch {
            syncStatus = .error("Sync failed: \(error.localizedDescription)")
            // Retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                self?.checkAndSync()
            }
        }
    }
    
    // Optimize trigger frequency calculation
    func getTriggerFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        let cacheKey = "triggers-\(timeFilter)"
        if let cached = chartDataCache[cacheKey] as? [(String, Int)],
           let lastUpdate = lastChartUpdateTime,
           Date().timeIntervalSince(lastUpdate) < chartCacheTimeout {
            return cached
        }
        
        var triggerCounts: [String: Int] = [:]
        let filtered = filteredMigraines(for: timeFilter)
        
        for migraine in filtered {
            for trigger in migraine.selectedTriggerNames {
                triggerCounts[trigger, default: 0] += 1
            }
        }
        
        let result = triggerCounts.sorted { $0.value > $1.value }
        chartDataCache[cacheKey] = result
        lastChartUpdateTime = Date()
        return result
    }
    
    // Optimize medication frequency calculation
    func getMedicationFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        let cacheKey = "medications-\(timeFilter)"
        if let cached = chartDataCache[cacheKey] as? [(String, Int)],
           let lastUpdate = lastChartUpdateTime,
           Date().timeIntervalSince(lastUpdate) < chartCacheTimeout {
            return cached
        }
        
        var medicationCounts: [String: Int] = [:]
        let filtered = filteredMigraines(for: timeFilter)
        
        for migraine in filtered {
            for medication in migraine.selectedMedicationNames {
                medicationCounts[medication, default: 0] += 1
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
    
    // Update verifyMigraineData method
    func verifyMigraineData(_ migraine: MigraineEvent) {
        print("DEBUG: Verifying migraine data:")
        print("- ID: \(migraine.id?.uuidString ?? "nil")")
        print("  Start Time: \(migraine.startTime?.description ?? "nil")")
        print("  Pain Level: \(migraine.painLevel)")
        print("  Location: \(migraine.location ?? "nil")")
        print("  Triggers: \(migraine.selectedTriggerNames)")
        print("  Medications: \(migraine.selectedMedicationNames)")
        print("  User Notes: \(getUserNotes(from: migraine) ?? "")")
        print("---")
    }
    
    // Update verifyAllMigraines method
    private func verifyAllMigraines() {
        print("\n=== Verifying All Migraines ===")
        let fetchRequest: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "notes CONTAINS[c] %@", "test migraine")
        
        do {
            let testMigraines = try viewContext.fetch(fetchRequest)
            print("Found \(testMigraines.count) test migraines")
            
            for migraine in testMigraines {
                print("\nMigraine Details:")
                print("- ID: \(migraine.id?.uuidString ?? "unknown")")
                print("- Start Time: \(migraine.startTime?.formatted() ?? "none")")
                print("- Location: \(migraine.location ?? "none")")
                print("- Pain Level: \(migraine.painLevel)")
                print("- Triggers: \(migraine.selectedTriggerNames)")
                print("- Medications: \(migraine.selectedMedicationNames)")
            }
            
            // Test the frequency methods
            let triggers = getTriggerFrequency(for: .month)
            print("\nTrigger frequency (month): \(triggers)")
            
            let medications = getMedicationFrequency(for: .month)
            print("Medication frequency (month): \(medications)")
        } catch {
            print("Error verifying test data: \(error)")
        }
    }
    
    // Update debugPrintAllMigraines method
    private func debugPrintAllMigraines() {
        print("\n=== DEBUG: All Migraines ===")
        for migraine in migraines {
            print("\nMigraine ID: \(migraine.id?.uuidString ?? "unknown")")
            print("Date: \(migraine.startTime?.description ?? "unknown")")
            print("Triggers: \(migraine.selectedTriggerNames)")
            print("Medications: \(migraine.selectedMedicationNames)")
        }
        print("========================\n")
    }
    
    // Update addTestMigraine method
    func createTestData() {
        let today = Date()
        
        // Create first migraine
        let migraine1 = MigraineEvent(context: viewContext)
        migraine1.id = UUID()
        migraine1.startTime = today
        migraine1.endTime = today.addingTimeInterval(7200)
        migraine1.painLevel = 5
        migraine1.location = "Frontal"
        migraine1.notes = "Test migraine today"
        
        // Instead, set boolean properties directly
        migraine1.isTriggerStress = true
        migraine1.isTriggerLackOfSleep = true
        migraine1.tookSumatriptan = true
        
        do {
            try viewContext.save()
            print("Successfully saved test migraines")
            fetchMigraines()
            verifyAllMigraines()
        } catch {
            print("Error saving test data: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }
    
    // Update helper methods to work with booleans
    func hasTrigger(_ name: String, in migraine: MigraineEvent) -> Bool {
        switch name {
        case "Stress": return migraine.isTriggerStress
        case "Lack of Sleep": return migraine.isTriggerLackOfSleep
        case "Dehydration": return migraine.isTriggerDehydration
        case "Weather": return migraine.isTriggerWeather
        case "Menstrual": return migraine.isTriggerHormones
        case "Alcohol": return migraine.isTriggerAlcohol
        case "Caffeine": return migraine.isTriggerCaffeine
        case "Food": return migraine.isTriggerFood
        case "Exercise": return migraine.isTriggerExercise
        case "Screen Time": return migraine.isTriggerScreenTime
        case "Other": return migraine.isTriggerOther
        default: return false
        }
    }
    
    func hasMedication(_ name: String, in migraine: MigraineEvent) -> Bool {
        switch name {
        case "Ibuprofen": return migraine.tookIbuprofin
        case "Excedrin": return migraine.tookExcedrin
        case "Tylenol": return migraine.tookTylenol
        case "Sumatriptan": return migraine.tookSumatriptan
        case "Rizatriptan": return migraine.tookRizatriptan
        case "Naproxen": return migraine.tookNaproxen
        case "Frovatriptan": return migraine.tookFrovatriptan
        case "Naratriptan": return migraine.tookNaratriptan
        case "Nurtec": return migraine.tookNurtec
        case "Ubrelvy": return migraine.tookUbrelvy
        case "Reyvow": return migraine.tookReyvow
        case "Trudhesa": return migraine.tookTrudhesa
        case "Elyxyb": return migraine.tookElyxyb
        case "Other": return migraine.tookOther
        default: return false
        }
    }
    
    @MainActor
    func loadChartData(for timeFilter: TimeFrame) async {
        // Prevent multiple simultaneous loads
        guard lastChartUpdateTime == nil || 
              Date().timeIntervalSince(lastChartUpdateTime!) > chartCacheTimeout else {
            return
        }
        
        // Load data in background
        await Task {
            // Pre-calculate all chart data
            let filtered = filteredMigraines(for: timeFilter)
            
            // Cache the filtered data
            chartDataCache["filtered-\(timeFilter)"] = filtered
            
            // Pre-calculate trigger frequency
            let triggerData = getTriggerFrequency(for: timeFilter)
            chartDataCache["triggers-\(timeFilter)"] = triggerData
            
            // Pre-calculate medication frequency
            let medicationData = getMedicationFrequency(for: timeFilter)
            chartDataCache["medications-\(timeFilter)"] = medicationData
            
            lastChartUpdateTime = Date()
            objectWillChange.send()
        }.value
    }
    
    // Update the createMigraine method to work with booleans directly
    func createMigraine(startTime: Date, endTime: Date?, painLevel: Int16, location: String, triggers: [String], medications: [String], hasAura: Bool, hasPhotophobia: Bool, hasPhonophobia: Bool, hasNausea: Bool, hasVomiting: Bool, hasWakeUpHeadache: Bool, hasTinnitus: Bool, hasVertigo: Bool, missedWork: Bool, missedSchool: Bool, missedEvents: Bool, notes: String?) {
        let migraine = MigraineEvent(context: viewContext)
        migraine.id = UUID()
        migraine.startTime = startTime
        migraine.endTime = endTime
        migraine.painLevel = painLevel
        migraine.location = location
        migraine.notes = notes
        
        // Set symptom booleans
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
        
        // Set trigger booleans directly
        migraine.isTriggerStress = triggers.contains("Stress")
        migraine.isTriggerLackOfSleep = triggers.contains("Lack of Sleep")
        migraine.isTriggerDehydration = triggers.contains("Dehydration")
        migraine.isTriggerWeather = triggers.contains("Weather")
        migraine.isTriggerHormones = triggers.contains("Menstrual")
        migraine.isTriggerAlcohol = triggers.contains("Alcohol")
        migraine.isTriggerCaffeine = triggers.contains("Caffeine")
        migraine.isTriggerFood = triggers.contains("Food")
        migraine.isTriggerExercise = triggers.contains("Exercise")
        migraine.isTriggerScreenTime = triggers.contains("Screen Time")
        migraine.isTriggerOther = triggers.contains("Other")
        
        // Set medication booleans directly
        migraine.tookIbuprofin = medications.contains("Ibuprofen")
        migraine.tookExcedrin = medications.contains("Excedrin")
        migraine.tookTylenol = medications.contains("Tylenol")
        migraine.tookSumatriptan = medications.contains("Sumatriptan")
        migraine.tookRizatriptan = medications.contains("Rizatriptan")
        migraine.tookNaproxen = medications.contains("Naproxen")
        migraine.tookFrovatriptan = medications.contains("Frovatriptan")
        migraine.tookNaratriptan = medications.contains("Naratriptan")
        migraine.tookNurtec = medications.contains("Nurtec")
        migraine.tookUbrelvy = medications.contains("Ubrelvy")
        migraine.tookReyvow = medications.contains("Reyvow")
        migraine.tookTrudhesa = medications.contains("Trudhesa")
        migraine.tookElyxyb = medications.contains("Elyxyb")
        migraine.tookOther = medications.contains("Other")
        
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            lastError = .saveFailed(error)
            print("Error creating migraine: \(error.localizedDescription)")
        }
    }
}

// Add NSFetchedResultsController delegate
extension MigraineViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async { [weak self] in
            self?.migraines = controller.fetchedObjects as? [MigraineEvent] ?? []
        }
    }
} 