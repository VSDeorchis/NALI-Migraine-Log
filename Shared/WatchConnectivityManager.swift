#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import CoreData
import SwiftUI

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private let session: WCSession
    private let context: NSManagedObjectContext
    private let syncQueue = DispatchQueue(label: "com.neuroli.sync", qos: .userInitiated)
    
    @Published var isPaired = false
    @Published var isReachable = false
    @Published var lastSyncTime: Date?
    
    private var deletedMigraineIds: Set<UUID> = []
    private let deletedIdsKey = "com.neuroli.deletedMigraineIds"
    
    init(session: WCSession = .default) {
        self.session = session
        self.context = PersistenceController.shared.container.viewContext
        super.init()
        
        if WCSession.isSupported() {
            print("WCSession is supported")
            session.delegate = self
            session.activate()
            
            #if os(iOS)
            // Schedule more frequent syncs for Watch connectivity
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.checkAndSyncData()
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
            print("Session not activated")
            return
        }
        
        syncQueue.async { [weak self] in
            self?.sendMigraineData()
        }
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
            let migraineData = migraines.compactMap { migraine -> [String: Any]? in
                guard let id = migraine.id else { return nil }
                return migraine.toWatchSyncDictionary()
            }
            
            let applicationContext: [String: Any] = [
                "migraineData": migraineData,
                "deletedIds": Array(deletedMigraineIds.map { $0.uuidString }),
                "syncTime": Date().timeIntervalSince1970
            ]
            
            try session.updateApplicationContext(applicationContext)
            
            DispatchQueue.main.async { [weak self] in
                self?.lastSyncTime = Date()
                print("Successfully synced \(migraineData.count) migraines and \(self?.deletedMigraineIds.count ?? 0) deletions")
            }
            
        } catch {
            print("Error syncing data: \(error)")
            
            // If updating application context fails, try sending as a message
            if session.isReachable {
                session.sendMessage(["requestSync": true], replyHandler: nil) { error in
                    print("Error sending sync request: \(error)")
                }
            }
        }
    }
    
    #if os(watchOS)
    /// Request full sync from the paired iPhone
    func requestFullSync() {
        guard session.isReachable else { return }
        session.sendMessage(["requestSync": true], replyHandler: nil) { error in
            print("Error requesting sync: \(error)")
        }
    }
    #endif
    
    // Handle incoming sync requests
    func handleSyncRequest() {
        syncQueue.async { [weak self] in
            self?.sendMigraineData()
        }
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
    
    // Add debug logging to track data flow
    func sendMigraineData(_ migraine: MigraineEvent) {
        print("Attempting to send migraine data to Watch")
        guard WCSession.default.isReachable else {
            print("Watch is not reachable")
            return
        }
        
        let migraineData = migraine.toWatchSyncDictionary()
        print("Converted migraine to dictionary: \(migraineData)")
        
        WCSession.default.sendMessage(migraineData, replyHandler: { reply in
            print("✅ Migraine data sent successfully")
        }, errorHandler: { error in
            print("❌ Error sending migraine data: \(error.localizedDescription)")
        })
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                print("Session activation failed: \(error.localizedDescription)")
                return
            }
            
            print("Session activated successfully")
            #if os(iOS)
            self?.isPaired = session.isPaired
            self?.isReachable = session.isReachable
            self?.checkAndSyncData()
            #else
            // Watch app should request data when activated
            self?.handleSyncRequest()
            #endif
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let migraineDataArray = applicationContext["migraineData"] as? [[String: Any]],
              let deletedIds = applicationContext["deletedIds"] as? [String] else {
            print("Invalid data format")
            return
        }
        
        context.perform { [weak self] in
            self?.processMigraineData(migraineDataArray, deletedIds: deletedIds)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["requestSync"] as? Bool == true {
            handleSyncRequest()
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("Session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("Session deactivated, reactivating...")
        session.activate()
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaired = session.isPaired
            self?.isReachable = session.isReachable
            if session.isPaired && session.isReachable {
                self?.checkAndSyncData()
            }
        }
    }
    #endif
}
#endif
