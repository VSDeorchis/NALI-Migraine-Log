//
//  WatchSyncResolutionTests.swift
//  NALI Migraine LogTests
//
//  Conflict handling for inbound Watch/iPhone records (last-writer-wins on
//  `modifiedAt`, tombstones, un-acknowledged local edits) and rejection of
//  foreign, truncated or wrong-version payloads.
//

import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("Watch sync resolution")
struct WatchSyncResolutionTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(modifiedAt: Date, id: UUID = UUID()) -> MigraineSyncRecord {
        MigraineSyncRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_699_990_000),
            endTime: nil,
            painLevel: 5,
            location: "Frontal",
            notes: nil,
            symptoms: ["nausea"],
            triggers: [],
            medications: [],
            modifiedAt: modifiedAt
        )
    }

    @Test("A record newer than the local revision is applied for both deltas and snapshots")
    func newerWins() {
        let incoming = record(modifiedAt: t0.addingTimeInterval(60))
        for kind in [WatchSyncEnvelope.Kind.delta, .snapshot] {
            let result = WatchSyncEnvelope.resolve(
                incoming: incoming, kind: kind, localRevision: t0,
                isTombstoned: false, hasPendingLocalEdit: false
            )
            #expect(result == .apply)
        }
    }

    @Test("A record older than the local revision is skipped (last-writer-wins)")
    func olderLoses() {
        let incoming = record(modifiedAt: t0.addingTimeInterval(-1))
        for kind in [WatchSyncEnvelope.Kind.delta, .snapshot] {
            let result = WatchSyncEnvelope.resolve(
                incoming: incoming, kind: kind, localRevision: t0,
                isTombstoned: false, hasPendingLocalEdit: false
            )
            #expect(result == .skipOlderThanLocal)
        }
    }

    @Test("Equal revisions apply so a retransmitted record converges instead of stalling")
    func equalRevisionApplies() {
        let result = WatchSyncEnvelope.resolve(
            incoming: record(modifiedAt: t0), kind: .delta, localRevision: t0,
            isTombstoned: false, hasPendingLocalEdit: false
        )
        #expect(result == .apply)
    }

    @Test("Unknown local entry is always inserted")
    func newEntryInserted() {
        let result = WatchSyncEnvelope.resolve(
            incoming: record(modifiedAt: t0), kind: .snapshot, localRevision: nil,
            isTombstoned: false, hasPendingLocalEdit: false
        )
        #expect(result == .apply)
    }

    @Test("Tombstones beat everything, including a newer incoming edit")
    func tombstoneWins() {
        let result = WatchSyncEnvelope.resolve(
            incoming: record(modifiedAt: t0.addingTimeInterval(3_600)), kind: .delta, localRevision: t0,
            isTombstoned: true, hasPendingLocalEdit: false
        )
        #expect(result == .skipTombstoned)
    }

    @Test("Snapshots do not clobber a local edit the counterpart hasn't acknowledged; deltas do")
    func pendingLocalEdit() {
        let incoming = record(modifiedAt: t0.addingTimeInterval(10))
        let snapshot = WatchSyncEnvelope.resolve(
            incoming: incoming, kind: .snapshot, localRevision: t0,
            isTombstoned: false, hasPendingLocalEdit: true
        )
        let delta = WatchSyncEnvelope.resolve(
            incoming: incoming, kind: .delta, localRevision: t0,
            isTombstoned: false, hasPendingLocalEdit: true
        )
        #expect(snapshot == .skipPendingLocalEdit)
        #expect(delta == .apply)
    }

    @Test("Envelope round-trips through its compact wire format")
    func envelopeRoundTrip() throws {
        let id = UUID()
        let envelope = WatchSyncEnvelope(
            kind: .delta,
            sentAt: t0,
            records: [record(modifiedAt: t0, id: id)],
            deletedIDs: [UUID()]
        )
        let data = try envelope.encoded()
        let decoded = try #require(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: data]))

        #expect(decoded.kind == .delta)
        #expect(decoded.records.count == 1)
        #expect(decoded.records.first?.id == id)
        #expect(decoded.records.first?.modifiedAt == t0)
        #expect(decoded.deletedIDs == envelope.deletedIDs)
    }

    @Test("Foreign, truncated and wrong-version payloads are rejected as a whole")
    func rejectsBadPayloads() throws {
        #expect(WatchSyncEnvelope.decode(from: [:]) == nil)
        #expect(WatchSyncEnvelope.decode(from: ["unrelated": "value"]) == nil)
        #expect(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: "not data"]) == nil)
        #expect(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: Data()]) == nil)
        #expect(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: Data("{\"v\":2".utf8)]) == nil)

        var future = WatchSyncEnvelope(kind: .delta, sentAt: t0, records: [], deletedIDs: [])
        future.version = WatchSyncEnvelope.currentVersion + 1
        let futureData = try future.encoded()
        #expect(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: futureData]) == nil)

        let valid = try WatchSyncEnvelope(kind: .delta, sentAt: t0, records: [], deletedIDs: []).encoded()
        let truncated = valid.prefix(valid.count / 2)
        #expect(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: Data(truncated)]) == nil)
    }

    @Test("Individual invalid records are dropped while the rest of the envelope survives")
    func dropsInvalidRecords() throws {
        var bogus = record(modifiedAt: t0)
        bogus.painLevel = 42
        let good = record(modifiedAt: t0)
        let envelope = WatchSyncEnvelope(kind: .snapshot, sentAt: t0, records: [bogus, good], deletedIDs: [])
        let decoded = try #require(WatchSyncEnvelope.decode(from: [WatchSyncEnvelope.payloadKey: try envelope.encoded()]))
        #expect(decoded.records.map(\.id) == [good.id])
    }
}
