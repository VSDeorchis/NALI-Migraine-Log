#if DEBUG
import CoreData
import Foundation

// MARK: - Developer diagnostics (DEBUG builds only)

extension MigraineViewModel {
    /// Dev-only diagnostic dump of the in-memory migraine list. Only
    /// non-identifying fields (id, timestamps, pain, counts) are logged.
    func printDebugInfo() {
        AppLogger.coreData.debug("=== Current Migraines (\(self.migraines.count, privacy: .public)) ===")
        for migraine in migraines {
            AppLogger.coreData.debug(
                "id=\(migraine.id?.uuidString ?? "nil", privacy: .public) start=\(migraine.startTime?.description ?? "nil", privacy: .public) pain=\(migraine.painLevel, privacy: .public) triggers=\(migraine.triggers.count, privacy: .public) meds=\(migraine.medications.count, privacy: .public) hasNotes=\(!(migraine.notes ?? "").isEmpty, privacy: .public)"
            )
        }
    }

    /// Dev-only data dump of non-identifying fields (id, dates, pain,
    /// counts). Free-text fields are never logged.
    func verifyMigraineData(_ migraine: MigraineEvent) {
        AppLogger.coreData.debug(
            "verifyMigraineData id=\(migraine.id?.uuidString ?? "nil", privacy: .public) start=\(migraine.startTime?.description ?? "nil", privacy: .public) pain=\(migraine.painLevel, privacy: .public) triggers=\(migraine.triggers.count, privacy: .public) meds=\(migraine.medications.count, privacy: .public)"
        )
    }

    private func verifyAllMigraines() {
        let fetchRequest: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "notes CONTAINS[c] %@", "test migraine")

        do {
            let testMigraines = try viewContext.fetch(fetchRequest)
            AppLogger.coreData.debug("verifyAllMigraines: found \(testMigraines.count, privacy: .public) test entries")
            for migraine in testMigraines {
                verifyMigraineData(migraine)
            }
        } catch {
            AppLogger.coreData.error("Error verifying test data: \(error.localizedDescription, privacy: .private)")
        }
    }

    func createTestData() {
        let today = Date()
        let migraine1 = MigraineEvent(context: viewContext)
        migraine1.id = UUID()
        migraine1.startTime = today
        migraine1.endTime = today.addingTimeInterval(7200)
        migraine1.painLevel = 5
        migraine1.location = "Frontal"
        migraine1.notes = "Test migraine today"
        migraine1.triggers = [.stress, .lackOfSleep]
        migraine1.medications = [.sumatriptan]

        do {
            try viewContext.save()
            AppLogger.coreData.notice("Saved test migraines")
            fetchMigraines()
            verifyAllMigraines()
        } catch {
            AppLogger.coreData.error("Error saving test data: \(error.localizedDescription, privacy: .private)")
            viewContext.rollback()
        }
    }
}
#endif
