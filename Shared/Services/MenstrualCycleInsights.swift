//
//  MenstrualCycleInsights.swift
//  NALI Migraine Log
//
//  Pure, HealthKit-free math for the cycle-aware features:
//
//    • `CycleEligibility` — the identity gate. Biological sex comes
//      from the HealthKit characteristic; `.male` excludes the feature
//      everywhere (Settings toggle, log badge, risk factor, Statistics
//      split). `.female` opts in outright; `.undetermined` (not set /
//      "other" / read denied) falls back to data-driven gating and only
//      activates when real menstrual-flow history exists.
//
//    • `PerimenstrualWindow` — the "1–2 days before through 2 days
//      after the start of menses" band the literature associates with
//      estrogen-withdrawal migraine. Offsets are measured in whole
//      calendar days from a cycle start (day 0): −2, −1, 0, +1, +2.
//      Days *before* a start that has not happened yet are estimated
//      from the median cycle length, so today's risk score can flag
//      "period expected in 2 days" without waiting for the flow sample.
//
//  Nothing here persists or logs cycle data; callers pass in the cycle
//  start dates they already hold in memory.
//

import Foundation

/// Whether the cycle-aware features may be offered at all.
enum CycleEligibility: Equatable, Sendable {
    /// Biological sex is recorded as male in Health — never offer.
    case excluded
    /// Biological sex is recorded as female in Health.
    case eligible
    /// Biological sex is not set, recorded as "other", or unreadable.
    /// Offer only when menstrual-flow history actually exists.
    case undetermined

    /// `true` when the feature may be surfaced, given whether the
    /// user has any menstrual-flow samples in Health.
    func allowsCycleInsights(hasMenstrualHistory: Bool) -> Bool {
        switch self {
        case .excluded:     return false
        case .eligible:     return true
        case .undetermined: return hasMenstrualHistory
        }
    }
}

enum PerimenstrualWindow {
    /// Days before a cycle start that count as perimenstrual.
    static let daysBefore = 2
    /// Days after a cycle start (exclusive of day 0) that count as perimenstrual.
    static let daysAfter = 2

    /// Cycle lengths outside this range are treated as tracking gaps
    /// rather than real cycles when estimating the next start.
    static let plausibleCycleLengths: ClosedRange<Int> = 21...40

    /// Consecutive cycle lengths (in days) between sorted starts,
    /// limited to plausible values.
    static func cycleLengths(cycleStarts: [Date], calendar: Calendar = .current) -> [Int] {
        let starts = cycleStarts.map { calendar.startOfDay(for: $0) }.sorted()
        guard starts.count >= 2 else { return [] }
        return zip(starts, starts.dropFirst()).compactMap { previous, next in
            guard let days = calendar.dateComponents([.day], from: previous, to: next).day,
                  plausibleCycleLengths.contains(days) else { return nil }
            return days
        }
    }

    /// Median of the plausible cycle lengths, or `nil` with fewer than
    /// two usable intervals.
    static func typicalCycleLength(cycleStarts: [Date], calendar: Calendar = .current) -> Int? {
        let lengths = cycleLengths(cycleStarts: cycleStarts, calendar: calendar).sorted()
        guard lengths.count >= 2 else { return nil }
        let mid = lengths.count / 2
        if lengths.count.isMultiple(of: 2) {
            return (lengths[mid - 1] + lengths[mid]) / 2
        }
        return lengths[mid]
    }

    /// Expected next cycle start: most recent start plus the typical
    /// cycle length. `nil` when the history is too thin to estimate.
    static func predictedNextStart(cycleStarts: [Date], calendar: Calendar = .current) -> Date? {
        guard let last = cycleStarts.map({ calendar.startOfDay(for: $0) }).max(),
              let length = typicalCycleLength(cycleStarts: cycleStarts, calendar: calendar) else {
            return nil
        }
        return calendar.date(byAdding: .day, value: length, to: last)
    }

    /// Whole-day offset of `date` from the nearest cycle start when it
    /// falls inside the perimenstrual band (−`daysBefore` … +`daysAfter`),
    /// otherwise `nil`. Logged starts win over the predicted next start;
    /// the prediction is only consulted for dates after the last logged
    /// start so historical entries are never tagged from an estimate.
    static func dayOffset(
        for date: Date,
        cycleStarts: [Date],
        calendar: Calendar = .current
    ) -> Int? {
        guard !cycleStarts.isEmpty else { return nil }
        let day = calendar.startOfDay(for: date)
        let starts = cycleStarts.map { calendar.startOfDay(for: $0) }.sorted()

        if let offset = nearestOffset(of: day, to: starts, calendar: calendar) {
            return offset
        }

        if let lastStart = starts.last, day > lastStart,
           let predicted = predictedNextStart(cycleStarts: starts, calendar: calendar) {
            return nearestOffset(of: day, to: [predicted], calendar: calendar)
        }
        return nil
    }

    private static func nearestOffset(of day: Date, to starts: [Date], calendar: Calendar) -> Int? {
        var best: Int?
        for start in starts {
            guard let diff = calendar.dateComponents([.day], from: start, to: day).day,
                  diff >= -daysBefore, diff <= daysAfter else { continue }
            if let current = best, abs(current) <= abs(diff) { continue }
            best = diff
        }
        return best
    }

    /// Short, non-diagnostic label for a badge (e.g. "2 days before period").
    static func shortLabel(forOffset offset: Int) -> String {
        switch offset {
        case ..<0:
            let n = -offset
            return n == 1 ? "Day before period" : "\(n) days before period"
        case 0:
            return "Period started"
        default:
            return "Day \(offset + 1) of period"
        }
    }

    /// Recommendation paired with the perimenstrual risk factor.
    static let recommendation =
        "Migraines are more common in the days just before and after a period starts. If you notice this pattern, it may be worth discussing preventive options with your clinician."

    /// Recommendation for the older days-since-flow fallback.
    static let legacyRecommendation =
        "Hormonal changes around menstruation are a common migraine trigger. Consider preventive strategies."

    /// Recommendation strings that must not leave the phone.
    static let sensitiveRecommendations: Set<String> = [recommendation, legacyRecommendation]

    /// Longer explanation used in the risk-factor detail. Negative
    /// offsets describe an *expected* start (estimated from recent
    /// cycle lengths) because a future flow sample cannot exist yet.
    static func riskDetail(forOffset offset: Int) -> String {
        switch offset {
        case ..<0:
            let n = -offset
            let when = n == 1 ? "tomorrow" : "in \(n) days"
            return "Your period is expected \(when) based on your recent cycle lengths — the days just before menses are a common trigger window"
        case 0:
            return "Your period started today — the first days of menses are a common trigger window"
        default:
            return "Day \(offset + 1) of your period — the first days of menses are a common trigger window"
        }
    }
}
