class PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        if #available(iOS 14.0, watchOS 7.0, *) {
            container = NSPersistentCloudKitContainer(name: "NALI_Migraine_Log")
        } else {
            container = NSPersistentContainer(name: "NALI_Migraine_Log")
        }
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Try to configure CloudKit
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            
            #if os(iOS)
            // Only try to use CloudKit on iOS if available
            if let _ = description.cloudKitContainerOptions {
                print("CloudKit configured")
            } else {
                print("CloudKit not available, falling back to direct sync")
                description.cloudKitContainerOptions = nil
            }
            #endif
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
} 