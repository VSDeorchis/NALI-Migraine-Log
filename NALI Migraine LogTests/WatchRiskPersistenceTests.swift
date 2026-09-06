//
//  WatchRiskPersistenceTests.swift
//  NALI Migraine LogTests
//
//  The Watch keeps the last risk score the phone sent and never invents one:
//  adoption is last-writer-wins on the phone timestamp, persisted payloads
//  round-trip through Data, and old scores are flagged stale rather than
//  silently replaced with 0%.
//

import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("Watch risk persistence")
struct WatchRiskPersistenceTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func payload(percentage: Int = 30, at timestamp: Date) -> WatchRiskPayload {
        let score = MigraineRiskScore(
            overallRisk: Double(percentage) / 100,
            riskLevel: .moderate,
            topFactors: [],
            recommendations: ["Stay hydrated."],
            confidence: 0.55,
            predictionSource: .ruleBased,
            timestamp: timestamp
        )
        return WatchRiskPayload(riskScore: score, now: timestamp)
    }

    // MARK: - Adoption

    @Test("First payload is always adopted")
    func adoptsWhenNothingIsStored() {
        #expect(WatchRiskPayload.shouldAdopt(payload(at: t0), over: nil))
    }

    @Test("Newer and equal timestamps replace the stored score; older ones do not")
    func lastWriterWins() {
        let current = payload(percentage: 30, at: t0)
        let newer = payload(percentage: 45, at: t0.addingTimeInterval(60))
        let same = payload(percentage: 45, at: t0)
        let older = payload(percentage: 10, at: t0.addingTimeInterval(-60))

        #expect(WatchRiskPayload.shouldAdopt(newer, over: current))
        #expect(WatchRiskPayload.shouldAdopt(same, over: current))
        #expect(!WatchRiskPayload.shouldAdopt(older, over: current))
    }

    // MARK: - Persistence round trip

    @Test("Encoded payload decodes to an equal value with its timestamp intact")
    func roundTrip() throws {
        let original = payload(percentage: 62, at: t0)
        let data = try original.encoded()
        let restored = WatchRiskPayload.decode(data)

        #expect(restored == original)
        #expect(restored?.timestamp == t0)
        #expect(restored?.riskPercentage == 62)
    }

    @Test("Corrupt persisted data yields no payload rather than a default score")
    func corruptDataIsRejected() {
        #expect(WatchRiskPayload.decode(Data("not json".utf8)) == nil)
        #expect(WatchRiskPayload.decode(Data()) == nil)
    }

    @Test("Out-of-range persisted values are rejected instead of clamped to 0%")
    func outOfRangeIsRejected() throws {
        var bad = payload(at: t0)
        bad.riskPercentage = 140
        let data = try bad.encoded()
        #expect(WatchRiskPayload.decode(data) == nil)
    }

    // MARK: - Staleness

    @Test("A score is stale only after the six-hour window")
    func staleness() {
        let risk = payload(at: t0)
        #expect(!risk.isStale(at: t0))
        #expect(!risk.isStale(at: t0.addingTimeInterval(WatchRiskPayload.staleAfter)))
        #expect(risk.isStale(at: t0.addingTimeInterval(WatchRiskPayload.staleAfter + 1)))
    }

    @Test("A stale score is still a valid payload — flagged, not discarded")
    func staleRemainsDisplayable() throws {
        let old = payload(percentage: 25, at: t0.addingTimeInterval(-2 * 24 * 3_600))
        let restored = try WatchRiskPayload.decode(old.encoded())
        #expect(restored?.riskPercentage == 25)
        #expect(restored?.isStale(at: t0) == true)
    }
}
