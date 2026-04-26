#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import CoreData
import SwiftUI

/// Bridge between the iOS and watchOS apps via `WCSession`.
///
/// **Concurrency model (Swift 6-clean):**
/// The class is `@MainActor` so every read/write of `@Published` state and
/// every Core Data operation against `viewContext` runs on the main thread.
/// All Apple framework callbacks (`WCSessionDelegate`, `Timer`,
/// `WCSession.sendMessage` errorHandlers) are `nonisolated` and **must** hop
/// to MainActor before touching `self`. This satisfies the Swift 6 strict
/// concurrency model (no actor crossing without an explicit `await`) and
/// also prevents the very-real data race where the previous version dispatched
/// `sendMigraineData()` (a MainActor method that fetches via `viewContext`,
/// itself main-thread-only) onto a background `DispatchQueue`.
@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private let session: WCSession
    private let context: NSManagedObjectContext
    
    @Published var isPaired = false
    @Published var isReachable = false
    @Published var lastSyncTime: Date?
    
    // Synced risk score from iPhone (used by watchOS)
    @Published var syncedRiskPercentage: Int?
    @Published var syncedRiskLevel: String?
    @Published var syncedRiskFactors: [[String: Any]]?
    @Published var syncedRiskRecommendations: [String]?
    @Published var syncedRiskTimestamp: Date?
    
    private var deletedMigraineIds: Set<UUID> = []
    private let deletedIdsKey = "com.neuroli.deletedMigraineIds"
    
    init(session: WCSession = .default) {
        self.session = session
        self.context = PersistenceController.shared.container.viewContext
        super.init()
        
        if WCSession.isSupported() {
            AppLogger.watch.debug("WCSession is supported")
            session.delegate = self
            session.activate()
            
            #if os(iOS)
            // Schedule more frequent syncs for Watch connectivity. The Timer
            // callback is non-isolated, so we must hop back to MainActor
            // before touching `self` (Swift 6 enforces this).
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkAndSyncData()
                }
            }
            #endif
        }
        
        // Load deleted IDs from UserDefaults
        if let deletedIdsData = UserDefaults.standard.data(forKey: deletedIdsKey),
           let deletedIds = try? JSONDecoder().decode(Set<UUID>.self, from: deletedIdsData) {
            deletedMigraineIds = deletedIds
        }
    }
    
    func checkAndSyncData() {
        #if os(iOS)
        guard session.activationState == .activated else {
            AppLogger.watch.debug("Session not activated")
            return
        }
        
        // Previously dispatched onto a background `syncQueue`, but
        // `sendMigraineData()` reads `viewContext` (main-thread-only) and
        // mutates `@Published` state. Running it on a background queue was
        // a latent thread-safety bug and is forbidden under Swift 6. Run
        // inline; we're already on the MainActor.
        sendMigraineData()
        #endif
    }
    
    func recordDeletion(of migraineId: UUID) {
        deletedMigraineIds.insert(migraineId)
        saveDeletedIds()
        checkAndSyncData()  // Trigger sync after deletion
    }
    
    private func saveDeletedIds() {
        if let encodedData = try? JSONEncoder().encode(deletedMigraineIds) {
            UserDefaults.standard.set(encodedData, forKey: deletedIdsKey)
        }
    }
    
    func sendMigraineData() {
        do {
            let migraines = try context.fetch(NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent"))
            // Drop entries without an `id` — they can't be reconciled on the
            // other side. We don't need the unwrapped value beyond the guard,
            // so check existence with a boolean rather than binding.
            let migraineData = migraines.compactMap { migraine -> [String: Any]? in
                guard migraine.id != nil else { return nil }
                return migraine.toWatchSyncDictionary()
            }
            
            var applicationContext: [String: Any] = [
                "migraineData": migraineData,
                "deletedIds": Array(deletedMigraineIds.map { $0.uuidString }),
                "syncTime": Date().timeIntervalSince1970
            ]
            
            // Include pending risk data if available
            if let pendingRisk = UserDefaults.standard.dictionary(forKey: "pendingRiskPayload") {
                applicationContext["riskUpdate"] = pendingRisk
            }
            
            try session.updateApplicationContext(applicationContext)
            
            // Already on MainActor — no `DispatchQueue.main.async` hop needed.
            lastSyncTime = Date()
            let count = migraineData.count
            let deletes = deletedMigraineIds.count
            AppLogger.watch.info("Successfully synced \(count, privacy: .public) migraines and \(deletes, privacy: .public) deletions")
            
        } catch {
            AppLogger.watch.error("Error syncing data: \(error.localizedDescription, privacy: .public)")
            
            // If updating application context fails, try sending as a message
            if session.isReachable {
                session.sendMessage(["requestSync": true], replyHandler: nil) { error in
                    AppLogger.watch.error("Error sending sync request: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    #if os(iOS)
    /// Send the computed risk score to the Watch so both platforms show the same value.
    func sendRiskScore(_ riskScore: MigraineRiskScore) {
        guard session.activationState == .activated else { return }
        
        let factorsData: [[String: Any]] = riskScore.topFactors.prefix(3).map { factor in
            [
                "name": factor.name,
                "contribution": factor.contribution,
                "icon": factor.icon,
                "detail": factor.detail
            ]
        }
        
        let riskPayload: [String: Any] = [
            "riskPercentage": riskScore.riskPercentage,
            "riskLevel": riskScore.riskLevel.rawValue,
            "factors": factorsData,
            "recommendations": Array(riskScore.recommendations.prefix(3)),
            "confidence": riskScore.confidence,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Send as a message for immediate delivery if reachable
        if session.isReachable {
            session.sendMessage(["riskUpdate": riskPayload], replyHandler: nil) { error in
                AppLogger.watch.error("Error sending risk to Watch: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // Also include in the next application context update so the Watch gets it eventually
        UserDefaults.standard.set(riskPayload, forKey: "pendingRiskPayload")
    }
    #endif
    
    #if os(watchOS)
    /// Request full sync from the paired iPhone
    func requestFullSync() {
        guard session.isReachable else { return }
        session.sendMessage(["requestSync": true], replyHandler: nil) { error in
            AppLogger.watch.error("Error requesting sync: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Process incoming risk score data from iPhone. Already on MainActor —
    /// the caller must guarantee that.
    private func processRiskData(_ riskPayload: [String: Any]) {
        syncedRiskPercentage = riskPayload["riskPercentage"] as? Int
        syncedRiskLevel = riskPayload["riskLevel"] as? String
        syncedRiskFactors = riskPayload["factors"] as? [[String: Any]]
        syncedRiskRecommendations = riskPayload["recommendations"] as? [String]
        if let timestamp = riskPayload["timestamp"] as? TimeInterval {
            syncedRiskTimestamp = Date(timeIntervalSince1970: timestamp)
        }
    }
    #endif
    
    // Handle incoming sync requests. Already on MainActor.
    func handleSyncRequest() {
        sendMigraineData()
    }
    
    private func processMigraineData(_ migraineDataArray: [[String: Any]], deletedIds: [String]) {
        let context = PersistenceController.shared.container.viewContext
        
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
                    AppLogger.watch.error("Error processing deletion: \(error.localizedDescription, privacy: .public)")
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
                let migraine: MigraineEvent
                let existingMigraines = try context.fetch(request)
                
                if let existingMigraine = existingMigraines.first {
                    migraine = existingMigraine
                } else {
                    migraine = MigraineEvent(context: context)
                    migraine.id = id
                }
                
                // Update basic properties
                if let startTimeDouble = migraineData["startTime"] as? TimeInterval {
                    migraine.startTime = Date(timeIntervalSince1970: startTimeDouble)
                }
                if let endTimeDouble = migraineData["endTime"] as? TimeInterval {
                    migraine.endTime = Date(timeIntervalSince1970: endTimeDouble)
                }
                migraine.painLevel = migraineData["painLevel"] as? Int16 ?? 0
                migraine.location = migraineData["location"] as? String
                migraine.notes = migraineData["notes"] as? String
                
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
                AppLogger.watch.error("Error processing migraine data: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // Save changes
        do {
            try context.save()
            AppLogger.watch.info("Successfully processed \(migraineDataArray.count, privacy: .public) migraines")
        } catch {
            AppLogger.watch.error("Error saving context: \(error.localizedDescription, privacy: .public)")
            context.rollback()
        }
    }
    
    // Add debug logging to track data flow. Note: the migraine dictionary
    // contains user-entered notes/locations, so it is NEVER logged in cleartext;
    // only counts and reachability flags are marked `.public`.
    func sendMigraineData(_ migraine: MigraineEvent) {
        AppLogger.watch.debug("Attempting to send migraine data to Watch")
        guard WCSession.default.isReachable else {
            AppLogger.watch.debug("Watch is not reachable")
            return
        }
        
        let migraineData = migraine.toWatchSyncDictionary()
        AppLogger.watch.debug("Converted migraine to dictionary (\(migraineData.count, privacy: .public) keys)")
        
        WCSession.default.sendMessage(migraineData, replyHandler: { _ in
            AppLogger.watch.info("Migraine data sent successfully")
        }, errorHandler: { error in
            AppLogger.watch.error("Error sending migraine data: \(error.localizedDescription, privacy: .public)")
        })
    }
}

// MARK: - WCSessionDelegate
//
// Every method here is called by the WatchConnectivity framework on a
// background queue. Marking the methods `nonisolated` makes the conformance
// legal under Swift 6 strict-concurrency (no implicit MainActor crossing),
// and we then explicitly hop to `@MainActor` inside each method before
// touching any `self` state. Values captured into the `Task` (session flags,
// payload dictionaries, primitives) are all Sendable.
extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // Read sendable session state up-front so we don't reach back into
        // `session` from inside the MainActor task (it isn't Sendable).
        let isPaired: Bool
        let isReachable: Bool
        #if os(iOS)
        isPaired = session.isPaired
        isReachable = session.isReachable
        #else
        isPaired = false
        isReachable = session.isReachable
        #endif
        let activationError = error

        Task { @MainActor [weak self] in
            if let activationError {
                AppLogger.watch.error("Session activation failed: \(activationError.localizedDescription, privacy: .public)")
                return
            }
            AppLogger.watch.info("Session activated successfully")
            #if os(iOS)
            self?.isPaired = isPaired
            self?.isReachable = isReachable
            self?.checkAndSyncData()
            #else
            self?.handleSyncRequest()
            #endif
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // The application context dictionary is plain `[String: Any]` (sent
        // across processes by the OS as plist data), so it's safe to capture
        // into the MainActor hop. Core Data work happens inside on the
        // main-thread-bound `viewContext`.
        let appContext = applicationContext
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let migraineDataArray = appContext["migraineData"] as? [[String: Any]],
               let deletedIds = appContext["deletedIds"] as? [String] {
                self.processMigraineData(migraineDataArray, deletedIds: deletedIds)
            }
            #if os(watchOS)
            if let riskPayload = appContext["riskUpdate"] as? [String: Any] {
                self.processRiskData(riskPayload)
            }
            #endif
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = message
        Task { @MainActor [weak self] in
            guard let self else { return }
            if payload["requestSync"] as? Bool == true {
                self.handleSyncRequest()
            }
            #if os(watchOS)
            if let riskPayload = payload["riskUpdate"] as? [String: Any] {
                self.processRiskData(riskPayload)
            }
            #endif
        }
    }
    
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        AppLogger.watch.debug("Session became inactive")
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        AppLogger.watch.debug("Session deactivated, reactivating...")
        session.activate()
    }
    
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let isPaired = session.isPaired
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isPaired = isPaired
            self?.isReachable = isReachable
            if isPaired && isReachable {
                self?.checkAndSyncData()
            }
        }
    }
    #endif
}
#endif
