//
//  CycleAssociationAnalysisTests.swift
//  NALI Migraine LogTests
//
//  Pure-function tests for the denominator-aware perimenstrual
//  association (`CycleAssociationAnalysis`): observed-day denominators,
//  rate ratio, confidence tiers, the "n of your last m cycles"
//  indicator, the severity split, the cycle-aligned series and the
//  wording guardrails. Fixed UTC calendar; `now` is pinned so the
//  coverage window never depends on the wall clock.
//

import Testing
import Foundation
@testable import NALI_Migraine_Log

@Suite("CycleAssociationAnalysis")
struct CycleAssociationAnalysisTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func sample(_ date: Date, pain: Int = 5) -> CycleMigraineSample {
        CycleMigraineSample(onset: date, painLevel: pain)
    }

    /// Six 28-day cycles starting 2026-01-01; window covers all of them
    /// and `now` is after the last window closes.
    private var sixCycleStarts: [Date] {
        (0..<6).map { calendar.date(byAdding: .day, value: 28 * $0, to: day(2026, 1, 1, hour: 0))! }
    }

    private var sixCycleWindow: DateInterval {
        DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 6, 20, hour: 0))
    }

    private var sixCycleNow: Date { day(2026, 6, 30) }

    // MARK: - Denominators

    @Test("Observed days are split into perimenstrual and other with a full-window denominator")
    func denominatorsCoverEveryObservedDay() throws {
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: [],
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        // Coverage: Jan 1 (first start; the -2 days fall before the window)
        // through Jun 19 inclusive = 170 days. Last start is May 21, so no
        // day exceeds the 45-day gap.
        #expect(association.perimenstrualDaysObserved + association.otherDaysObserved == 170)
        // Six starts × 5-day window, minus the two pre-window days of cycle 1.
        #expect(association.perimenstrualDaysObserved == 6 * 5 - 2)
        #expect(association.cycleCount == 6)
        #expect(association.migraineDayCount == 0)
    }

    @Test("Days more than 45 days after the last logged start are not observed")
    func coverageGapExcludesStaleDays() throws {
        let starts = [day(2026, 1, 1, hour: 0)]
        let window = DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 4, 1, hour: 0))
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: [sample(day(2026, 3, 20))],   // 78 days after → unknown context
            cycleStarts: starts,
            window: window,
            now: day(2026, 4, 5),
            calendar: calendar
        ))
        // Jan 1 ... Feb 15 (gap 45) inclusive = 46 observed days.
        #expect(association.perimenstrualDaysObserved + association.otherDaysObserved == 46)
        #expect(association.migraineDayCount == 0)
    }

    @Test("Future days are never observed even when the window extends past today")
    func futureDaysExcluded() throws {
        let starts = [day(2026, 1, 1, hour: 0)]
        let window = DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 2, 1, hour: 0))
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: [],
            cycleStarts: starts,
            window: window,
            now: day(2026, 1, 10),
            calendar: calendar
        ))
        #expect(association.perimenstrualDaysObserved + association.otherDaysObserved == 10)
    }

    @Test("No logged starts or no overlap with the window yields nil")
    func nilWhenNothingObservable() {
        #expect(CycleAssociationAnalysis.compute(
            samples: [sample(day(2026, 1, 5))],
            cycleStarts: [],
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ) == nil)

        #expect(CycleAssociationAnalysis.compute(
            samples: [],
            cycleStarts: [day(2026, 9, 1)],
            window: DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 2, 1, hour: 0)),
            now: day(2026, 10, 1),
            calendar: calendar
        ) == nil)
    }

    // MARK: - Rates and ratio

    @Test("Rate ratio compares migraine-day rates, not raw shares")
    func rateRatio() throws {
        // One migraine on day 0 of each cycle (6 peri days) and 6 spread
        // across other days.
        var samples = sixCycleStarts.map { sample($0.addingTimeInterval(3600 * 10)) }
        samples += (0..<6).map { sample(calendar.date(byAdding: .day, value: 28 * $0 + 14, to: day(2026, 1, 1))!) }

        let association = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(association.perimenstrualMigraineDays == 6)
        #expect(association.otherMigraineDays == 6)
        #expect(association.migraineDayCount == 12)

        let periRate = 6.0 / Double(association.perimenstrualDaysObserved)
        let otherRate = 6.0 / Double(association.otherDaysObserved)
        let ratio = try #require(association.rateRatio)
        #expect(abs(ratio - periRate / otherRate) < 0.0001)
        #expect(ratio > 4)   // 6/28 vs 6/142
        #expect(association.headline.contains("more likely"))
        #expect(association.headline.contains("×"))
    }

    @Test("Two attacks on one day count as a single migraine day in both cohorts")
    func sameDayAttacksDeduplicated() throws {
        let start = day(2026, 1, 1, hour: 0)
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: [sample(day(2026, 1, 1, hour: 8)), sample(day(2026, 1, 1, hour: 20)),
                      sample(day(2026, 1, 15, hour: 8)), sample(day(2026, 1, 15, hour: 21))],
            cycleStarts: [start],
            window: DateInterval(start: start, end: day(2026, 2, 1, hour: 0)),
            now: day(2026, 2, 5),
            calendar: calendar
        ))
        #expect(association.perimenstrualMigraineDays == 1)
        #expect(association.otherMigraineDays == 1)
        #expect(association.perimenstrualAttackCount == 2)
        #expect(association.otherAttackCount == 2)
    }

    @Test("Ratio is nil when nothing fell outside the window and the headline says so in words")
    func infiniteRatioReportedInWords() throws {
        let samples = sixCycleStarts.map { sample($0.addingTimeInterval(3600 * 9)) }
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(association.rateRatio == nil)
        #expect(association.confidence == .consistent)
        #expect(association.headline == "Every migraine day fell in the 5 days around the start of your period")
    }

    @Test("Near-1 ratios read as 'about as likely'")
    func neutralHeadline() throws {
        // 1 peri migraine day per cycle (6 of 28 peri days ≈ 0.21) and
        // ~0.21 on other days: 30 of 142 other days.
        var samples = sixCycleStarts.map { sample($0.addingTimeInterval(3600 * 9)) }
        for cycle in 0..<6 {
            for offset in [5, 8, 11, 14, 17] {
                samples.append(sample(calendar.date(byAdding: .day, value: 28 * cycle + offset, to: day(2026, 1, 1))!))
            }
        }
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        let ratio = try #require(association.rateRatio)
        #expect(ratio > 0.8 && ratio < 1.2)
        #expect(association.headline == "Migraines were about as likely around your period as on other days")
    }

    // MARK: - Confidence tiers

    @Test("Fewer than 3 cycles or 5 migraine days is insufficient and hides the ratio headline")
    func insufficientTier() throws {
        let twoStarts = Array(sixCycleStarts.prefix(2))
        let window = DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 2, 20, hour: 0))
        let few = try #require(CycleAssociationAnalysis.compute(
            samples: (0..<8).map { sample(calendar.date(byAdding: .day, value: $0 * 5, to: day(2026, 1, 2))!) },
            cycleStarts: twoStarts,
            window: window,
            now: day(2026, 3, 1),
            calendar: calendar
        ))
        #expect(few.cycleCount == 2)
        #expect(few.confidence == .insufficient)
        #expect(few.headline == "Pattern emerging — keep logging")

        let fewDays = try #require(CycleAssociationAnalysis.compute(
            samples: [sample(day(2026, 1, 1)), sample(day(2026, 2, 10))],
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(fewDays.cycleCount == 6)
        #expect(fewDays.migraineDayCount == 2)
        #expect(fewDays.confidence == .insufficient)
    }

    @Test("3–5 cycles is 'early', 6+ is 'consistent'")
    func tiers() throws {
        let samples = (0..<6).map { sample(calendar.date(byAdding: .day, value: $0 * 9, to: day(2026, 1, 2))!) }

        let three = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: Array(sixCycleStarts.prefix(3)),
            window: DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 3, 20, hour: 0)),
            now: day(2026, 4, 1),
            calendar: calendar
        ))
        #expect(three.cycleCount == 3)
        #expect(three.confidence == .early)

        let six = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(six.confidence == .consistent)
        #expect(CycleConfidence.consistent.title == "Consistent pattern")
    }

    // MARK: - Recent cycles indicator

    @Test("Recent-cycle indicator evaluates up to the last 3 fully observed cycles")
    func recentCycles() throws {
        // Migraine in the window of cycles 4 and 6 only (0-based 3 and 5).
        let samples = [3, 5].map { sample(sixCycleStarts[$0].addingTimeInterval(3600 * 9)) }
            + (0..<4).map { sample(calendar.date(byAdding: .day, value: 10 + $0 * 28, to: day(2026, 1, 1))!) }
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(association.recentCyclesEvaluated == 3)
        #expect(association.recentCyclesWithPerimenstrualMigraine == 2)
        #expect(association.recentCyclesSummary == "A migraine started in the perimenstrual window in 2 of your last 3 cycles")
    }

    @Test("A cycle whose window is not fully observed is skipped by the indicator")
    func recentCyclesSkipPartialWindow() throws {
        // `now` lands on day +1 of the last start, so its +2 day is unobserved.
        let lastStart = sixCycleStarts[5]
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: [],
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: calendar.date(byAdding: .day, value: 1, to: lastStart)!,
            calendar: calendar
        ))
        #expect(association.recentCyclesEvaluated == 3)
        #expect(association.cycleCount == 6)
    }

    // MARK: - Severity split

    @Test("Severity comparison needs at least 3 attacks in each cohort")
    func severityComparison() throws {
        let peri = sixCycleStarts.prefix(3).map { sample($0.addingTimeInterval(3600 * 9), pain: 8) }
        let other = (0..<3).map { sample(calendar.date(byAdding: .day, value: 14 + $0 * 28, to: day(2026, 1, 1))!, pain: 4) }
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: peri + other,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(association.hasSeverityComparison)
        #expect(association.perimenstrualMeanPain == 8)
        #expect(association.otherMeanPain == 4)

        let thin = try #require(CycleAssociationAnalysis.compute(
            samples: Array(peri.prefix(2)) + other,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(thin.hasSeverityComparison == false)
    }

    // MARK: - Aligned series

    @Test("Aligned series covers −7…+7 with per-offset denominators and flags the window")
    func alignedSeries() throws {
        let samples = sixCycleStarts.map { sample(calendar.date(byAdding: .day, value: -1, to: $0)!) }
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        #expect(association.aligned.map(\.offset) == Array(-7...7))

        let minusOne = try #require(association.aligned.first { $0.offset == -1 })
        // Cycle 1's day −1 (Dec 31) is outside the window → 5 observed.
        #expect(minusOne.observedDays == 5)
        #expect(minusOne.migraineDays == 5)
        #expect(minusOne.rate == 1)
        #expect(minusOne.isPerimenstrual)

        let zero = try #require(association.aligned.first { $0.offset == 0 })
        #expect(zero.observedDays == 6)
        #expect(zero.migraineDays == 0)

        let plusSeven = try #require(association.aligned.first { $0.offset == 7 })
        #expect(plusSeven.observedDays == 6)
        #expect(plusSeven.isPerimenstrual == false)

        #expect(CycleAlignedPoint(offset: 3, migraineDays: 0, observedDays: 0).rate == nil)
    }

    @Test("Predicted starts never feed the association")
    func predictionsIgnored() throws {
        // Three regular cycles, then a migraine on the day the *next*
        // (unlogged) start would be predicted: it must count as "other".
        let starts = Array(sixCycleStarts.prefix(3))
        let predictedNext = calendar.date(byAdding: .day, value: 28 * 3, to: day(2026, 1, 1))!
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: [sample(predictedNext)],
            cycleStarts: starts,
            window: DateInterval(start: day(2026, 1, 1, hour: 0), end: day(2026, 4, 10, hour: 0)),
            now: day(2026, 4, 10),
            calendar: calendar
        ))
        #expect(association.perimenstrualMigraineDays == 0)
        #expect(association.otherMigraineDays == 1)
    }

    // MARK: - Wording guardrails

    @Test("Headlines never assert a menstrual-migraine diagnosis")
    func headlinesAreNonDiagnostic() throws {
        var samples = sixCycleStarts.map { sample($0.addingTimeInterval(3600 * 9)) }
        samples += (0..<3).map { sample(calendar.date(byAdding: .day, value: 28 * $0 + 14, to: day(2026, 1, 1))!) }
        let association = try #require(CycleAssociationAnalysis.compute(
            samples: samples,
            cycleStarts: sixCycleStarts,
            window: sixCycleWindow,
            now: sixCycleNow,
            calendar: calendar
        ))
        for text in [association.headline, association.recentCyclesSummary ?? ""] {
            #expect(!text.lowercased().contains("menstrual migraine"))
            #expect(!text.lowercased().contains("diagnos"))
            #expect(!text.lowercased().contains("caused"))
        }
    }
}
