//
//  HealthKitSampleClampTests.swift
//  NALI Migraine LogTests
//
//  Regression tests for the end-time clamp that prevents the "Sync All
//  Migraines Now" backfill from crashing.
//
//  `HKCategorySample.init(type:value:start:end:metadata:)` raises an
//  Objective-C `NSInvalidArgumentException` when `end < start`. That
//  exception cannot be caught by Swift `do/catch`, so a single stored
//  migraine whose end time precedes its start time (the editor historically
//  allowed this) would crash the whole app when the user force-synced to
//  Apple Health. `HealthKitManager.clampedHealthSampleEnd` guarantees the
//  end is never before the start so every constructed sample is valid.
//

import Testing
import Foundation
@testable import NALI_Migraine_Log

@Suite("HealthKit sample end-time clamp")
struct HealthKitSampleClampTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("End before start is clamped up to the start time")
    func endBeforeStartIsClamped() {
        let end = start.addingTimeInterval(-3600) // an hour *before* start
        let clamped = HealthKitManager.clampedHealthSampleEnd(start: start, end: end)
        #expect(clamped == start)
        #expect(clamped >= start)
    }

    @Test("A valid end after the start is preserved unchanged")
    func validEndIsPreserved() {
        let end = start.addingTimeInterval(3600) // an hour after start
        let clamped = HealthKitManager.clampedHealthSampleEnd(start: start, end: end)
        #expect(clamped == end)
    }

    @Test("A nil end (still-ongoing migraine) falls back to the start")
    func nilEndFallsBackToStart() {
        let clamped = HealthKitManager.clampedHealthSampleEnd(start: start, end: nil)
        #expect(clamped == start)
    }

    @Test("An end equal to the start is left as-is (zero-duration sample)")
    func equalEndIsPreserved() {
        let clamped = HealthKitManager.clampedHealthSampleEnd(start: start, end: start)
        #expect(clamped == start)
    }
}

@Suite("HealthKit sleep interval merge")
struct HealthKitSleepMergeTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func interval(_ startHours: Double, _ endHours: Double) -> DateInterval {
        DateInterval(start: base.addingTimeInterval(startHours * 3600),
                     end: base.addingTimeInterval(endHours * 3600))
    }

    @Test("Overlapping samples from two sources are counted once")
    func overlappingSamplesCountOnce() {
        // Watch stages 23:00–06:30 split into blocks, plus a third-party
        // tracker's single 23:15–06:00 "asleep" block.
        let intervals = [
            interval(0, 2), interval(2, 4.5), interval(5, 7.5),
            interval(0.25, 7)
        ]
        let merged = HealthKitManager.mergedIntervals(intervals)
        #expect(merged.count == 1)
        #expect(HealthKitManager.mergedDuration(of: intervals) == 7.5 * 3600)
    }

    @Test("Disjoint samples keep their gaps")
    func disjointSamplesKeepGaps() {
        let intervals = [interval(3, 4), interval(0, 1)]
        let merged = HealthKitManager.mergedIntervals(intervals)
        #expect(merged.count == 2)
        #expect(merged.first?.start == base)
        #expect(HealthKitManager.mergedDuration(of: intervals) == 2 * 3600)
    }

    @Test("Touching samples coalesce and an empty list yields zero")
    func touchingAndEmpty() {
        #expect(HealthKitManager.mergedIntervals([interval(0, 1), interval(1, 2)]).count == 1)
        #expect(HealthKitManager.mergedDuration(of: []) == 0)
    }
}
