import Foundation
import CoreData

// On-disk shape of the legacy UserDefaults-backed migraine log. Decoded once
// at first launch after upgrading to the Core Data + CloudKit storage path.
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

enum DataMigrationHelper {
    private static let migrationCompletedKey = "hasPerformedCoreDateMigration"
    private static let legacyDataKey = "migraines"

    static func checkAndMigrateData(context: NSManagedObjectContext) {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else {
            return
        }

        guard let data = UserDefaults.standard.data(forKey: legacyDataKey) else {
            // Nothing to migrate — record completion so we don't re-check on
            // every launch.
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            return
        }

        do {
            let oldMigraines = try JSONDecoder().decode([OldMigraineEvent].self, from: data)

            for old in oldMigraines {
                let migraine = MigraineEvent(context: context)
                migraine.id = old.id
                migraine.startTime = old.startTime
                migraine.endTime = old.endTime
                migraine.painLevel = Int16(old.painLevel)
                migraine.location = old.location
                migraine.notes = old.notes

                migraine.hasAura = old.hasAura
                migraine.hasPhotophobia = old.hasPhotophobia
                migraine.hasPhonophobia = old.hasPhonophobia
                migraine.hasNausea = old.hasNausea
                migraine.hasVomiting = old.hasVomiting
                migraine.hasWakeUpHeadache = old.hasWakeUpHeadache
                migraine.hasTinnitus = old.hasTinnitus
                migraine.hasVertigo = old.hasVertigo
                migraine.missedWork = old.missedWork
                migraine.missedSchool = old.missedSchool
                migraine.missedEvents = old.missedEvents

                // Round-trip through the enum facades so legacy synonyms
                // (e.g. "Hormones" → .menstrual, "Ibuprofin" → .ibuprofin)
                // are honored, and so any new cases added to MigraineTrigger /
                // MigraineMedication are picked up automatically.
                migraine.triggers = Set(old.triggers.compactMap(MigraineTrigger.init(displayName:)))
                migraine.medications = Set(old.medications.compactMap(MigraineMedication.init(displayName:)))
            }

            try context.save()

            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            UserDefaults.standard.removeObject(forKey: legacyDataKey)

            AppLogger.migration.notice("Migrated \(oldMigraines.count, privacy: .public) migraines from UserDefaults to Core Data")
        } catch {
            AppLogger.migration.error("Failed migrating data to Core Data: \(error.localizedDescription, privacy: .public)")
        }
    }
}
