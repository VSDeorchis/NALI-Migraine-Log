class PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    @Published var syncStatus: SyncStatus = .notConfigured
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NALI_Migraine_Log")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure CloudKit integration
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve store description")
        }
        
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.yourapp.NALIMigraineLog")
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
                // Handle CloudKit specific errors
                if (error as NSError).domain == NSCocoaErrorDomain && 
                   (error as NSError).code == 134400 {
                    // CloudKit is not available (no iCloud account)
                    self.syncStatus = .disabled
                } else {
                    self.syncStatus = .error(error.localizedDescription)
                }
            } else {
                print("Core Data store loaded successfully")
                self.syncStatus = .enabled
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

extension PersistenceController {
    enum SyncStatus: Equatable {
        case notConfigured
        case enabled
        case disabled
        case error(String)
        case syncing(Double)
        case pendingChanges(Int)
        
        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.notConfigured, .notConfigured): return true
            case (.enabled, .enabled): return true
            case (.disabled, .disabled): return true
            case (.error(let e1), .error(let e2)): return e1 == e2
            case (.syncing(let p1), .syncing(let p2)): return p1 == p2
            case (.pendingChanges(let c1), .pendingChanges(let c2)): return c1 == c2
            default: return false
            }
        }
    }
} 