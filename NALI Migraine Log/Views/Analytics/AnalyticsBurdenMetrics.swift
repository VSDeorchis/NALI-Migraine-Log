//
//  AnalyticsBurdenMetrics.swift
//  NALI Migraine Log
//
//  Pure, Foundation-only calculations behind the modernised Analytics
//  dashboard: headache *days* (the unit clinicians use, as opposed to
//  attack counts), acute-medication days, duration spread, symptom
//  prevalence, weekday distribution and a data-completeness score.
//  Everything here is synchronous and side-effect free so it can be
//  unit-tested without HealthKit or SwiftUI.
//

import Foundation

// MARK: - Models

/// Median and interquartile range of completed attack durations.
struct DurationSpread: Equatable {
    let median: TimeInterval
    let lowerQuartile: TimeInterval
    let upperQuartile: TimeInterval
    let sampleCount: Int

    var interquartileRange: TimeInterval { upperQuartile - lowerQuartile }
}

/// Associated symptoms captured as booleans on `MigraineEvent`.
/// Nausea and vomiting are folded together to mirror ICHD-3 wording.
enum MigraineSymptom: String, CaseIterable, Identifiable, Hashable {
    case aura
    case nauseaOrVomiting
    case photophobia
    case phonophobia
    case vertigo
    case tinnitus
    case wakeUpHeadache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aura:             return "Aura"
        case .nauseaOrVomiting: return "Nausea / vomiting"
        case .photophobia:      return "Light sensitivity"
        case .phonophobia:      return "Sound sensitivity"
        case .vertigo:          return "Vertigo"
        case .tinnitus:         return "Tinnitus"
        case .wakeUpHeadache:   return "Woke with headache"
        }
    }

    var systemImage: String {
        switch self {
        case .aura:             return "sparkles"
        case .nauseaOrVomiting: return "allergens"
        case .photophobia:      return "sun.max.fill"
        case .phonophobia:      return "speaker.wave.3.fill"
        case .vertigo:          return "tornado"
        case .tinnitus:         return "ear.fill"
        case .wakeUpHeadache:   return "alarm.fill"
        }
    }
}

struct SymptomPrevalencePoint: Identifiable, Equatable {
    var id: MigraineSymptom { symptom }
    let symptom: MigraineSymptom
    let count: Int
    /// 0...1 share of the entries in the period reporting the symptom.
    let share: Double
}

/// Attack count per weekday, in the calendar's first-day-of-week order.
struct WeekdayPoint: Identifiable, Equatable {
    var id: Int { weekday }
    /// 1 = Sunday, matching `Calendar.Component.weekday`.
    let weekday: Int
    let name: String
    let count: Int
}

/// How much optional detail the entries in a period carry. Drives the
/// "data completeness" footer so users can judge how much weight to
/// give the derived patterns.
struct DataCompleteness: Equatable {
    let total: Int
    let withEndTime: Int
    let withWeather: Int
    let withTriggers: Int
    let withMedications: Int

    var endTimeShare: Double { share(withEndTime) }
    var weatherShare: Double { share(withWeather) }
    var triggerShare: Double { share(withTriggers) }
    var medicationShare: Double { share(withMedications) }

    /// Mean of the four component shares, 0...1.
    var overallShare: Double {
        guard total > 0 else { return 0 }
        return (endTimeShare + weatherShare + triggerShare + medicationShare) / 4
    }

    private func share(_ value: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }
}

/// Baseline-relative tint for a monthly bar: compared with the user's
/// own average rather than a fixed "5 is fine, 9 is bad" scale.
enum MonthlyTone: Equatable {
    case below
    case near
    case above

    static func tone(count: Int, average: Double) -> MonthlyTone {
        guard average > 0 else { return count == 0 ? .near : .above }
        let ratio = Double(count) / average
        if ratio <= 0.75 { return .below }
        if ratio >= 1.25 { return .above }
        return .near
    }
}

/// Reference bands for acute-medication days in a 30-day month. The
/// thresholds mirror the day counts ICHD-3 uses when *describing*
/// frequent acute medication use; the app only reports them as context
/// and never labels a user with medication-overuse headache.
enum AcuteMedicationBand: Equatable {
    case low
    case moderate
    case frequent

    static let moderateThreshold = 10
    static let frequentThreshold = 15

    static func band(daysPerMonth: Double) -> AcuteMedicationBand {
        if daysPerMonth >= Double(frequentThreshold) { return .frequent }
        if daysPerMonth >= Double(moderateThreshold) { return .moderate }
        return .low
    }
}

// MARK: - Computations

extension Array where Element == MigraineEvent {

    /// Unique calendar days with at least one logged attack.
    func headacheDays(calendar: Calendar = .current) -> Int {
        Set(compactMap { migraine -> Date? in
            guard let start = migraine.startTime else { return nil }
            return calendar.startOfDay(for: start)
        }).count
    }

    /// Unique calendar days on which at least one acute medication was
    /// taken. Multiple doses (or attacks) on the same day count once.
    func acuteMedicationDays(calendar: Calendar = .current) -> Int {
        Set(compactMap { migraine -> Date? in
            guard let start = migraine.startTime,
                  !migraine.medications.isEmpty else { return nil }
            return calendar.startOfDay(for: start)
        }).count
    }

    /// Rolling monthly series of unique headache days.
    func monthlyHeadacheDays(
        monthsBack: Int = 11,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MonthlyPoint] {
        monthlyUniqueDays(monthsBack: monthsBack, now: now, calendar: calendar) { _ in true }
    }

    /// Rolling monthly series of unique acute-medication days.
    func monthlyAcuteMedicationDays(
        monthsBack: Int = 11,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MonthlyPoint] {
        monthlyUniqueDays(monthsBack: monthsBack, now: now, calendar: calendar) {
            !$0.medications.isEmpty
        }
    }

    private func monthlyUniqueDays(
        monthsBack: Int,
        now: Date,
        calendar: Calendar,
        include: (MigraineEvent) -> Bool
    ) -> [MonthlyPoint] {
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let windowStart = calendar.date(byAdding: .month, value: -monthsBack, to: currentMonthStart)
            ?? currentMonthStart
        let windowEnd = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? now

        var daysByMonth: [Date: Set<Date>] = [:]
        var cursor = windowStart
        while cursor < windowEnd {
            daysByMonth[cursor] = []
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        for migraine in self where include(migraine) {
            guard let date = migraine.startTime,
                  date >= windowStart, date < windowEnd,
                  let monthStart = calendar.date(
                      from: calendar.dateComponents([.year, .month], from: date)
                  ) else { continue }
            daysByMonth[monthStart, default: []].insert(calendar.startOfDay(for: date))
        }

        return daysByMonth
            .map { MonthlyPoint(month: $0.key, count: $0.value.count) }
            .sorted { $0.month < $1.month }
    }

    /// Median and quartiles of completed attack durations, or `nil`
    /// when nothing in the period has an end time.
    var durationSpread: DurationSpread? {
        let durations = compactMap { migraine -> TimeInterval? in
            guard let start = migraine.startTime, let end = migraine.endTime,
                  end > start else { return nil }
            return end.timeIntervalSince(start)
        }.sorted()
        guard !durations.isEmpty else { return nil }
        return DurationSpread(
            median: Self.percentile(durations, 0.5),
            lowerQuartile: Self.percentile(durations, 0.25),
            upperQuartile: Self.percentile(durations, 0.75),
            sampleCount: durations.count
        )
    }

    /// Linear-interpolated percentile of an ascending-sorted array.
    private static func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        if lower == upper { return lower == sorted.count - 1 ? last : sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Share of entries reporting each associated symptom, sorted by
    /// prevalence. Always includes every symptom so charts stay stable.
    var symptomPrevalence: [SymptomPrevalencePoint] {
        let total = count
        return MigraineSymptom.allCases.map { symptom in
            let matches = filter { $0.has(symptom) }.count
            return SymptomPrevalencePoint(
                symptom: symptom,
                count: matches,
                share: total > 0 ? Double(matches) / Double(total) : 0
            )
        }
        .sorted { $0.count > $1.count }
    }

    /// Attack count per weekday, ordered from the calendar's first
    /// weekday so the chart reads Mon…Sun or Sun…Sat per locale.
    func weekdayDistribution(calendar: Calendar = .current) -> [WeekdayPoint] {
        var counts: [Int: Int] = [:]
        for migraine in self {
            guard let start = migraine.startTime else { continue }
            counts[calendar.component(.weekday, from: start), default: 0] += 1
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (0..<7).map { index in
            let weekday = ((calendar.firstWeekday - 1 + index) % 7) + 1
            return WeekdayPoint(
                weekday: weekday,
                name: symbols[Swift.min(weekday - 1, symbols.count - 1)],
                count: counts[weekday] ?? 0
            )
        }
    }

    /// How many entries carry each optional detail.
    var dataCompleteness: DataCompleteness {
        DataCompleteness(
            total: count,
            withEndTime: filter { $0.endTime != nil }.count,
            withWeather: filter { $0.hasWeatherData }.count,
            withTriggers: filter { !$0.triggers.isEmpty }.count,
            withMedications: filter { !$0.medications.isEmpty }.count
        )
    }
}

extension MigraineEvent {
    func has(_ symptom: MigraineSymptom) -> Bool {
        switch symptom {
        case .aura:             return hasAura
        case .nauseaOrVomiting: return hasNausea || hasVomiting
        case .photophobia:      return hasPhotophobia
        case .phonophobia:      return hasPhonophobia
        case .vertigo:          return hasVertigo
        case .tinnitus:         return hasTinnitus
        case .wakeUpHeadache:   return hasWakeUpHeadache
        }
    }
}

extension Array where Element == MonthlyPoint {
    /// Mean count across the series, or 0 when empty.
    var averageCount: Double {
        guard !isEmpty else { return 0 }
        return Double(reduce(0) { $0 + $1.count }) / Double(count)
    }
}
