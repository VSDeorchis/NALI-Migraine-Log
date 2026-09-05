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
    /// Pass `usePrediction: false` for retrospective analytics that must
    /// only ever reflect logged flow samples.
    static func dayOffset(
        for date: Date,
        cycleStarts: [Date],
        calendar: Calendar = .current,
        usePrediction: Bool = true
    ) -> Int? {
        guard !cycleStarts.isEmpty else { return nil }
        let day = calendar.startOfDay(for: date)
        let starts = cycleStarts.map { calendar.startOfDay(for: $0) }.sorted()

        if let offset = nearestOffset(of: day, to: starts, calendar: calendar) {
            return offset
        }

        if usePrediction, let lastStart = starts.last, day > lastStart,
           let predicted = predictedNextStart(cycleStarts: starts, calendar: calendar) {
            return nearestOffset(of: day, to: [predicted], calendar: calendar)
        }
        return nil
    }

    private static func nearestOffset(of day: Date, to starts: [Date], calendar: Calendar) -> Int? {
        nearestOffset(of: day, to: starts, within: -daysBefore...daysAfter, calendar: calendar)
    }

    /// Signed day offset from the closest start whose distance falls
    /// inside `range`, or `nil`. Ties resolve to the earlier start.
    static func nearestOffset(
        of day: Date,
        to starts: [Date],
        within range: ClosedRange<Int>,
        calendar: Calendar
    ) -> Int? {
        var best: Int?
        for start in starts {
            guard let diff = calendar.dateComponents([.day], from: start, to: day).day,
                  range.contains(diff) else { continue }
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

// MARK: - Denominator-aware association

/// One logged attack reduced to what the cycle analysis needs.
struct CycleMigraineSample: Equatable, Sendable {
    let onset: Date
    let painLevel: Int
}

/// How much weight the observed perimenstrual pattern can carry.
enum CycleConfidence: Equatable, Sendable {
    /// Too few cycles or migraine days to say anything — no ratio shown.
    case insufficient
    /// 3–5 cycles observed.
    case early
    /// 6 or more cycles observed.
    case consistent

    var title: String {
        switch self {
        case .insufficient: return "Pattern emerging"
        case .early:        return "Early pattern"
        case .consistent:   return "Consistent pattern"
        }
    }
}

/// Migraine days and observed days at one relative offset from a
/// logged cycle start (day 0). Drives the cycle-aligned chart.
struct CycleAlignedPoint: Identifiable, Equatable, Sendable {
    var id: Int { offset }
    let offset: Int
    let migraineDays: Int
    let observedDays: Int

    /// Share of observed days at this offset that had a migraine.
    var rate: Double? {
        guard observedDays > 0 else { return nil }
        return Double(migraineDays) / Double(observedDays)
    }

    var isPerimenstrual: Bool {
        offset >= -PerimenstrualWindow.daysBefore && offset <= PerimenstrualWindow.daysAfter
    }
}

/// Rate-ratio comparison of migraine days inside vs. outside the
/// perimenstrual window, over the days for which cycle context is
/// actually known. Compare with a raw "30% of migraines were
/// perimenstrual" figure, which has no denominator: the window covers
/// roughly 5 of every 28 days, so ~18% would be expected by chance.
struct CycleAssociation: Equatable, Sendable {
    /// Logged cycle starts whose perimenstrual window overlaps the
    /// observed days.
    let cycleCount: Int
    /// Unique migraine days that fell on observed days.
    let migraineDayCount: Int
    let perimenstrualMigraineDays: Int
    let perimenstrualDaysObserved: Int
    let otherMigraineDays: Int
    let otherDaysObserved: Int
    /// Of the most recent fully-observed cycles (up to three), how many
    /// had at least one migraine inside the perimenstrual window.
    let recentCyclesWithPerimenstrualMigraine: Int
    let recentCyclesEvaluated: Int
    /// Mean pain of attacks starting inside / outside the window.
    let perimenstrualMeanPain: Double?
    let perimenstrualAttackCount: Int
    let otherMeanPain: Double?
    let otherAttackCount: Int
    let aligned: [CycleAlignedPoint]

    var perimenstrualRate: Double? {
        guard perimenstrualDaysObserved > 0 else { return nil }
        return Double(perimenstrualMigraineDays) / Double(perimenstrualDaysObserved)
    }

    var baselineRate: Double? {
        guard otherDaysObserved > 0 else { return nil }
        return Double(otherMigraineDays) / Double(otherDaysObserved)
    }

    /// Perimenstrual rate ÷ baseline rate. `nil` when either side has
    /// no observed days or when no migraine fell outside the window
    /// (an infinite ratio is reported in words instead).
    var rateRatio: Double? {
        guard let perimenstrualRate, let baselineRate, baselineRate > 0 else { return nil }
        return perimenstrualRate / baselineRate
    }

    var confidence: CycleConfidence {
        if cycleCount < CycleAssociationAnalysis.minimumCycles
            || migraineDayCount < CycleAssociationAnalysis.minimumMigraineDays {
            return .insufficient
        }
        return cycleCount >= CycleAssociationAnalysis.consistentCycles ? .consistent : .early
    }

    /// Whether both pain cohorts are large enough to compare.
    var hasSeverityComparison: Bool {
        perimenstrualAttackCount >= CycleAssociationAnalysis.minimumSeveritySamples
            && otherAttackCount >= CycleAssociationAnalysis.minimumSeveritySamples
            && perimenstrualMeanPain != nil && otherMeanPain != nil
    }

    /// Headline copy. Association only — never a diagnosis.
    var headline: String {
        let windowDays = PerimenstrualWindow.daysBefore + PerimenstrualWindow.daysAfter + 1
        switch confidence {
        case .insufficient:
            return "Pattern emerging — keep logging"
        case .early, .consistent:
            if let ratio = rateRatio {
                let rounded = (ratio * 10).rounded() / 10
                if rounded >= 1.2 {
                    return "Migraines were \(Self.format(rounded))× more likely in the \(windowDays) days around the start of your period"
                }
                if rounded <= 0.8 {
                    return "Migraines were less likely around the start of your period (\(Self.format(rounded))× the rate on other days)"
                }
                return "Migraines were about as likely around your period as on other days"
            }
            if perimenstrualMigraineDays > 0, otherMigraineDays == 0 {
                return "Every migraine day fell in the \(windowDays) days around the start of your period"
            }
            if perimenstrualMigraineDays == 0, otherMigraineDays > 0 {
                return "No migraine days fell in the \(windowDays) days around the start of your period"
            }
            return "Not enough migraine days to compare yet"
        }
    }

    /// "In 3 of your last 3 cycles" style indicator, or `nil` when no
    /// complete cycle has been observed.
    var recentCyclesSummary: String? {
        guard recentCyclesEvaluated > 0 else { return nil }
        let cycles = recentCyclesEvaluated == 1 ? "cycle" : "cycles"
        return "A migraine started in the perimenstrual window in \(recentCyclesWithPerimenstrualMigraine) of your last \(recentCyclesEvaluated) \(cycles)"
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum CycleAssociationAnalysis {
    static let minimumCycles = 3
    static let minimumMigraineDays = 5
    static let consistentCycles = 6
    static let minimumSeveritySamples = 3
    static let recentCyclesToEvaluate = 3
    /// Relative-day range plotted in the cycle-aligned chart.
    static let alignedRange: ClosedRange<Int> = -7...7
    /// Days after a logged start beyond which cycle context is treated
    /// as unknown (a tracking gap rather than a 60-day cycle).
    static let maxCoverageGap = 45

    /// Computes the association over `window`, restricted to days on
    /// which cycle context is known: from two days before the first
    /// logged start, never into the future, and never more than
    /// `maxCoverageGap` days past the most recent start. Only logged
    /// starts are used — predictions never feed retrospective stats.
    static func compute(
        samples: [CycleMigraineSample],
        cycleStarts: [Date],
        window: DateInterval,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CycleAssociation? {
        let starts = Array(Set(cycleStarts.map { calendar.startOfDay(for: $0) })).sorted()
        guard let firstStart = starts.first else { return nil }

        let windowStart = calendar.startOfDay(for: window.start)
        let windowEnd = calendar.startOfDay(for: window.end)
        guard let today = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let earliest = calendar.date(byAdding: .day, value: -PerimenstrualWindow.daysBefore, to: firstStart)
        else { return nil }

        let coverageStart = max(windowStart, earliest)
        let coverageEnd = min(windowEnd, today)
        guard coverageStart < coverageEnd else { return nil }

        var migraineDays: Set<Date> = []
        for sample in samples {
            migraineDays.insert(calendar.startOfDay(for: sample.onset))
        }

        var observedDays: Set<Date> = []
        var periMigraine = 0, periObserved = 0, otherMigraine = 0, otherObserved = 0
        var alignedMigraine: [Int: Int] = [:]
        var alignedObserved: [Int: Int] = [:]

        var day = coverageStart
        while day < coverageEnd {
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? coverageEnd
            }
            if let prior = starts.last(where: { $0 <= day }),
               let gap = calendar.dateComponents([.day], from: prior, to: day).day,
               gap > maxCoverageGap {
                continue
            }
            observedDays.insert(day)
            let hasMigraine = migraineDays.contains(day)
            let periOffset = PerimenstrualWindow.dayOffset(
                for: day, cycleStarts: starts, calendar: calendar, usePrediction: false
            )
            if periOffset != nil {
                periObserved += 1
                if hasMigraine { periMigraine += 1 }
            } else {
                otherObserved += 1
                if hasMigraine { otherMigraine += 1 }
            }
            if let offset = PerimenstrualWindow.nearestOffset(
                of: day, to: starts, within: alignedRange, calendar: calendar
            ) {
                alignedObserved[offset, default: 0] += 1
                if hasMigraine { alignedMigraine[offset, default: 0] += 1 }
            }
        }

        guard !observedDays.isEmpty else { return nil }

        // Cycle starts whose window touches an observed day.
        let coveredStarts = starts.filter { start in
            guard let lo = calendar.date(byAdding: .day, value: -PerimenstrualWindow.daysBefore, to: start),
                  let hi = calendar.date(byAdding: .day, value: PerimenstrualWindow.daysAfter, to: start)
            else { return false }
            return hi >= coverageStart && lo < coverageEnd
        }

        // Most recent cycles whose whole window has been observed.
        var recentEvaluated = 0
        var recentWithMigraine = 0
        for start in coveredStarts.reversed() where recentEvaluated < recentCyclesToEvaluate {
            let offsets = -PerimenstrualWindow.daysBefore...PerimenstrualWindow.daysAfter
            let windowDays = offsets.compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            guard windowDays.count == offsets.count,
                  windowDays.allSatisfy({ observedDays.contains($0) }) else { continue }
            recentEvaluated += 1
            if windowDays.contains(where: { migraineDays.contains($0) }) {
                recentWithMigraine += 1
            }
        }

        var periPain: [Double] = []
        var otherPain: [Double] = []
        for sample in samples {
            let onsetDay = calendar.startOfDay(for: sample.onset)
            guard observedDays.contains(onsetDay) else { continue }
            let isPeri = PerimenstrualWindow.dayOffset(
                for: onsetDay, cycleStarts: starts, calendar: calendar, usePrediction: false
            ) != nil
            if isPeri { periPain.append(Double(sample.painLevel)) }
            else { otherPain.append(Double(sample.painLevel)) }
        }

        let aligned = alignedRange.map { offset in
            CycleAlignedPoint(
                offset: offset,
                migraineDays: alignedMigraine[offset] ?? 0,
                observedDays: alignedObserved[offset] ?? 0
            )
        }

        return CycleAssociation(
            cycleCount: coveredStarts.count,
            migraineDayCount: periMigraine + otherMigraine,
            perimenstrualMigraineDays: periMigraine,
            perimenstrualDaysObserved: periObserved,
            otherMigraineDays: otherMigraine,
            otherDaysObserved: otherObserved,
            recentCyclesWithPerimenstrualMigraine: recentWithMigraine,
            recentCyclesEvaluated: recentEvaluated,
            perimenstrualMeanPain: periPain.isEmpty ? nil : periPain.reduce(0, +) / Double(periPain.count),
            perimenstrualAttackCount: periPain.count,
            otherMeanPain: otherPain.isEmpty ? nil : otherPain.reduce(0, +) / Double(otherPain.count),
            otherAttackCount: otherPain.count,
            aligned: aligned
        )
    }
}
