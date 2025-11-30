import Foundation
import WatchConnectivity
import CoreData
import SwiftUI

// Add this line to import SyncStatus
@_implementationOnly import NALIMigraineLogShared

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private let session: WCSession
    private let context: NSManagedObjectContext
    private let syncQueue = DispatchQueue(label: "com.neuroli.sync", qos: .userInitiated)
    
    @Published var isPaired = false
    @Published var isReachable = false
    @Published var lastSyncTime: Date?
    @Published var syncStatus: SyncStatus = .notConfigured
    
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
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.checkAndSyncData()
            }
            #endif
        }
        
        if let deletedIdsData = UserDefaults.standard.data(forKey: deletedIdsKey),
           let deletedIds = try? JSONDecoder().decode(Set<UUID>.self, from: deletedIdsData) {
            deletedMigraineIds = deletedIds
        }
    }
    
    func sendMigraineData(_ migraine: MigraineEvent) {
        print("Attempting to send migraine data to Phone")
        guard WCSession.default.isReachable else {
            print("Phone is not reachable")
            return
        }
        
        let migraineData = migraine.toWatchSyncDictionary()
        print("Converted migraine to dictionary: \(migraineData)")
        
        // Try to update application context first
        do {
            try WCSession.default.updateApplicationContext([
                "migraineData": [migraineData],
                "deletedIds": [],
                "syncTime": Date().timeIntervalSince1970
            ])
            print("✅ Migraine data sent successfully via context")
        } catch {
            // If context update fails, try sending as a message
            WCSession.default.sendMessage(migraineData, replyHandler: { reply in
                print("✅ Migraine data sent successfully via message")
            }, errorHandler: { error in
                print("❌ Error sending migraine data: \(error.localizedDescription)")
            })
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                print("Session activation failed: \(error.localizedDescription)")
                self?.syncStatus = .error(error.localizedDescription)
                return
            }
            
            print("Session activated successfully")
            #if os(iOS)
            self?.isPaired = session.isPaired
            self?.isReachable = session.isReachable
            self?.syncStatus = .enabled
            self?.checkAndSyncData()
            #else
            self?.handleSyncRequest()
            #endif
        }
    }
    
    // ... rest of the implementation ...
} 