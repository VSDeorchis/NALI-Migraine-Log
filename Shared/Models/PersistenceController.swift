//
//  PersistenceController.swift
//  NALI Migraine Log
//
//  Shared Core Data controller
//

import CoreData
import SwiftUI

public final class PersistenceController: ObservableObject {
    @Published public var syncStatus: SyncStatus = .notConfigured
    public static let shared = PersistenceController()
    
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
    
    let container: NSPersistentContainer
    
    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NALI_Migraine_Log")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure store
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            
            let storeOptions: [String: NSObject] = [
                NSMigratePersistentStoresAutomaticallyOption: true as NSNumber,
                NSInferMappingModelAutomaticallyOption: true as NSNumber,
                NSSQLitePragmasOption: ["journal_mode": "WAL"] as NSObject
            ]
            
            for (key, value) in storeOptions {
                description.setOption(value, forKey: key)
            }
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error)")
                self.handlePersistentStoreError(error)
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.shouldDeleteInaccessibleFaults = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreRemoved),
            name: NSNotification.Name.NSPersistentStoreCoordinatorStoresWillChange,
            object: container.persistentStoreCoordinator
        )
    }
    
    private func handlePersistentStoreError(_ error: Error) {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }
        
        do {
            try container.persistentStoreCoordinator.persistentStores.forEach { store in
                try container.persistentStoreCoordinator.remove(store)
            }
            
            try FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            
            try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: nil
            )
        } catch {
            print("Failed to recover from persistent store error: \(error)")
            fatalError("Unresolvable Core Data error: \(error)")
        }
    }
    
    @objc private func handleStoreRemoved(_ notification: Notification) {
        container.viewContext.reset()
    }
    
    func migrateDataToNewStore(completion: @escaping (Result<Void, Error>) -> Void) {
        // Implement migration logic here
        completion(.success(()))
    }
} 