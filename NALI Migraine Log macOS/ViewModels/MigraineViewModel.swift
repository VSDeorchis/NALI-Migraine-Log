import Foundation
import CoreData

class MigraineViewModel: ObservableObject {
    @Published var migraines: [MigraineEvent] = []
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        fetchMigraines()
    }
    
    func fetchMigraines() {
        let request = MigraineEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        
        do {
            migraines = try viewContext.fetch(request)
        } catch {
            print("Error fetching migraines: \(error)")
        }
    }
    
    func addMigraine(
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        notes: String?,
        triggers: [String],
        medications: [String]
    ) {
        let migraine = MigraineEvent(context: viewContext)
        migraine.id = UUID()
        migraine.startTime = startTime
        migraine.endTime = endTime
        migraine.painLevel = painLevel
        migraine.location = location
        migraine.notes = notes
        
        // Add triggers
        for triggerName in triggers {
            let trigger = TriggerEntity(context: viewContext)
            trigger.name = triggerName
            trigger.migraine = migraine
        }
        
        // Add medications
        for medicationName in medications {
            let medication = MedicationEntity(context: viewContext)
            medication.name = medicationName
            medication.migraine = migraine
        }
        
        save()
        fetchMigraines()
    }
    
    func deleteMigraine(_ migraine: MigraineEvent) {
        viewContext.delete(migraine)
        save()
        fetchMigraines()
    }
    
    func updateMigraine(
        _ migraine: MigraineEvent,
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        notes: String?,
        triggers: [String],
        medications: [String]
    ) {
        migraine.startTime = startTime
        migraine.endTime = endTime
        migraine.painLevel = painLevel
        migraine.location = location
        migraine.notes = notes
        
        // Remove existing triggers and medications
        if let existingTriggers = migraine.triggers as? NSSet {
            for case let trigger as TriggerEntity in existingTriggers {
                viewContext.delete(trigger)
            }
        }
        
        if let existingMedications = migraine.medications as? NSSet {
            for case let medication as MedicationEntity in existingMedications {
                viewContext.delete(medication)
            }
        }
        
        // Add new triggers
        for triggerName in triggers {
            let trigger = TriggerEntity(context: viewContext)
            trigger.name = triggerName
            trigger.migraine = migraine
        }
        
        // Add new medications
        for medicationName in medications {
            let medication = MedicationEntity(context: viewContext)
            medication.name = medicationName
            medication.migraine = migraine
        }
        
        save()
        fetchMigraines()
    }
    
    private func save() {
        do {
            try viewContext.save()
            objectWillChange.send()
            fetchMigraines()
        } catch {
            print("Error saving context: \(error)")
        }
    }
} 