//
//  MigraineSyncRecordTests.swift
//  NALI Migraine LogTests
//
//  Covers the Watch sync payload: encode/decode round trip, inbound
//  validation, and the persisted `modifiedAt` revision that drives
//  last-writer-wins between iPhone and Watch.
//

import Testing
import CoreData
@testable import NALI_Migraine_Log

@Suite("MigraineSyncRecord", .serialized)
@MainActor
struct MigraineSyncRecordTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController.preview.container.viewContext
    }

    private func makeEvent(in context: NSManagedObjectContext, pain: Int16 = 5) -> MigraineEvent {
        let event = MigraineEvent(context: context)
        event.id = UUID()
        event.startTime = Date(timeIntervalSinceNow: -3_600)
        event.painLevel = pain
        return event
    }

    @Test("Saving stamps modifiedAt; explicit modifiedAt is preserved")
    func modifiedAtStamping() throws {
        let context = makeContext()
        let event = makeEvent(in: context)
        #expect(event.modifiedAt == nil)
        #expect(event.revision == .distantPast)

        try context.save()
        let stamped = try #require(event.modifiedAt)
        #expect(abs(stamped.timeIntervalSinceNow) < 5)

        let remote = Date(timeIntervalSince1970: 1_700_000_000)
        event.painLevel = 7
        event.modifiedAt = remote
        try context.save()
        #expect(event.modifiedAt == remote)

        context.delete(event)
        try context.save()
    }

    @Test("Record round-trips through the envelope and carries the event revision")
    func roundTrip() throws {
        let context = makeContext()
        let event = makeEvent(in: context, pain: 8)
        event.location = "Home"
        event.notes = "Bright lights"
        event.hasAura = true
        event.triggers = [.stress, .caffeine]
        event.medications = [.ibuprofin]
        try context.save()

        let record = try #require(MigraineSyncRecord(event: event, includeNotes: true))
        #expect(record.modifiedAt == event.modifiedAt)
        #expect(record.notes == "Bright lights")

        let envelope = WatchSyncEnvelope(kind: .delta, sentAt: Date(), records: [record], deletedIDs: [])
        let payload: [String: Any] = [WatchSyncEnvelope.payloadKey: try envelope.encoded()]
        let decoded = try #require(WatchSyncEnvelope.decode(from: payload))
        let back = try #require(decoded.records.first)

        #expect(back.id == record.id)
        #expect(back.painLevel == 8)
        #expect(back.symptoms == ["aura"])
        #expect(Set(back.triggers) == Set(["stress", "caffeine"]))
        #expect(back.medications == ["ibuprofin"])
        #expect(abs(back.modifiedAt.timeIntervalSince(record.modifiedAt)) < 1)

        let target = MigraineEvent(context: context)
        back.apply(to: target)
        #expect(target.modifiedAt == back.modifiedAt)
        #expect(target.triggers == [.stress, .caffeine])

        context.delete(event)
        context.delete(target)
        try context.save()
    }

    @Test("Snapshots omit notes and apply() keeps local notes")
    func snapshotKeepsLocalNotes() throws {
        let context = makeContext()
        let event = makeEvent(in: context)
        event.notes = "Typed on watch"
        try context.save()

        let record = try #require(MigraineSyncRecord(event: event, includeNotes: false))
        #expect(record.notes == nil)
        record.apply(to: event)
        #expect(event.notes == "Typed on watch")

        context.delete(event)
        try context.save()
    }

    @Test("Validation drops out-of-range records and trims long fields")
    func validation() {
        let now = Date()
        let base = MigraineSyncRecord(
            id: UUID(),
            startTime: now,
            endTime: nil,
            painLevel: 5,
            location: String(repeating: "x", count: 500),
            notes: String(repeating: "n", count: 5_000),
            symptoms: ["aura", "bogus"],
            triggers: ["stress", "bogus"],
            medications: ["ibuprofin", "bogus"],
            modifiedAt: now
        )

        let cleaned = base.validated(now: now)
        #expect(cleaned?.location?.count == MigraineSyncRecord.maxLocationLength)
        #expect(cleaned?.notes?.count == MigraineSyncRecord.maxNotesLength)
        #expect(cleaned?.symptoms == ["aura"])
        #expect(cleaned?.triggers == ["stress"])
        #expect(cleaned?.medications == ["ibuprofin"])

        var badPain = base
        badPain.painLevel = 11
        #expect(badPain.validated(now: now) == nil)

        var future = base
        future.startTime = now.addingTimeInterval(3 * 86_400)
        #expect(future.validated(now: now) == nil)

        var ancient = base
        ancient.startTime = Date(timeIntervalSince1970: 0)
        #expect(ancient.validated(now: now) == nil)
    }
}
