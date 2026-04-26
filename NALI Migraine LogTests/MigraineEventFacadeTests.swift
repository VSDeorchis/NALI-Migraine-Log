//
//  MigraineEventFacadeTests.swift
//  NALI Migraine LogTests
//
//  Round-trip tests for the `MigraineEvent` enum-set facade. These verify
//  that writing a `Set<MigraineTrigger>` / `Set<MigraineMedication>` to a
//  Core Data event and reading it back produces an equal set, and that
//  `orderedTriggers` / `orderedMedications` return values in the canonical
//  declaration order regardless of insertion order.
//
//  Storage on disk is unchanged from the boolean-attribute era, so a
//  regression here would silently corrupt user data — these tests are the
//  guardrail.
//

import Testing
import CoreData
@testable import NALI_Migraine_Log

@Suite("MigraineEvent enum-set facade", .serialized)
@MainActor
struct MigraineEventFacadeTests {

    /// In-memory Core Data context backed by `PersistenceController.preview`.
    ///
    /// `preview` is a single shared in-memory instance (Core Data store is
    /// `/dev/null`-backed), but every test below operates on a freshly-
    /// inserted `MigraineEvent` and only inspects properties of *that*
    /// event, so the shared context can't bleed state across tests.
    private func makeContext() -> NSManagedObjectContext {
        return PersistenceController.preview.container.viewContext
    }

    /// Builds a minimal valid `MigraineEvent` so we can exercise the facade
    /// without dragging in the full new-migraine flow.
    private func makeEvent(in context: NSManagedObjectContext) -> MigraineEvent {
        let event = MigraineEvent(context: context)
        event.id = UUID()
        event.startTime = Date()
        event.painLevel = 5
        event.location = "Frontal"
        return event
    }

    // MARK: - Triggers

    @Test("Triggers round-trip: write Set, read Set, equal")
    func triggerSetRoundTrip() {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)

        let original: Set<MigraineTrigger> = [.stress, .menstrual, .screenTime]
        event.triggers = original

        #expect(event.triggers == original)
    }

    @Test("Setting an empty Set clears every trigger boolean")
    func clearingTriggers() {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)
        event.triggers = MigraineTrigger.allCases.reduce(into: Set<MigraineTrigger>()) { $0.insert($1) }
        #expect(event.triggers.count == MigraineTrigger.allCases.count)

        event.triggers = []
        #expect(event.triggers.isEmpty)
    }

    @Test("Menstrual maps to the legacy `isTriggerHormones` storage attribute")
    func menstrualUsesHormonesStorage() {
        // The on-disk Core Data attribute is still named `isTriggerHormones`
        // (renaming would require a model migration). The facade hides this,
        // but the underlying boolean must flip — otherwise CloudKit syncs
        // and CSV exports against the boolean would diverge from the facade.
        let ctx = makeContext()
        let event = makeEvent(in: ctx)
        event.triggers = [.menstrual]
        #expect(event.isTriggerHormones == true)
        #expect(event.triggers.contains(.menstrual))
    }

    @Test("orderedTriggers returns canonical declaration order regardless of insertion order")
    func orderedTriggersIsCanonical() {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)

        // Pick a deliberately out-of-order subset so a naïve
        // `Array(triggers)` would fail the assertion.
        event.triggers = [.screenTime, .stress, .weather, .alcohol]

        #expect(event.orderedTriggers == [.stress, .weather, .alcohol, .screenTime])
    }

    // MARK: - Medications

    @Test("Medications round-trip: write Set, read Set, equal")
    func medicationSetRoundTrip() {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)

        let original: Set<MigraineMedication> = [.ibuprofin, .sumatriptan, .nurtec]
        event.medications = original

        #expect(event.medications == original)
    }

    @Test("Setting an empty Set clears every medication boolean")
    func clearingMedications() {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)
        event.medications = MigraineMedication.allCases.reduce(into: Set<MigraineMedication>()) { $0.insert($1) }
        #expect(event.medications.count == MigraineMedication.allCases.count)

        event.medications = []
        #expect(event.medications.isEmpty)
    }

    @Test("orderedMedications returns canonical declaration order regardless of insertion order")
    func orderedMedicationsIsCanonical() {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)

        event.medications = [.nurtec, .tylenol, .reyvow, .ibuprofin]

        #expect(event.orderedMedications == [.tylenol, .ibuprofin, .nurtec, .reyvow])
    }

    @Test("Ibuprofin facade flips the `tookIbuprofin` storage boolean")
    func ibuprofinUsesLegacyStorageSpelling() {
        // Same hazard as `isTriggerHormones`: on-disk attribute keeps the
        // historic spelling, facade hides it. If this drifts, exports break.
        let ctx = makeContext()
        let event = makeEvent(in: ctx)
        event.medications = [.ibuprofin]
        #expect(event.tookIbuprofin == true)
        #expect(event.medications.contains(.ibuprofin))
    }

    // MARK: - Persistence

    @Test("Triggers and medications survive a context save + re-fetch")
    func setsSurviveSaveAndRefetch() throws {
        let ctx = makeContext()
        let event = makeEvent(in: ctx)
        let triggerSet: Set<MigraineTrigger> = [.stress, .lackOfSleep]
        let medSet: Set<MigraineMedication> = [.sumatriptan, .ibuprofin]
        event.triggers = triggerSet
        event.medications = medSet

        try ctx.save()
        ctx.refresh(event, mergeChanges: false)

        #expect(event.triggers == triggerSet)
        #expect(event.medications == medSet)
    }
}
