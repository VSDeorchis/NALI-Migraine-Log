import CoreData
import Combine
import Foundation

enum MigraineError: LocalizedError {
    case saveFailed(Error)
    case fetchFailed(Error)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save migraine: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch migraines: \(error.localizedDescription)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        }
    }
}

/// Platform-neutral core of the migraine view models. Owns the main-queue
/// context, the published entry list and every Core Data mutation; the
/// iOS/watchOS and macOS `MigraineViewModel` subclasses add platform
/// behaviour (fetched-results controller, weather, Watch sync, Health
/// mirroring) around these primitives.
///
/// Subclasses replace `migraines`/`lastError` wholesale; views treat both
/// as read-only.
class MigraineStore: NSObject, ObservableObject {
    /// Result of `deleteAllData()`. Core Data and ML artifacts are always
    /// cleared or the call throws; Health is the one dependency whose
    /// failure is reported instead, because the local wipe already happened
    /// and the user can finish the job in the Health app.
    struct DeleteAllOutcome {
        var deletedCount: Int
        var deletedIDs: [UUID]
        var healthCleanupError: Error?
    }

    @Published var migraines: [MigraineEvent] = []
    @Published var lastError: MigraineError?

    let viewContext: NSManagedObjectContext

    let locations = [
        "Frontal",
        "Whole Head",
        "Left Side",
        "Right Side",
        "Occipital/Back of Head"
    ]

    let triggers = [
        "Stress",
        "Lack of Sleep",
        "Dehydration",
        "Weather",
        "Menstrual",
        "Alcohol",
        "Caffeine",
        "Food",
        "Exercise",
        "Screen Time",
        "Other"
    ]

    let medications = [
        "Ibuprofen",
        "Excedrin",
        "Tylenol",
        "Sumatriptan",
        "Rizatriptan",
        "Naproxen",
        "Frovatriptan",
        "Naratriptan",
        "Nurtec",
        "Symbravo",
        "Ubrelvy",
        "Reyvow",
        "Trudhesa",
        "Elyxyb",
        "Other"
    ]

    init(context: NSManagedObjectContext) {
        self.viewContext = context
        super.init()
    }

    // MARK: - Fetching

    /// Loads every entry, newest first. Subclasses with a fetched-results
    /// controller override this.
    func fetchMigraines() {
        let request = MigraineEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]

        do {
            migraines = try viewContext.fetch(request)
        } catch {
            lastError = .fetchFailed(error)
            AppLogger.coreData.error("Error fetching migraines: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Mutations

    /// Inserts and saves a new entry. Returns `nil` (and publishes
    /// `lastError`) when the save fails; the context is rolled back.
    @MainActor
    @discardableResult
    func insertMigraine(_ draft: MigraineDraft) -> MigraineEvent? {
        let migraine = MigraineEvent(context: viewContext)
        migraine.id = UUID()
        migraine.apply(draft)
        migraine.clearWeatherData()

        // Temporarily disable automatic merging to prevent deadlock
        let originalMergesSetting = viewContext.automaticallyMergesChangesFromParent
        viewContext.automaticallyMergesChangesFromParent = false
        defer { viewContext.automaticallyMergesChangesFromParent = originalMergesSetting }

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Failed to save migraine: \(error.localizedDescription, privacy: .private)")
            return nil
        }

        // Refresh the object to ensure it's not a fault
        viewContext.refresh(migraine, mergeChanges: false)
        AppLogger.coreData.notice("Migraine saved; id=\(migraine.id?.uuidString ?? "nil", privacy: .public)")
        return migraine
    }

    /// Overwrites `migraine` with `draft` and saves.
    @MainActor
    @discardableResult
    func updateMigraine(_ migraine: MigraineEvent, with draft: MigraineDraft) -> Bool {
        migraine.apply(draft)
        return saveContext()
    }

    /// Deletes `migraine`, saves and reloads the list. Subclasses that need
    /// the entry's identity after deletion capture it before calling super.
    @MainActor
    @discardableResult
    func deleteMigraine(_ migraine: MigraineEvent) -> Bool {
        viewContext.delete(migraine)

        do {
            try viewContext.save()
        } catch {
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error deleting migraine: \(error.localizedDescription, privacy: .private)")
            viewContext.rollback()
            return false
        }

        fetchMigraines()
        return true
    }

    /// Erases every migraine on this device and everything derived from it:
    /// Core Data rows (deleted one by one so CloudKit mirroring propagates
    /// the deletes — batch requests bypass the mirroring pipeline), the
    /// Health samples this app wrote, and the on-device ML training data
    /// and model. Recovery backups made by `PersistenceController` are left
    /// alone; the user manages those explicitly from Settings.
    @MainActor
    func deleteAllData() async throws -> DeleteAllOutcome {
        let request = MigraineEvent.fetchRequest()

        let all: [MigraineEvent]
        do {
            all = try viewContext.fetch(request)
        } catch {
            lastError = .fetchFailed(error)
            throw MigraineError.fetchFailed(error)
        }

        let ids = all.compactMap(\.id)
        for migraine in all {
            viewContext.delete(migraine)
        }

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error clearing data: \(error.localizedDescription, privacy: .private)")
            throw MigraineError.saveFailed(error)
        }

        migrainesWereErased(ids: ids)
        MigrainePredictionService.shared.clearTrainedArtifacts()
        MigraineDraftStore.clear()

        var outcome = DeleteAllOutcome(deletedCount: all.count, deletedIDs: ids)
        if #available(iOS 17.0, watchOS 10.0, *) {
            do {
                try await HealthKitManager.shared.deleteAllMirroredSamples()
            } catch {
                outcome.healthCleanupError = error
                AppLogger.health.error("Delete-all could not remove Health samples: \(error.localizedDescription, privacy: .private)")
            }
        }

        migraines = []
        fetchMigraines()

        AppLogger.coreData.notice("Deleted all migraine data (\(all.count, privacy: .public) entries)")
        return outcome
    }

    /// Called by `deleteAllData()` right after the Core Data save commits,
    /// before any asynchronous cleanup. Default does nothing.
    @MainActor
    func migrainesWereErased(ids: [UUID]) {}

    /// Saves `viewContext` synchronously (it is a main-queue context and
    /// every caller is already on the main actor). Returns `false` and
    /// publishes `lastError` when the save fails.
    @MainActor
    @discardableResult
    func saveContext() -> Bool {
        guard viewContext.hasChanges else { return true }

        do {
            try viewContext.save()
            return true
        } catch {
            lastError = .saveFailed(error)
            AppLogger.coreData.error("Error saving context: \(error.localizedDescription, privacy: .private)")
            viewContext.rollback()
            return false
        }
    }

    // MARK: - Summary statistics

    var commonTriggers: [(String, Int)] {
        var triggerCounts: [String: Int] = [:]
        for migraine in migraines {
            for trigger in migraine.triggers {
                triggerCounts[trigger.displayName, default: 0] += 1
            }
        }
        return triggerCounts.sorted { $0.value > $1.value }
    }

    var medicationUsage: [(String, Int)] {
        var medicationCounts: [String: Int] = [:]
        for migraine in migraines {
            for medication in migraine.medications {
                medicationCounts[medication.displayName, default: 0] += 1
            }
        }
        return medicationCounts.sorted { $0.value > $1.value }
    }

    var averagePainLevel: Double {
        guard !migraines.isEmpty else { return 0 }
        let sum = migraines.reduce(0) { $0 + Double($1.painLevel) }
        return sum / Double(migraines.count)
    }

    var migraineFrequency: String {
        guard !migraines.isEmpty else { return "No data" }

        let calendar = Calendar.current
        let now = Date()
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-30 * 86_400)

        let monthlyCount = migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return startTime >= oneMonthAgo
        }.count

        return "\(monthlyCount) per month"
    }

    var averageDuration: TimeInterval? {
        let durationsWithEndTime = migraines.compactMap { migraine -> TimeInterval? in
            guard let startTime = migraine.startTime,
                  let endTime = migraine.endTime else { return nil }
            return endTime.timeIntervalSince(startTime)
        }

        guard !durationsWithEndTime.isEmpty else { return nil }
        return durationsWithEndTime.reduce(0, +) / Double(durationsWithEndTime.count)
    }
}
