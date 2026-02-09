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
        medications: [String],
        hasAura: Bool = false,
        hasPhotophobia: Bool = false,
        hasPhonophobia: Bool = false,
        hasNausea: Bool = false,
        hasVomiting: Bool = false,
        hasWakeUpHeadache: Bool = false,
        hasTinnitus: Bool = false,
        hasVertigo: Bool = false,
        missedWork: Bool = false,
        missedSchool: Bool = false,
        missedEvents: Bool = false
    ) {
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
        
        // Map trigger names to boolean properties
        applyTriggers(triggers, to: migraine)
        
        // Map medication names to boolean properties
        applyMedications(medications, to: migraine)
        
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
        medications: [String],
        hasAura: Bool = false,
        hasPhotophobia: Bool = false,
        hasPhonophobia: Bool = false,
        hasNausea: Bool = false,
        hasVomiting: Bool = false,
        hasWakeUpHeadache: Bool = false,
        hasTinnitus: Bool = false,
        hasVertigo: Bool = false,
        missedWork: Bool = false,
        missedSchool: Bool = false,
        missedEvents: Bool = false
    ) {
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
        
        // Reset all triggers and medications, then apply new selections
        resetTriggers(migraine)
        resetMedications(migraine)
        applyTriggers(triggers, to: migraine)
        applyMedications(medications, to: migraine)
        
        save()
        fetchMigraines()
    }
    
    // MARK: - Trigger Mapping
    
    private func applyTriggers(_ triggers: [String], to migraine: MigraineEvent) {
        for trigger in triggers {
            switch trigger {
            case "Stress": migraine.isTriggerStress = true
            case "Sleep Changes", "Lack of Sleep": migraine.isTriggerLackOfSleep = true
            case "Weather": migraine.isTriggerWeather = true
            case "Food": migraine.isTriggerFood = true
            case "Caffeine": migraine.isTriggerCaffeine = true
            case "Alcohol": migraine.isTriggerAlcohol = true
            case "Exercise": migraine.isTriggerExercise = true
            case "Screen Time": migraine.isTriggerScreenTime = true
            case "Hormonal", "Hormones": migraine.isTriggerHormones = true
            case "Dehydration": migraine.isTriggerDehydration = true
            case "Other": migraine.isTriggerOther = true
            default: break
            }
        }
    }
    
    private func resetTriggers(_ migraine: MigraineEvent) {
        migraine.isTriggerStress = false
        migraine.isTriggerLackOfSleep = false
        migraine.isTriggerWeather = false
        migraine.isTriggerFood = false
        migraine.isTriggerCaffeine = false
        migraine.isTriggerAlcohol = false
        migraine.isTriggerExercise = false
        migraine.isTriggerScreenTime = false
        migraine.isTriggerHormones = false
        migraine.isTriggerDehydration = false
        migraine.isTriggerOther = false
    }
    
    // MARK: - Medication Mapping
    
    private func applyMedications(_ medications: [String], to migraine: MigraineEvent) {
        for medication in medications {
            switch medication {
            case "Sumatriptan": migraine.tookSumatriptan = true
            case "Rizatriptan": migraine.tookRizatriptan = true
            case "Eletriptan": migraine.tookEletriptan = true
            case "Frovatriptan": migraine.tookFrovatriptan = true
            case "Naratriptan": migraine.tookNaratriptan = true
            case "Ubrelvy": migraine.tookUbrelvy = true
            case "Nurtec": migraine.tookNurtec = true
            case "Reyvow": migraine.tookReyvow = true
            case "Trudhesa": migraine.tookTrudhesa = true
            case "Elyxyb": migraine.tookElyxyb = true
            case "Tylenol": migraine.tookTylenol = true
            case "Advil", "Ibuprofen": migraine.tookIbuprofin = true
            case "Naproxen": migraine.tookNaproxen = true
            case "Excedrin": migraine.tookExcedrin = true
            case "Other": migraine.tookOther = true
            default: break
            }
        }
    }
    
    private func resetMedications(_ migraine: MigraineEvent) {
        migraine.tookSumatriptan = false
        migraine.tookRizatriptan = false
        migraine.tookEletriptan = false
        migraine.tookFrovatriptan = false
        migraine.tookNaratriptan = false
        migraine.tookUbrelvy = false
        migraine.tookNurtec = false
        migraine.tookReyvow = false
        migraine.tookTrudhesa = false
        migraine.tookElyxyb = false
        migraine.tookTylenol = false
        migraine.tookIbuprofin = false
        migraine.tookNaproxen = false
        migraine.tookExcedrin = false
        migraine.tookOther = false
    }
    
    private func save() {
        do {
            try viewContext.save()
            objectWillChange.send()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
