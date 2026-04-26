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
