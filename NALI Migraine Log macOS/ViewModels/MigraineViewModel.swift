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

    struct DeleteAllOutcome {
        var deletedCount: Int
        var healthCleanupError: Error?
    }

    @MainActor
    func deleteAllData() async throws -> DeleteAllOutcome {
        let request = MigraineEvent.fetchRequest()
        let all = try viewContext.fetch(request)

        for migraine in all {
            viewContext.delete(migraine)
        }

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            AppLogger.coreData.error("Error clearing data: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        MigrainePredictionService.shared.clearTrainedArtifacts()

        var outcome = DeleteAllOutcome(deletedCount: all.count)
        do {
            try await HealthKitManager.shared.deleteAllMirroredSamples()
        } catch {
            outcome.healthCleanupError = error
            AppLogger.health.error("Delete-all could not remove Health samples: \(error.localizedDescription, privacy: .public)")
        }

        migraines = []
        fetchMigraines()
        AppLogger.coreData.notice("Deleted all migraine data (\(all.count, privacy: .public) entries)")
        return outcome
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
