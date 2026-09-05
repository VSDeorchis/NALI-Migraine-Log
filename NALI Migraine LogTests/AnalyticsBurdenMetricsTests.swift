//
//  AnalyticsBurdenMetricsTests.swift
//  NALI Migraine LogTests
//
//  Pure-computation tests for the burden metrics behind the Statistics
//  dashboard: unique headache / acute-medication days, the rolling
//  monthly series, duration median + IQR, symptom prevalence, weekday
//  distribution, data completeness and the baseline-relative tints.
//  Events live in the in-memory preview context; a fixed UTC calendar
//  keeps day boundaries independent of the host timezone.
//

import Testing
import CoreData
import Foundation
@testable import NALI_Migraine_Log

@Suite("Analytics burden metrics", .serialized)
@MainActor
struct AnalyticsBurdenMetricsTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController.preview.container.viewContext
    }

    @discardableResult
    private func event(
        in context: NSManagedObjectContext,
        start: Date,
        durationHours: Double? = nil,
        pain: Int16 = 5,
        medications: Set<MigraineMedication> = [],
        triggers: Set<MigraineTrigger> = [],
        weather: Bool = false,
        configure: (MigraineEvent) -> Void = { _ in }
    ) -> MigraineEvent {
        let e = MigraineEvent(context: context)
        e.id = UUID()
        e.startTime = start
        if let durationHours {
            e.endTime = start.addingTimeInterval(durationHours * 3600)
        }
        e.painLevel = pain
        e.location = "Frontal"
        e.medications = medications
        e.triggers = triggers
        e.hasWeatherData = weather
        configure(e)
        return e
    }

    // MARK: - Unique days

    @Test("Two attacks on one calendar day count as a single headache day")
    func headacheDaysDeduplicatesSameDay() {
        let ctx = makeContext()
        let events = [
            event(in: ctx, start: date(2026, 3, 10, hour: 8)),
            event(in: ctx, start: date(2026, 3, 10, hour: 20)),
            event(in: ctx, start: date(2026, 3, 12)),
        ]
        #expect(events.headacheDays(calendar: calendar) == 2)
        #expect(events.count == 3)
    }

    @Test("Acute-medication days count days, not doses, and ignore untreated attacks")
    func acuteMedicationDaysCountDaysNotDoses() {
        let ctx = makeContext()
        let events = [
            event(in: ctx, start: date(2026, 3, 10, hour: 8), medications: [.ibuprofin, .sumatriptan]),
            event(in: ctx, start: date(2026, 3, 10, hour: 21), medications: [.ibuprofin]),
            event(in: ctx, start: date(2026, 3, 11)),
            event(in: ctx, start: date(2026, 3, 14), medications: [.tylenol]),
        ]
        #expect(events.acuteMedicationDays(calendar: calendar) == 2)
        #expect(events.headacheDays(calendar: calendar) == 3)
    }

    @Test("Empty input yields zero days and no duration spread")
    func emptyInput() {
        let events: [MigraineEvent] = []
        #expect(events.headacheDays(calendar: calendar) == 0)
        #expect(events.acuteMedicationDays(calendar: calendar) == 0)
        #expect(events.durationSpread == nil)
        #expect(events.dataCompleteness.overallShare == 0)
    }

    // MARK: - Monthly series

    @Test("Monthly series spans monthsBack+1 months, oldest first, with zero-filled gaps")
    func monthlySeriesShape() {
        let ctx = makeContext()
        let now = date(2026, 6, 15)
        let events = [
            event(in: ctx, start: date(2026, 6, 1)),
            event(in: ctx, start: date(2026, 6, 1, hour: 22)),   // same day
            event(in: ctx, start: date(2026, 4, 3)),
            event(in: ctx, start: date(2025, 12, 31)),           // outside 5-month window
        ]
        let series = events.monthlyHeadacheDays(monthsBack: 5, now: now, calendar: calendar)
        #expect(series.count == 6)
        #expect(series.first?.month == date(2026, 1, 1, hour: 0))
        #expect(series.last?.month == date(2026, 6, 1, hour: 0))
        #expect(series.map(\.count) == [0, 0, 0, 1, 0, 1])
    }

    @Test("Monthly medication-days series only counts treated days")
    func monthlyMedicationSeries() {
        let ctx = makeContext()
        let now = date(2026, 6, 15)
        let events = [
            event(in: ctx, start: date(2026, 6, 2), medications: [.ibuprofin]),
            event(in: ctx, start: date(2026, 6, 2, hour: 23), medications: [.naproxen]),
            event(in: ctx, start: date(2026, 6, 5)),
            event(in: ctx, start: date(2026, 5, 9), medications: [.sumatriptan]),
        ]
        let series = events.monthlyAcuteMedicationDays(monthsBack: 1, now: now, calendar: calendar)
        #expect(series.map(\.count) == [1, 1])
        #expect(series.averageCount == 1)
    }

    // MARK: - Duration spread

    @Test("Median and quartiles interpolate linearly and ignore open-ended entries")
    func durationSpread() {
        let ctx = makeContext()
        let events = [
            event(in: ctx, start: date(2026, 1, 1), durationHours: 1),
            event(in: ctx, start: date(2026, 1, 2), durationHours: 2),
            event(in: ctx, start: date(2026, 1, 3), durationHours: 3),
            event(in: ctx, start: date(2026, 1, 4), durationHours: 4),
            event(in: ctx, start: date(2026, 1, 5), durationHours: 10),
            event(in: ctx, start: date(2026, 1, 6)),                    // no end time
        ]
        let spread = events.durationSpread
        #expect(spread?.sampleCount == 5)
        #expect(spread?.median == 10_800.0)
        #expect(spread?.lowerQuartile == 7_200.0)
        #expect(spread?.upperQuartile == 14_400.0)
        #expect(spread?.interquartileRange == 7_200.0)
    }

    @Test("Even sample counts interpolate the median between the middle two values")
    func durationSpreadEvenCount() {
        let ctx = makeContext()
        let events = [
            event(in: ctx, start: date(2026, 1, 1), durationHours: 2),
            event(in: ctx, start: date(2026, 1, 2), durationHours: 4),
        ]
        #expect(events.durationSpread?.median == 10_800.0)
    }

    @Test("End times before the start are discarded")
    func durationSpreadIgnoresNegativeDurations() {
        let ctx = makeContext()
        let e = event(in: ctx, start: date(2026, 1, 1))
        e.endTime = date(2025, 12, 31)
        #expect([e].durationSpread == nil)
    }

    // MARK: - Symptoms

    @Test("Symptom prevalence covers every symptom, merges nausea/vomiting, sorts by count")
    func symptomPrevalence() {
        let ctx = makeContext()
        let events = [
            event(in: ctx, start: date(2026, 1, 1)) { $0.hasNausea = true; $0.hasPhotophobia = true },
            event(in: ctx, start: date(2026, 1, 2)) { $0.hasVomiting = true; $0.hasPhotophobia = true },
            event(in: ctx, start: date(2026, 1, 3)) { $0.hasNausea = true; $0.hasVomiting = true },
            event(in: ctx, start: date(2026, 1, 4)) { $0.hasAura = true },
        ]
        let prevalence = events.symptomPrevalence
        #expect(prevalence.count == MigraineSymptom.allCases.count)
        #expect(prevalence.first?.symptom == .nauseaOrVomiting)
        #expect(prevalence.first?.count == 3)
        #expect(prevalence.first?.share == 0.75)
        let photophobia = prevalence.first { $0.symptom == .photophobia }
        #expect(photophobia?.count == 2)
        #expect(photophobia?.share == 0.5)
        #expect(prevalence.first { $0.symptom == .tinnitus }?.count == 0)
    }

    // MARK: - Weekday

    @Test("Weekday distribution starts on the calendar's first weekday and counts onsets")
    func weekdayDistribution() {
        let ctx = makeContext()
        // 2026-03-01 is a Sunday; 2026-03-02 a Monday.
        let events = [
            event(in: ctx, start: date(2026, 3, 1)),
            event(in: ctx, start: date(2026, 3, 2)),
            event(in: ctx, start: date(2026, 3, 9)),
        ]
        let points = events.weekdayDistribution(calendar: calendar)
        #expect(points.count == 7)
        #expect(points.map(\.weekday) == [1, 2, 3, 4, 5, 6, 7])
        #expect(points[0].count == 1)
        #expect(points[1].count == 2)
        #expect(points[2...].allSatisfy { $0.count == 0 })

        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        #expect(events.weekdayDistribution(calendar: mondayFirst).map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
    }

    // MARK: - Completeness

    @Test("Completeness shares reflect each optional detail and average to the overall share")
    func dataCompleteness() {
        let ctx = makeContext()
        let events = [
            event(in: ctx, start: date(2026, 1, 1), durationHours: 2, medications: [.ibuprofin], triggers: [.stress], weather: true),
            event(in: ctx, start: date(2026, 1, 2), durationHours: 3),
            event(in: ctx, start: date(2026, 1, 3), triggers: [.caffeine]),
            event(in: ctx, start: date(2026, 1, 4)),
        ]
        let c = events.dataCompleteness
        #expect(c.total == 4)
        #expect(c.endTimeShare == 0.5)
        #expect(c.weatherShare == 0.25)
        #expect(c.triggerShare == 0.5)
        #expect(c.medicationShare == 0.25)
        #expect(abs(c.overallShare - 0.375) < 0.0001)
    }

    // MARK: - Tints and bands

    @Test("Monthly tone is relative to the user's own average")
    func monthlyTone() {
        #expect(MonthlyTone.tone(count: 2, average: 4) == .below)
        #expect(MonthlyTone.tone(count: 3, average: 4) == .below)   // 0.75 boundary
        #expect(MonthlyTone.tone(count: 4, average: 4) == .near)
        #expect(MonthlyTone.tone(count: 5, average: 4) == .above)   // 1.25 boundary
        #expect(MonthlyTone.tone(count: 0, average: 0) == .near)
        #expect(MonthlyTone.tone(count: 1, average: 0) == .above)
    }

    @Test("Acute-medication bands switch at the 10- and 15-day reference marks")
    func medicationBands() {
        #expect(AcuteMedicationBand.band(daysPerMonth: 0) == .low)
        #expect(AcuteMedicationBand.band(daysPerMonth: 9.9) == .low)
        #expect(AcuteMedicationBand.band(daysPerMonth: 10) == .moderate)
        #expect(AcuteMedicationBand.band(daysPerMonth: 14.9) == .moderate)
        #expect(AcuteMedicationBand.band(daysPerMonth: 15) == .frequent)
    }
}
