import Foundation
import CoreData

/// macOS view model: the shared `MigraineStore` plus the form-facing
/// `addMigraine`/`updateMigraine` signatures the Mac views call.
final class MigraineViewModel: MigraineStore {
    override init(context: NSManagedObjectContext) {
        super.init(context: context)
        fetchMigraines()
    }

    @MainActor
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
        let draft = MigraineDraft(
            startTime: startTime,
            endTime: endTime,
            painLevel: painLevel,
            location: location,
            notes: notes,
            triggers: triggers,
            medications: medications,
            hasAura: hasAura,
            hasPhotophobia: hasPhotophobia,
            hasPhonophobia: hasPhonophobia,
            hasNausea: hasNausea,
            hasVomiting: hasVomiting,
            hasWakeUpHeadache: hasWakeUpHeadache,
            hasTinnitus: hasTinnitus,
            hasVertigo: hasVertigo,
            missedWork: missedWork,
            missedSchool: missedSchool,
            missedEvents: missedEvents
        )

        insertMigraine(draft)
        fetchMigraines()
    }

    @MainActor
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
        let draft = MigraineDraft(
            startTime: startTime,
            endTime: endTime,
            painLevel: painLevel,
            location: location,
            notes: notes,
            triggers: triggers,
            medications: medications,
            hasAura: hasAura,
            hasPhotophobia: hasPhotophobia,
            hasPhonophobia: hasPhonophobia,
            hasNausea: hasNausea,
            hasVomiting: hasVomiting,
            hasWakeUpHeadache: hasWakeUpHeadache,
            hasTinnitus: hasTinnitus,
            hasVertigo: hasVertigo,
            missedWork: missedWork,
            missedSchool: missedSchool,
            missedEvents: missedEvents
        )

        updateMigraine(migraine, with: draft)
        fetchMigraines()
    }
}
