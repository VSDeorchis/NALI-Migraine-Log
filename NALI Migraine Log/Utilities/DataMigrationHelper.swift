import Foundation
import CoreData

// Old data model for decoding
private struct OldMigraineEvent: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let painLevel: Int
    let location: String
    let triggers: [String]
    let medications: [String]
    let notes: String?
    let hasAura: Bool
    let hasPhotophobia: Bool
    let hasPhonophobia: Bool
    let hasNausea: Bool
    let hasVomiting: Bool
    let hasWakeUpHeadache: Bool
    let hasTinnitus: Bool
    let hasVertigo: Bool
    let missedWork: Bool
    let missedSchool: Bool
    let missedEvents: Bool
}

class DataMigrationHelper {
    static func checkAndMigrateData(context: NSManagedObjectContext) {
        // Check if we've already performed migration
        if UserDefaults.standard.bool(forKey: "hasPerformedCoreDateMigration") {
            return
        }
        
        // Try to load existing data from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "migraines") {
            do {
                let decoder = JSONDecoder()
                let oldMigraines = try decoder.decode([OldMigraineEvent].self, from: data)
                
                // Convert old data to Core Data entities
                for oldMigraine in oldMigraines {
                    let migraine = MigraineEvent(context: context)
                    migraine.id = oldMigraine.id
                    migraine.startTime = oldMigraine.startTime
                    migraine.endTime = oldMigraine.endTime
                    migraine.painLevel = Int16(oldMigraine.painLevel)
                    migraine.location = oldMigraine.location
                    migraine.notes = oldMigraine.notes
                    
                    // Set boolean symptoms
                    migraine.hasAura = oldMigraine.hasAura
                    migraine.hasPhotophobia = oldMigraine.hasPhotophobia
                    migraine.hasPhonophobia = oldMigraine.hasPhonophobia
                    migraine.hasNausea = oldMigraine.hasNausea
                    migraine.hasVomiting = oldMigraine.hasVomiting
                    migraine.hasWakeUpHeadache = oldMigraine.hasWakeUpHeadache
                    migraine.hasTinnitus = oldMigraine.hasTinnitus
                    migraine.hasVertigo = oldMigraine.hasVertigo
                    migraine.missedWork = oldMigraine.missedWork
                    migraine.missedSchool = oldMigraine.missedSchool
                    migraine.missedEvents = oldMigraine.missedEvents
                    
                    // Set trigger booleans directly
                    migraine.isTriggerStress = oldMigraine.triggers.contains("Stress")
                    migraine.isTriggerLackOfSleep = oldMigraine.triggers.contains("Lack of Sleep")
                    migraine.isTriggerDehydration = oldMigraine.triggers.contains("Dehydration")
                    migraine.isTriggerWeather = oldMigraine.triggers.contains("Weather")
                    migraine.isTriggerHormones = oldMigraine.triggers.contains("Hormones")
                    migraine.isTriggerAlcohol = oldMigraine.triggers.contains("Alcohol")
                    migraine.isTriggerCaffeine = oldMigraine.triggers.contains("Caffeine")
                    migraine.isTriggerFood = oldMigraine.triggers.contains("Food")
                    migraine.isTriggerExercise = oldMigraine.triggers.contains("Exercise")
                    migraine.isTriggerScreenTime = oldMigraine.triggers.contains("Screen Time")
                    migraine.isTriggerOther = oldMigraine.triggers.contains("Other")
                    
                    // Set medication booleans directly
                    migraine.tookIbuprofin = oldMigraine.medications.contains("Ibuprofen")
                    migraine.tookExcedrin = oldMigraine.medications.contains("Excedrin")
                    migraine.tookTylenol = oldMigraine.medications.contains("Tylenol")
                    migraine.tookSumatriptan = oldMigraine.medications.contains("Sumatriptan")
                    migraine.tookRizatriptan = oldMigraine.medications.contains("Rizatriptan")
                    migraine.tookNaproxen = oldMigraine.medications.contains("Naproxen")
                    migraine.tookFrovatriptan = oldMigraine.medications.contains("Frovatriptan")
                    migraine.tookNaratriptan = oldMigraine.medications.contains("Naratriptan")
                    migraine.tookNurtec = oldMigraine.medications.contains("Nurtec")
                    migraine.tookSymbravo = oldMigraine.medications.contains("Symbravo")
                    migraine.tookUbrelvy = oldMigraine.medications.contains("Ubrelvy")
                    migraine.tookReyvow = oldMigraine.medications.contains("Reyvow")
                    migraine.tookTrudhesa = oldMigraine.medications.contains("Trudhesa")
                    migraine.tookElyxyb = oldMigraine.medications.contains("Elyxyb")
                    migraine.tookOther = oldMigraine.medications.contains("Other")
                }
                
                try context.save()
                
                // Mark migration as complete
                UserDefaults.standard.set(true, forKey: "hasPerformedCoreDateMigration")
                
                // Clean up old data
                UserDefaults.standard.removeObject(forKey: "migraines")
                
                print("Successfully migrated \(oldMigraines.count) migraines to Core Data")
            } catch {
                print("Error migrating data to Core Data: \(error)")
            }
        }
    }
} 