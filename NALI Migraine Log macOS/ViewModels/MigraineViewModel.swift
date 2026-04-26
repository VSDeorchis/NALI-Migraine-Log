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
            AppLogger.coreData.error("Error fetching migraines: \(error.localizedDescription, privacy: .public)")
        }
    }

    func addMigraine(
        startTime: Date,
        endTime: Date?,
        painLevel: Int16,
        location: String,
        notes: String?,
        triggers: Set<MigraineTrigger>,
        medications: Set<MigraineMedication>,
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

        // Facade setters write all underlying booleans atomically (true if in
        // the set, false otherwise), so no separate "reset" pass is needed.
        migraine.triggers = triggers
        migraine.medications = medications

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
        triggers: Set<MigraineTrigger>,
        medications: Set<MigraineMedication>,
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

        migraine.triggers = triggers
        migraine.medications = medications

        save()
        fetchMigraines()
    }

    private func save() {
        do {
            try viewContext.save()
            objectWillChange.send()
        } catch {
            AppLogger.coreData.error("Error saving context: \(error.localizedDescription, privacy: .public)")
        }
    }
}
