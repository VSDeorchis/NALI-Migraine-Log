//
//  MenstrualCycleInsightsTests.swift
//  NALI Migraine LogTests
//
//  Pure-function tests for the cycle-aware gating (`CycleEligibility`)
//  and the perimenstrual window math (`PerimenstrualWindow`). A fixed
//  UTC calendar keeps the day arithmetic independent of the host
//  timezone.
//

import Testing
import Foundation
import SwiftUI
@testable import NALI_Migraine_Log

@Suite("MenstrualCycleInsights")
struct MenstrualCycleInsightsTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Eligibility

    @Test("Male biological sex never allows cycle insights, even with history")
    func maleExcluded() {
        #expect(CycleEligibility.excluded.allowsCycleInsights(hasMenstrualHistory: true) == false)
        #expect(CycleEligibility.excluded.allowsCycleInsights(hasMenstrualHistory: false) == false)
    }

    @Test("Female biological sex allows cycle insights regardless of history")
    func femaleEligible() {
        #expect(CycleEligibility.eligible.allowsCycleInsights(hasMenstrualHistory: false))
        #expect(CycleEligibility.eligible.allowsCycleInsights(hasMenstrualHistory: true))
    }

    @Test("Unknown biological sex requires real menstrual history")
    func undeterminedNeedsHistory() {
        #expect(CycleEligibility.undetermined.allowsCycleInsights(hasMenstrualHistory: false) == false)
        #expect(CycleEligibility.undetermined.allowsCycleInsights(hasMenstrualHistory: true))
    }

    // MARK: - Cycle length estimation

    @Test("Implausible gaps are treated as tracking gaps, not cycles")
    func cycleLengthsFilterImplausibleGaps() {
        let starts = [
            day(2026, 1, 1),
            day(2026, 1, 29),   // 28
            day(2026, 4, 1),    // 62 — gap in tracking
            day(2026, 5, 1),    // 30
            day(2026, 5, 10),   // 9 — spotting / bad data
        ]
        #expect(PerimenstrualWindow.cycleLengths(cycleStarts: starts, calendar: calendar) == [28, 30])
    }

    @Test("Typical cycle length is the median and needs two usable intervals")
    func typicalCycleLength() {
        let one = [day(2026, 1, 1), day(2026, 1, 29)]
        #expect(PerimenstrualWindow.typicalCycleLength(cycleStarts: one, calendar: calendar) == nil)

        let odd = [day(2026, 1, 1), day(2026, 1, 27), day(2026, 2, 26), day(2026, 3, 25)] // 26, 30, 27
        #expect(PerimenstrualWindow.typicalCycleLength(cycleStarts: odd, calendar: calendar) == 27)

        let even = [day(2026, 1, 1), day(2026, 1, 29), day(2026, 2, 28)] // 28, 30
        #expect(PerimenstrualWindow.typicalCycleLength(cycleStarts: even, calendar: calendar) == 29)
    }

    @Test("Predicted next start is last start plus typical length")
    func predictedNextStart() {
        let starts = [day(2026, 1, 1), day(2026, 1, 29), day(2026, 2, 26)] // 28, 28
        let predicted = PerimenstrualWindow.predictedNextStart(cycleStarts: starts, calendar: calendar)
        #expect(predicted == day(2026, 3, 26))
        #expect(PerimenstrualWindow.predictedNextStart(cycleStarts: [day(2026, 1, 1)], calendar: calendar) == nil)
    }

    // MARK: - Day offsets

    @Test("Offsets −2…+2 around a logged start; outside is nil")
    func offsetsAroundLoggedStart() {
        let starts = [day(2026, 3, 10)]
        let offsets: [Int: Int] = [7: -3, 8: -2, 9: -1, 10: 0, 11: 1, 12: 2, 13: 3]
        for (d, offset) in offsets {
            let result = PerimenstrualWindow.dayOffset(for: day(2026, 3, d, hour: 15), cycleStarts: starts, calendar: calendar)
            let expected: Int? = (-2...2).contains(offset) ? offset : nil
            #expect(result == expected, "day \(d)")
        }
    }

    @Test("Empty cycle history yields no offset")
    func emptyHistory() {
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 10), cycleStarts: [], calendar: calendar) == nil)
    }

    @Test("Nearest start wins when two starts bracket a date")
    func nearestStartWins() {
        // Two starts 4 days apart (unrealistic, but exercises tie-breaking).
        let starts = [day(2026, 3, 10), day(2026, 3, 14)]
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 11), cycleStarts: starts, calendar: calendar) == 1)
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 13), cycleStarts: starts, calendar: calendar) == -1)
    }

    @Test("Days before a predicted next start are flagged once history is thick enough")
    func predictedWindowAfterLastStart() {
        let starts = [day(2026, 1, 1), day(2026, 1, 29), day(2026, 2, 26)] // predicts 2026-03-26
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 24), cycleStarts: starts, calendar: calendar) == -2)
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 26), cycleStarts: starts, calendar: calendar) == 0)
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 20), cycleStarts: starts, calendar: calendar) == nil)
    }

    @Test("No prediction with a single logged start")
    func noPredictionWithThinHistory() {
        let starts = [day(2026, 2, 26)]
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 25), cycleStarts: starts, calendar: calendar) == nil)
    }

    @Test("Historical dates are never tagged from a prediction")
    func noBackwardPrediction() {
        // Tracking gap between Jan 29 and Apr 1: the missing ~Feb 26 and
        // ~Mar 26 starts must not be inferred.
        let starts = [day(2026, 1, 1), day(2026, 1, 29), day(2026, 4, 1), day(2026, 4, 29)]
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 2, 26), cycleStarts: starts, calendar: calendar) == nil)
        #expect(PerimenstrualWindow.dayOffset(for: day(2026, 3, 26), cycleStarts: starts, calendar: calendar) == nil)
    }

    // MARK: - Feature vector

    @Test("Cycle starts in the health snapshot drive the perimenstrual feature for any reference date")
    func featureVectorUsesCycleStarts() {
        // Use the extractor's own calendar (Calendar.current) so the
        // day arithmetic matches regardless of host timezone.
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let reference = cal.date(byAdding: .day, value: 1, to: start)!
        let farAway = cal.date(byAdding: .day, value: 10, to: start)!

        let health = HealthKitSnapshot(cycleStarts: [start])
        let extractor = FeatureExtractor()

        let inWindow = extractor.extractFeatures(migraines: [], currentWeather: nil, healthData: health, referenceDate: reference)
        #expect(inWindow.perimenstrualDayOffset == 1)
        #expect(inWindow.toDictionary()["isPerimenstrual"] as? Int == 1)

        let outside = extractor.extractFeatures(migraines: [], currentWeather: nil, healthData: health, referenceDate: farAway)
        #expect(outside.perimenstrualDayOffset == nil)
        #expect(outside.toDictionary()["isPerimenstrual"] as? Int == 0)

        let noCycle = extractor.extractFeatures(migraines: [], currentWeather: nil, healthData: HealthKitSnapshot(), referenceDate: reference)
        #expect(noCycle.perimenstrualDayOffset == nil)
    }

    // MARK: - Watch payload

    @Test("Sensitive risk factors and recommendations never reach the Watch payload")
    func watchPayloadStripsSensitiveContext() {
        let score = MigraineRiskScore(
            overallRisk: 0.42,
            riskLevel: .moderate,
            topFactors: [
                RiskFactor(name: "Perimenstrual Window", contribution: 0.15, icon: "drop.fill",
                           color: .pink, detail: PerimenstrualWindow.riskDetail(forOffset: 0), isSensitive: true),
                RiskFactor(name: "Poor Sleep", contribution: 0.12, icon: "bed.double.fill",
                           color: .indigo, detail: "4h last night"),
            ],
            recommendations: [PerimenstrualWindow.recommendation, "Prioritize sleep tonight."],
            confidence: 0.6,
            predictionSource: .ruleBased,
            timestamp: Date()
        )

        let payload = WatchRiskPayload(riskScore: score)
        #expect(payload.riskPercentage == 42)
        #expect(payload.factors.map(\.name) == ["Poor Sleep"])
        #expect(payload.recommendations == ["Prioritize sleep tonight."])
    }

    // MARK: - Copy

    @Test("Labels describe timing without asserting causation")
    func labels() {
        #expect(PerimenstrualWindow.shortLabel(forOffset: -2) == "2 days before period")
        #expect(PerimenstrualWindow.shortLabel(forOffset: -1) == "Day before period")
        #expect(PerimenstrualWindow.shortLabel(forOffset: 0) == "Period started")
        #expect(PerimenstrualWindow.shortLabel(forOffset: 2) == "Day 3 of period")
        #expect(PerimenstrualWindow.riskDetail(forOffset: -1).contains("expected tomorrow"))
        #expect(PerimenstrualWindow.riskDetail(forOffset: 0).contains("started today"))
        #expect(PerimenstrualWindow.sensitiveRecommendations.contains(PerimenstrualWindow.recommendation))
    }
}
