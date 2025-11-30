import Foundation
import CoreData
import WatchConnectivity

// Add this if MigraineEvent+Dictionary is in a separate module
// import YourModuleName

enum WatchSyncError: Error {
    case fetchFailed(Error)
    case conversionFailed(String)
    case contextUpdateFailed(Error)
    case messageSendFailed(Error)
    case notReachable
    case invalidData
}

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private let session: WCSession
    
    @Published private(set) var isReachable = false
    @Published private(set) var isCloudKitAvailable = false
    private var syncTimer: Timer?
    
    @Published var lastSyncTime: Date?
    @Published var deletedMigraineIds: Set<UUID> = []
    @Published private(set) var syncStatus: SyncStatus = .notConfigured
    private var lastSyncAttempt: Date?
    private let minSyncInterval: TimeInterval = 5 // Minimum time between syncs
    private var syncRetryCount = 0
    private let maxRetries = 3
    
    override init() {
        self.session = WCSession.default
        super.init()
        
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
    
    private func loadDeletedIds() {
        if let deletedIdsData = UserDefaults.standard.data(forKey: "deletedMigraineIds"),
           let deletedIds = try? JSONDecoder().decode(Set<UUID>.self, from: deletedIdsData) {
            deletedMigraineIds = deletedIds
        }
    }
    
    func checkAndSyncData() async {
        guard session.activationState == .activated else {
            print("Watch connectivity session not activated")
            return
        }
        
        #if os(iOS)
        guard session.isReachable else {
            print("Watch is not reachable")
            return
        }
        
        await sendMigraineData()
        #endif
    }
    
    private func sendMigraineData() async {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        
        do {
            let migraines = try context.fetch(fetchRequest)
            let migraineData = migraines.compactMap { migraine -> [String: Any]? in
                guard let id = migraine.id else { return nil }
                return migraine.toWatchSyncDictionary()
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.sendMessage(
                    ["migraines": migraineData],
                    replyHandler: { _ in
                        continuation.resume()
                    },
                    errorHandler: { error in
                        continuation.resume(throwing: error)
                    }
                )
            }
        } catch {
            print("Error during migraine sync: \(error.localizedDescription)")
        }
    }
    
    private func startSyncTimer() {
        // Cancel existing timer if any
        syncTimer?.invalidate()
        
        // Create new timer on main thread
        DispatchQueue.main.async { [weak self] in
            self?.syncTimer = Timer.scheduledTimer(
                withTimeInterval: 15,
                repeats: true
            ) { [weak self] _ in
                Task { [weak self] in
                    await self?.checkAndSyncData()
                }
            }
        }
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    private func handleSyncError(_ error: Error) {
        let errorMessage: String
        switch error {
        case WatchSyncError.fetchFailed(let underlyingError):
            errorMessage = "Failed to fetch data: \(underlyingError.localizedDescription)"
        case WatchSyncError.conversionFailed(let details):
            errorMessage = "Data conversion failed: \(details)"
        case WatchSyncError.contextUpdateFailed(let underlyingError):
            errorMessage = "Failed to update context: \(underlyingError.localizedDescription)"
        case WatchSyncError.messageSendFailed(let underlyingError):
            errorMessage = "Failed to send message: \(underlyingError.localizedDescription)"
        case WatchSyncError.notReachable:
            errorMessage = "Watch is not reachable"
        case WatchSyncError.invalidData:
            errorMessage = "Invalid data format"
        default:
            errorMessage = "Unknown error: \(error.localizedDescription)"
        }
        
        print("Sync error: \(errorMessage)")
        syncStatus = .error
    }
    
    private func processMigraineData(_ migraineDataArray: [[String: Any]], deletedIds: [String]) {
        // Process deletions first
        for deletedIdString in deletedIds {
            if let deletedId = UUID(uuidString: deletedIdString) {
                deletedMigraineIds.insert(deletedId)
                
                let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
                request.predicate = NSPredicate(format: "id == %@", deletedId as CVarArg)
                
                do {
                    let existingMigraines = try context.fetch(request)
                    for migraine in existingMigraines {
                        context.delete(migraine)
                    }
                } catch {
                    print("Error processing deletion: \(error)")
                }
            }
        }
        
        // Process updates/additions
        for migraineData in migraineDataArray {
            guard let idString = migraineData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  !deletedMigraineIds.contains(id) else { continue }
            
            let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            do {
                let existingMigraines = try context.fetch(request)
                let migraine = existingMigraines.first ?? MigraineEvent(context: context)
                
                // Update basic properties
                migraine.id = id
                migraine.startTime = Date(timeIntervalSince1970: migraineData["startTime"] as? Double ?? Date().timeIntervalSince1970)
                if let endTimeInterval = migraineData["endTime"] as? Double {
                    migraine.endTime = Date(timeIntervalSince1970: endTimeInterval)
                }
                migraine.painLevel = Int16(migraineData["painLevel"] as? Int ?? 5)
                migraine.location = migraineData["location"] as? String
                migraine.notes = migraineData["notes"] as? String
                
                // Create new triggers
                if let triggerNames = migraineData["triggers"] as? [String] {
                    // Remove existing triggers
                    if let existingTriggers = migraine.triggers as? Set<TriggerEntity> {
                        for trigger in existingTriggers {
                            context.delete(trigger)
                        }
                    }
                    
                    // Add new triggers
                    for name in triggerNames {
                        let trigger = TriggerEntity(context: context)
                        trigger.id = UUID()
                        trigger.name = name
                        trigger.migraine = migraine
                    }
                }
                
                // Create new medications
                if let medicationNames = migraineData["medications"] as? [String] {
                    // Remove existing medications
                    if let existingMedications = migraine.medications as? Set<MedicationEntity> {
                        for medication in existingMedications {
                            context.delete(medication)
                        }
                    }
                    
                    // Add new medications
                    for name in medicationNames {
                        let medication = MedicationEntity(context: context)
                        medication.id = UUID()
                        medication.name = name
                        medication.migraine = migraine
                    }
                }
                
                // Update boolean properties
                migraine.hasAura = migraineData["hasAura"] as? Bool ?? false
                migraine.hasPhotophobia = migraineData["hasPhotophobia"] as? Bool ?? false
                migraine.hasPhonophobia = migraineData["hasPhonophobia"] as? Bool ?? false
                migraine.hasNausea = migraineData["hasNausea"] as? Bool ?? false
                migraine.hasVomiting = migraineData["hasVomiting"] as? Bool ?? false
                migraine.hasWakeUpHeadache = migraineData["hasWakeUpHeadache"] as? Bool ?? false
                migraine.hasTinnitus = migraineData["hasTinnitus"] as? Bool ?? false
                migraine.hasVertigo = migraineData["hasVertigo"] as? Bool ?? false
                migraine.missedWork = migraineData["missedWork"] as? Bool ?? false
                migraine.missedSchool = migraineData["missedSchool"] as? Bool ?? false
                migraine.missedEvents = migraineData["missedEvents"] as? Bool ?? false
                
            } catch {
                print("Error processing migraine data: \(error)")
            }
        }
        
        // Save changes
        do {
            try context.save()
            print("Successfully processed \(migraineDataArray.count) migraines")
        } catch {
            print("Error saving context: \(error)")
            context.rollback()
        }
    }
    
    func sendMigraineToiOS(_ migraine: MigraineEvent) async throws {
        guard session.activationState == .activated else {
            syncStatus = .offline
            throw WatchSyncError.notReachable
        }
        
        syncStatus = .syncing
        let migraineData = migraine.toWatchSyncDictionary()
        print("Sending migraine to iOS: \(migraineData)")
        
        do {
            try await withCheckedThrowingContinuation { continuation in
                session.sendMessage(migraineData, replyHandler: { reply in
                    print("Successfully sent migraine to iOS: \(reply)")
                    self.syncStatus = .synced
                    continuation.resume()
                }, errorHandler: { error in
                    print("Failed to send migraine to iOS: \(error)")
                    self.syncStatus = .error
                    continuation.resume(throwing: error)
                })
            }
        } catch {
            syncStatus = .error
            throw error
        }
    }
    
    #if os(iOS)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if message["requestSync"] as? Bool == true {
                // Watch requested sync
                await sendMigraineData()
                replyHandler(["status": "success"])
            } else {
                // Handle migraine data
                do {
                    let context = PersistenceController.shared.container.viewContext
                    let migraine = MigraineEvent(context: context)
                    migraine.updateFromDictionary(message)
                    try context.save()
                    syncStatus = .synced
                    lastSyncTime = Date()
                    replyHandler(["status": "success"])
                } catch {
                    print("Failed to save received migraine: \(error)")
                    syncStatus = .error
                    replyHandler(["status": "error", "message": error.localizedDescription])
                }
            }
        }
    }
    #endif
    
    func manualSync() async {
        guard session.activationState == .activated else {
            syncStatus = .offline
            return
        }
        
        guard !syncStatus == .syncing else {
            return // Already syncing
        }
        
        syncStatus = .syncing
        
        do {
            #if os(iOS)
            // iOS initiates sync to Watch
            guard session.isReachable else {
                syncStatus = .offline
                return
            }
            await sendMigraineData()
            #else
            // Watch requests sync from iOS
            try await requestSyncFromiOS()
            #endif
            
            syncStatus = .synced
            lastSyncTime = Date()
        } catch {
            print("Manual sync failed: \(error)")
            syncStatus = .error
        }
    }
    
    private func requestSyncFromiOS() async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                ["requestSync": true],
                replyHandler: { _ in
                    continuation.resume()
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Session activation failed: \(error.localizedDescription)")
            syncStatus = .error
        } else {
            print("Session activated successfully")
            isReachable = activationState == .activated
            syncStatus = activationState == .activated ? .synced : .offline
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task {
            do {
                let context = PersistenceController.shared.container.viewContext
                let _ = try MigraineEvent.from(dictionary: message, in: context)
                try context.save()
                replyHandler(["status": "success"])
            } catch {
                print("Error processing received migraine: \(error)")
                replyHandler(["status": "error", "message": error.localizedDescription])
            }
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        isReachable = false
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
} 