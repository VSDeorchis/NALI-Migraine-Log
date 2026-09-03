//
//  AnalyticsComputations.swift
//  NALI Migraine Log
//
//  Pure-data extensions on `[MigraineEvent]` powering the dashboard tiles,
//  severity heatmap and auto-generated insight cards. Kept side-effect free
//  and synchronous so the filtered list can be produced once per redraw and
//  shared across multiple views without re-walking Core Data.
//

import Foundation

// MARK: - Severity buckets

extension Array where Element == MigraineEvent {

    /// Distribution of migraines across mild/moderate/severe/extreme buckets.
    /// Always returns one entry per bucket, including zero-count buckets, so
    /// the chart layout stays stable as the time filter changes.
    var severityBucketDistribution: [SeverityBucketPoint] {
        var counts: [SeverityBucket: Int] = [:]
        for migraine in self {
            guard let bucket = SeverityBucket.bucket(for: Int(migraine.painLevel)) else {
                continue
            }
            counts[bucket, default: 0] += 1
        }
        return SeverityBucket.allCases.map {
            SeverityBucketPoint(bucket: $0, count: counts[$0] ?? 0)
        }
    }

    /// Number of *unique calendar days* on which at least one migraine reached
    /// pain level 7+. We count days, not migraines, to align with the way
    /// patients describe their experience to clinicians ("I had 3 bad days
    /// last month") and to avoid double-counting multi-event days.
    func severePainDays(calendar: Calendar = .current) -> Int {
        let severeDays = compactMap { migraine -> Date? in
            guard migraine.painLevel >= 7,
                  let start = migraine.startTime else { return nil }
            return calendar.startOfDay(for: start)
        }
        return Set(severeDays).count
    }
}

// MARK: - Streaks & frequency

extension Array where Element == MigraineEvent {

    /// Days since the most recent migraine in the *full* dataset, capped at
    /// the period length so we can show a sane number when the user has
    /// never logged a migraine. Returns `nil` only when the array is empty.
    func currentMigraineFreeStreak(now: Date = Date(),
                                   calendar: Calendar = .current) -> Int? {
        let mostRecentStart = compactMap(\.startTime).max()
        guard let last = mostRecentStart else { return nil }

        let lastDay = calendar.startOfDay(for: last)
        let today   = calendar.startOfDay(for: now)
        let days    = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return Swift.max(days, 0)
    }

    /// Longest consecutive streak of migraine-free days within the bounded
    /// `[start, end]` window. Useful for the year/month detail view, where
    /// we want to celebrate the best stretch — not just "today minus last".
    func longestMigraineFreeStreak(in interval: DateInterval,
                                   calendar: Calendar = .current) -> Int {
        let migraineDays: Set<Date> = Set(
            self.compactMap { migraine -> Date? in
                guard let start = migraine.startTime,
                      interval.contains(start) else { return nil }
                return calendar.startOfDay(for: start)
            }
        )

        var longest = 0
        var current = 0
        var cursor = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)

        while cursor <= end {
            if migraineDays.contains(cursor) {
                current = 0
            } else {
                current += 1
                longest = Swift.max(longest, current)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return longest
    }
}

// MARK: - Top trigger / medication

extension Array where Element == MigraineEvent {

    /// Most common trigger by occurrence count, plus the count itself.
    /// Returns `nil` if the period has no logged triggers.
    var topTrigger: (trigger: MigraineTrigger, count: Int)? {
        var counts: [MigraineTrigger: Int] = [:]
        for migraine in self {
            for trigger in migraine.triggers {
                counts[trigger, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    /// Most-used medication by occurrence count.
    var topMedication: (medication: MigraineMedication, count: Int)? {
        var counts: [MigraineMedication: Int] = [:]
        for migraine in self {
            for medication in migraine.medications {
                counts[medication, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }
}

// MARK: - Life impact

extension Array where Element == MigraineEvent {

    /// Total cumulative impact days = (#missed work) + (#missed school) + (#missed events).
    /// Days are counted independently per category (a single migraine that
    /// missed work *and* an event counts twice), matching how the existing
    /// Life Impact card already decomposes them.
    var totalImpactDays: Int {
        reduce(0) { acc, migraine in
            acc
            + (migraine.missedWork ? 1 : 0)
            + (migraine.missedSchool ? 1 : 0)
            + (migraine.missedEvents ? 1 : 0)
        }
    }
}

// MARK: - Heatmap cells

extension Array where Element == MigraineEvent {

    /// One `DailyPainCell` per day in `interval`. Every day is represented —
    /// migraine-free days appear with `worstPain == 0`. The heatmap relies
    /// on this dense layout to render an even grid.
    func dailyPainCells(in interval: DateInterval,
                        calendar: Calendar = .current) -> [DailyPainCell] {
        var worstByDay: [Date: (Int, Int)] = [:]      // day -> (worst pain, count)

        for migraine in self {
            guard let start = migraine.startTime,
                  interval.contains(start) else { continue }
            let day = calendar.startOfDay(for: start)
            let pain = Int(migraine.painLevel)
            if let existing = worstByDay[day] {
                worstByDay[day] = (Swift.max(existing.0, pain), existing.1 + 1)
            } else {
                worstByDay[day] = (pain, 1)
            }
        }

        var cells: [DailyPainCell] = []
        var cursor = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        while cursor <= end {
            if let value = worstByDay[cursor] {
                cells.append(DailyPainCell(date: cursor,
                                           worstPain: value.0,
                                           migraineCount: value.1))
            } else {
                cells.append(DailyPainCell(date: cursor,
                                           worstPain: 0,
                                           migraineCount: 0))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return cells
    }
}

// MARK: - Dashboard aggregates

extension Array where Element == MigraineEvent {

    /// Mean duration of entries that have an explicit end time; `nil` when
    /// no entry in the set has been closed out.
    var averageDuration: TimeInterval? {
        let durations = compactMap { migraine -> TimeInterval? in
            guard let start = migraine.startTime, let end = migraine.endTime else { return nil }
            return end.timeIntervalSince(start)
        }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// Number of entries that contribute to `averageDuration`.
    var completedCount: Int {
        reduce(0) { $0 + ($1.endTime == nil ? 0 : 1) }
    }

    /// Mean pain level, or 0 for an empty set.
    var averagePain: Double {
        guard !isEmpty else { return 0 }
        return reduce(0.0) { $0 + Double($1.painLevel) } / Double(count)
    }

    /// Total medication doses across all entries (one per flagged medication).
    var totalMedicationUses: Int {
        reduce(0) { $0 + $1.medications.count }
    }

    /// Entries whose start time falls inside `interval`.
    func count(in interval: DateInterval) -> Int {
        reduce(0) { acc, migraine in
            guard let start = migraine.startTime, interval.contains(start) else { return acc }
            return acc + 1
        }
    }

    /// One point per pain level 1...10, including zero counts.
    var painLevelDistribution: [PainLevelPoint] {
        var counts: [Int: Int] = [:]
        for migraine in self {
            counts[Int(migraine.painLevel), default: 0] += 1
        }
        return (1...10).map { PainLevelPoint(level: $0, count: counts[$0] ?? 0) }
    }

    /// Triggers sorted by frequency, most common first; zero-count triggers omitted.
    var triggerDistribution: [TriggerPoint] {
        var counts: [MigraineTrigger: Int] = [:]
        for migraine in self {
            for trigger in migraine.triggers { counts[trigger, default: 0] += 1 }
        }
        return counts
            .filter { $0.value > 0 }
            .map { TriggerPoint(trigger: $0.key.displayName, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Medications sorted by frequency, most used first; zero-count medications omitted.
    var medicationDistribution: [MedicationPoint] {
        var counts: [MigraineMedication: Int] = [:]
        for migraine in self {
            for medication in migraine.medications { counts[medication, default: 0] += 1 }
        }
        return counts
            .filter { $0.value > 0 }
            .map { MedicationPoint(medication: $0.key.displayName, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    static var timeOfDaySlots: [String] { ["Morning", "Afternoon", "Evening", "Night"] }

    /// Onset counts per part of day (Morning 5–12, Afternoon 12–17,
    /// Evening 17–22, Night otherwise). Always emits all four slots.
    func timeOfDayDistribution(calendar: Calendar = .current) -> [TimeOfDayPoint] {
        var counts: [String: Int] = [:]
        for migraine in self {
            guard let date = migraine.startTime else { continue }
            let slot: String
            switch calendar.component(.hour, from: date) {
            case 5..<12:  slot = "Morning"
            case 12..<17: slot = "Afternoon"
            case 17..<22: slot = "Evening"
            default:      slot = "Night"
            }
            counts[slot, default: 0] += 1
        }
        return Self.timeOfDaySlots.map { TimeOfDayPoint(timeOfDay: $0, count: counts[$0] ?? 0) }
    }

    /// Missed work / school / events counts, always three points.
    var qualityOfLifeDistribution: [QualityOfLifePoint] {
        [
            QualityOfLifePoint(type: "Missed Work", count: filter(\.missedWork).count),
            QualityOfLifePoint(type: "Missed School", count: filter(\.missedSchool).count),
            QualityOfLifePoint(type: "Missed Events", count: filter(\.missedEvents).count)
        ]
    }

    /// Entries per calendar month for the `monthsBack` months ending with
    /// the month containing `now`. Months without entries are included.
    func monthlyDistribution(monthsBack: Int = 6,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> [MonthlyPoint] {
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let windowStart = calendar.date(byAdding: .month, value: -monthsBack, to: currentMonthStart) ?? currentMonthStart
        let windowEnd = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? now

        var counts: [Date: Int] = [:]
        var cursor = windowStart
        while cursor < windowEnd {
            counts[cursor] = 0
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        for migraine in self {
            guard let date = migraine.startTime, date >= windowStart, date < windowEnd,
                  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            else { continue }
            counts[monthStart, default: 0] += 1
        }

        return counts.map { MonthlyPoint(month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }
}

// MARK: - Day-of-week

extension Array where Element == MigraineEvent {

    /// Most common weekday for a migraine onset (1 = Sunday in `Calendar.current`),
    /// plus a normalized 0...1 share for tooltips.
    func mostCommonWeekday(calendar: Calendar = .current)
    -> (weekday: Int, name: String, share: Double)? {
        guard !isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for migraine in self {
            guard let start = migraine.startTime else { continue }
            let dow = calendar.component(.weekday, from: start)
            counts[dow, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        let total = counts.values.reduce(0, +)
        let share = total > 0 ? Double(top.value) / Double(total) : 0

        let formatter = DateFormatter()
        formatter.calendar = calendar
        let symbols = formatter.weekdaySymbols ?? []
        let index = Swift.max(0, Swift.min(top.key - 1, symbols.count - 1))
        return (top.key, symbols[index], share)
    }
}
