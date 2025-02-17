import CoreData
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    @Published private(set) var syncStatus: PersistenceController.SyncStatus = .notConfigured
    @Published private(set) var lastSyncTime: Date?
    private var pendingChanges: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    private let viewContext: NSManagedObjectContext
    private var fetchedResultsController: NSFetchedResultsController<MigraineEvent>?
    
    // Update these constants
    let locations = [
        "Frontal",
        "Whole Head",
        "Left Side",
        "Right Side",
        "Occipital/Back of Head"
    ]

    let triggers = [
        "Stress", "Sleep Changes", "Weather", "Food", 
        "Caffeine", "Alcohol", "Exercise", "Screen Time", 
        "Hormonal", "Other"
    ]
    
    let medications = [
        "Sumatriptan",
        "Rizatriptan",
        "Frovatriptan",
        "Naratriptan",
        "Ubrelvy (Ubrogepant)",
        "Nurtec (Rimegepant)",
        "Trudhesa (Dihydroergotamine)",
        "Reyvow (Lasmiditan)",
        "Elyxyb (Celecoxib)",
        "Tylenol",
        "Advil",
        "Excedrin",
        "Other"
    ]
    
    private var autoSyncTimer: Timer?
    private let autoSyncInterval: TimeInterval = 300 // 5 minutes
    
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
            migraines = fetchedResultsController?.fetchedObjects ?? []
        } catch {
            lastError = .fetchFailed(error)
            print("Error fetching migraines: \(error)")
        }
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
    
    func addMigraine(
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        triggers: [String],
        medications: [String],
        notes: String?
    ) {
        let migraine = MigraineEvent(context: viewContext)
        migraine.id = UUID()
        migraine.startTime = startTime
        migraine.endTime = endTime
        migraine.painLevel = painLevel
        migraine.location = location
        migraine.notes = notes
        
        // Create and associate triggers
        let triggerEntities = triggers.map { triggerName -> TriggerEntity in
            let trigger = TriggerEntity(context: viewContext)
            trigger.id = UUID()
            trigger.name = triggerName
            trigger.migraine = migraine
            return trigger
        }
        migraine.mutableSetValue(forKey: "triggers").addObjects(from: triggerEntities)
        
        // Create and associate medications
        let medicationEntities = medications.map { medicationName -> MedicationEntity in
            let medication = MedicationEntity(context: viewContext)
            medication.id = UUID()
            medication.name = medicationName
            medication.migraine = migraine
            return medication
        }
        migraine.mutableSetValue(forKey: "medications").addObjects(from: medicationEntities)
        
        // Save and verify
        do {
            try viewContext.save()
            print("DEBUG: Successfully saved migraine with:")
            print("- Triggers: \(triggers)")
            print("- Medications: \(medications)")
            
            // Verify the relationships were saved
            if let savedTriggers = migraine.triggers as? Set<TriggerEntity> {
                print("DEBUG: Verified triggers: \(savedTriggers.compactMap { $0.name })")
            }
            if let savedMedications = migraine.medications as? Set<MedicationEntity> {
                print("DEBUG: Verified medications: \(savedMedications.compactMap { $0.name })")
            }
            
            objectWillChange.send()
            fetchMigraines()
        } catch {
            print("ERROR: Failed to save migraine: \(error)")
        }
    }
    
    func updateMigraine(
        _ migraine: MigraineEvent,
        startTime: Date,
        endTime: Date?,
        painLevel: Int,
        location: String,
        triggers: Set<String>,
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
        medications: Set<String>,
        notes: String?
    ) {
        switch validateMigraine(startTime: startTime, endTime: endTime, painLevel: painLevel) {
        case .success:
            // Update basic properties
            migraine.startTime = startTime
            migraine.endTime = endTime
            migraine.painLevel = Int16(painLevel)
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
            
            let userNotes = notes ?? ""
            let tempData = [
                "triggers": Array(triggers),
                "medications": Array(medications)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: tempData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                migraine.notes = userNotes + "\n\nTEMP_DATA:" + jsonString
            }
            
            save()
            
        case .failure(let error):
            lastError = error
            print("Validation error: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func deleteMigraine(_ migraine: MigraineEvent) {
        guard let id = migraine.id else { return }
        
        // First remove any relationships
        if let triggers = migraine.triggers {
            for case let trigger as TriggerEntity in triggers {
                viewContext.delete(trigger)
            }
        }
        
        if let medications = migraine.medications {
            for case let medication as MedicationEntity in medications {
                viewContext.delete(medication)
            }
        }
        
        // Then delete the migraine
        viewContext.delete(migraine)
        
        do {
            try viewContext.save()
            // Record the deletion for syncing
            Task {
                await WatchConnectivityManager.shared.recordDeletion(of: id)
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
            let tempData = MigraineViewModel.extractTempData(from: migraine)
            print("  Triggers: \(tempData.triggers)")
            print("  Medications: \(tempData.medications)")
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
    
    static func extractTempData(from migraine: MigraineEvent) -> (triggers: Set<String>, medications: Set<String>) {
        let triggers = migraine.triggers?.compactMap { $0.name } ?? []
        let medications = migraine.medications?.compactMap { $0.name } ?? []
        return (Set(triggers), Set(medications))
    }

    func getUserNotes(from migraine: MigraineEvent) -> String? {
        guard let notes = migraine.notes else { return nil }
        guard let tempDataRange = notes.range(of: "\n\nTEMP_DATA:") else { return notes }
        return String(notes[..<tempDataRange.lowerBound])
    }

    // Add these computed properties for statistics
    var commonTriggers: [(String, Int)] {
        var triggerCounts: [String: Int] = [:]
        
        for migraine in migraines {
            let tempData = MigraineViewModel.extractTempData(from: migraine)
            for trigger in tempData.triggers {
                triggerCounts[trigger, default: 0] += 1
            }
        }
        
        return triggerCounts
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
    
    var medicationUsage: [(String, Int)] {
        var medicationCounts: [String: Int] = [:]
        
        for migraine in migraines {
            let tempData = MigraineViewModel.extractTempData(from: migraine)
            for medication in tempData.medications {
                medicationCounts[medication, default: 0] += 1
            }
        }
        
        return medicationCounts
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
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
        try await withCheckedThrowingContinuation { continuation in
            do {
                PersistenceController.shared.migrateDataToNewStore { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
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
        // Only sync if there are pending changes and we're not already syncing
        if case .pendingChanges = syncStatus {
            syncPendingChanges()
        }
    }
    
    private func handleSyncStatusChange(_ status: PersistenceController.SyncStatus) {
        switch status {
        case .enabled:
            setupAutoSync()
        case .disabled, .error:
            autoSyncTimer?.invalidate()
            autoSyncTimer = nil
        default:
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
    
    // Update getTriggerFrequency to be more verbose
    func getTriggerFrequency(for timeFrame: TimeFrame = .month) -> [(String, Int)] {
        print("\n=== Getting Trigger Frequency ===")
        print("Total migraines: \(migraines.count)")
        
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch timeFrame {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        }
        
        print("Time frame: \(timeFrame)")
        print("Start date: \(startDate)")
        print("End date: \(now)")
        
        let filteredMigraines = migraines.filter { migraine in
            guard let startTime = migraine.startTime else {
                print("Migraine has no start time")
                return false
            }
            let isInRange = startTime >= startDate && startTime <= now
            print("Migraine date \(startTime) in range: \(isInRange)")
            return isInRange
        }
        
        print("Filtered migraines count: \(filteredMigraines.count)")
        
        var triggerCounts: [String: Int] = [:]
        
        for migraine in filteredMigraines {
            print("\nProcessing migraine: \(migraine.id?.uuidString ?? "unknown")")
            
            if let triggers = migraine.triggers as? Set<TriggerEntity> {
                print("Found \(triggers.count) triggers")
                for trigger in triggers {
                    if let name = trigger.name {
                        triggerCounts[name, default: 0] += 1
                        print("Counted trigger: \(name)")
                    }
                }
            } else {
                print("Failed to get triggers")
            }
        }
        
        let result = triggerCounts.sorted { $0.value > $1.value }
        print("\nFinal trigger counts: \(result)")
        return result
    }
    
    // Similarly update getMedicationFrequency
    func getMedicationFrequency(for timeFrame: TimeFrame = .month) -> [(String, Int)] {
        print("\n=== Getting Medication Frequency ===")
        let calendar = Calendar.current
        let now = Date()
        
        let startDate: Date
        switch timeFrame {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        }
        
        let filteredMigraines = migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return startTime >= startDate && startTime <= now
        }
        
        print("DEBUG: Found \(filteredMigraines.count) migraines in time frame")
        
        var medicationCounts: [String: Int] = [:]
        
        for migraine in filteredMigraines {
            guard let medications = migraine.medications as? Set<MedicationEntity> else {
                print("DEBUG: Failed to get medications for migraine \(migraine.id?.uuidString ?? "unknown")")
                continue
            }
            
            for medication in medications {
                if let name = medication.name {
                    medicationCounts[name, default: 0] += 1
                    print("DEBUG: Counted medication: \(name)")
                }
            }
        }
        
        let result = medicationCounts.sorted { $0.value > $1.value }
        print("DEBUG: Final medication counts: \(result)")
        return result
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
    
    // Add helper method to verify data is being saved correctly
    func verifyMigraineData(_ migraine: MigraineEvent) {
        print("DEBUG: Verifying migraine data:")
        print("- ID: \(migraine.id?.uuidString ?? "unknown")")
        print("- Start Time: \(migraine.startTime?.description ?? "unknown")")
        print("- Triggers: \((migraine.triggers as? Set<TriggerEntity>)?.compactMap { $0.name } ?? [])")
        print("- Medications: \((migraine.medications as? Set<MedicationEntity>)?.compactMap { $0.name } ?? [])")
    }
    
    // Add this debug method
    private func debugPrintAllMigraines() {
        print("\n=== DEBUG: All Migraines ===")
        for migraine in migraines {
            print("\nMigraine ID: \(migraine.id?.uuidString ?? "unknown")")
            print("Date: \(migraine.startTime?.description ?? "unknown")")
            if let triggers = migraine.triggers as? Set<TriggerEntity> {
                print("Triggers: \(triggers.compactMap { $0.name })")
            } else {
                print("No triggers found or wrong type")
            }
            if let medications = migraine.medications as? Set<MedicationEntity> {
                print("Medications: \(medications.compactMap { $0.name })")
            } else {
                print("No medications found or wrong type")
            }
        }
        print("========================\n")
    }
    
    // Add this test method
    func addTestMigraine() {
        print("\n=== Adding Test Migraines ===")
        
        // Clear existing test data
        do {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "MigraineEvent")
            fetchRequest.predicate = NSPredicate(format: "notes CONTAINS[c] %@", "test migraine")
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try viewContext.execute(batchDeleteRequest)
            try viewContext.save()
        } catch {
            print("Error clearing test data: \(error)")
        }
        
        // Add a migraine from today
        let today = Date()
        let migraine1 = MigraineEvent(context: viewContext)
        migraine1.id = UUID()
        migraine1.startTime = today
        migraine1.endTime = today.addingTimeInterval(3600)
        migraine1.painLevel = 5
        migraine1.location = "Frontal"
        migraine1.notes = "Test migraine today"
        
        // Add triggers for first migraine
        let trigger1 = TriggerEntity(context: viewContext)
        trigger1.id = UUID()
        trigger1.name = "Stress"
        trigger1.migraine = migraine1
        migraine1.addToTriggers(trigger1)
        
        let trigger2 = TriggerEntity(context: viewContext)
        trigger2.id = UUID()
        trigger2.name = "Weather"
        trigger2.migraine = migraine1
        migraine1.addToTriggers(trigger2)
        
        // Add medications for first migraine
        let med1 = MedicationEntity(context: viewContext)
        med1.id = UUID()
        med1.name = "Sumatriptan"
        med1.migraine = migraine1
        migraine1.addToMedications(med1)
        
        let med2 = MedicationEntity(context: viewContext)
        med2.id = UUID()
        med2.name = "Tylenol"
        med2.migraine = migraine1
        migraine1.addToMedications(med2)
        
        // Add a migraine from yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let migraine2 = MigraineEvent(context: viewContext)
        migraine2.id = UUID()
        migraine2.startTime = yesterday
        migraine2.endTime = yesterday.addingTimeInterval(3600)
        migraine2.painLevel = 7
        migraine2.location = "Whole Head"
        migraine2.notes = "Test migraine yesterday"
        
        // Add triggers and medications for second migraine
        let trigger3 = TriggerEntity(context: viewContext)
        trigger3.id = UUID()
        trigger3.name = "Sleep Changes"
        trigger3.migraine = migraine2
        migraine2.addToTriggers(trigger3)
        
        let med3 = MedicationEntity(context: viewContext)
        med3.id = UUID()
        med3.name = "Rizatriptan"
        med3.migraine = migraine2
        migraine2.addToMedications(med3)
        
        // Save the context
        do {
            try viewContext.save()
            print("Successfully saved test migraines")
            
            // Force a refresh of the migraines array
            fetchMigraines()
            
            // Verify the data
            verifyAllMigraines()
        } catch {
            print("Error saving test data: \(error)")
            viewContext.rollback()
        }
    }
    
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
                
                if let triggers = migraine.triggers as? Set<TriggerEntity> {
                    print("- Triggers (\(triggers.count)):")
                    for trigger in triggers {
                        print("  • \(trigger.name ?? "unnamed")")
                    }
                }
                
                if let medications = migraine.medications as? Set<MedicationEntity> {
                    print("- Medications (\(medications.count)):")
                    for medication in medications {
                        print("  • \(medication.name ?? "unnamed")")
                    }
                }
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
}

// Add NSFetchedResultsController delegate
extension MigraineViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async { [weak self] in
            self?.migraines = controller.fetchedObjects as? [MigraineEvent] ?? []
        }
    }
} 