//
//  MLModelValidationTests.swift
//  NALI Migraine LogTests
//
//  The ML confidence shown to users is derived from hold-out performance.
//  These tests pin the shape of that derivation: no skill above the
//  majority-class baseline means floor confidence, more hold-out days mean
//  more credit, and the value never leaves its bounds.
//

import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("MLModelValidation")
struct MLModelValidationTests {

    @Test("Confidence sits at the floor when the model is no better than always guessing the majority class")
    func noSkillIsFloor() {
        let atBaseline = MLModelValidation.confidence(accuracy: 0.8, baseline: 0.8, sampleCount: 100)
        let belowBaseline = MLModelValidation.confidence(accuracy: 0.6, baseline: 0.8, sampleCount: 100)
        #expect(atBaseline == MLModelValidation.floor)
        #expect(belowBaseline == MLModelValidation.floor)
    }

    @Test("Perfect accuracy with a full-size hold-out reaches the ceiling")
    func perfectIsCeiling() {
        let value = MLModelValidation.confidence(
            accuracy: 1.0,
            baseline: 0.7,
            sampleCount: MLModelValidation.fullCreditSampleCount
        )
        #expect(abs(value - MLModelValidation.ceiling) < 1e-9)
    }

    @Test("Confidence scales linearly with hold-out size until full credit and then plateaus")
    func sampleSizeScaling() {
        let small = MLModelValidation.confidence(accuracy: 1.0, baseline: 0.5, sampleCount: 15)
        let half = MLModelValidation.confidence(accuracy: 1.0, baseline: 0.5, sampleCount: 30)
        let full = MLModelValidation.confidence(accuracy: 1.0, baseline: 0.5, sampleCount: 60)
        let oversized = MLModelValidation.confidence(accuracy: 1.0, baseline: 0.5, sampleCount: 600)

        let span = MLModelValidation.ceiling - MLModelValidation.floor
        #expect(abs(small - (MLModelValidation.floor + span * 0.25)) < 1e-9)
        #expect(abs(half - (MLModelValidation.floor + span * 0.5)) < 1e-9)
        #expect(abs(full - MLModelValidation.ceiling) < 1e-9)
        #expect(oversized == full)
    }

    @Test("Partial skill lands strictly between floor and ceiling")
    func partialSkill() {
        // 0.85 accuracy vs 0.70 baseline: skill = 0.15 / 0.30 = 0.5
        let value = MLModelValidation.confidence(accuracy: 0.85, baseline: 0.70, sampleCount: 60)
        let expected = MLModelValidation.floor + (MLModelValidation.ceiling - MLModelValidation.floor) * 0.5
        #expect(abs(value - expected) < 1e-9)
    }

    @Test("Invalid inputs fall back to the floor instead of NaN or out-of-range values")
    func invalidInputs() {
        #expect(MLModelValidation.confidence(accuracy: .nan, baseline: 0.5, sampleCount: 10) == MLModelValidation.floor)
        #expect(MLModelValidation.confidence(accuracy: 0.9, baseline: .infinity, sampleCount: 10) == MLModelValidation.floor)
        #expect(MLModelValidation.confidence(accuracy: 0.9, baseline: 0.5, sampleCount: 0) == MLModelValidation.floor)
        #expect(MLModelValidation.confidence(accuracy: 0.9, baseline: 0.5, sampleCount: -3) == MLModelValidation.floor)
        // A single-class hold-out (baseline == 1) has nothing to beat.
        #expect(MLModelValidation.confidence(accuracy: 1.0, baseline: 1.0, sampleCount: 60) == MLModelValidation.floor)
    }

    @Test("Confidence is always bounded even for absurd accuracy values")
    func alwaysBounded() {
        for accuracy in [-5.0, 0.0, 0.5, 1.0, 5.0] {
            for baseline in [0.0, 0.5, 0.99] {
                for count in [1, 7, 60, 10_000] {
                    let value = MLModelValidation.confidence(accuracy: accuracy, baseline: baseline, sampleCount: count)
                    #expect(value >= MLModelValidation.floor && value <= MLModelValidation.ceiling)
                }
            }
        }
    }

    @Test("Placeholder for models trained before validation existed is inside the bounds")
    func unvalidatedPlaceholder() {
        #expect(MLModelValidation.unvalidated > MLModelValidation.floor)
        #expect(MLModelValidation.unvalidated < MLModelValidation.ceiling)
    }

    @Test("Majority baseline is the share of the more common label")
    func majorityBaseline() {
        #expect(MLModelValidation.majorityBaseline(labels: [0, 0, 0, 1]) == 0.75)
        #expect(MLModelValidation.majorityBaseline(labels: [1, 1, 1, 0]) == 0.75)
        #expect(MLModelValidation.majorityBaseline(labels: [0, 1]) == 0.5)
        #expect(MLModelValidation.majorityBaseline(labels: [1, 1, 1]) == 1)
        #expect(MLModelValidation.majorityBaseline(labels: []) == 1)
    }

    @Test("Chronological split keeps order and holds out the most recent rows")
    func chronologicalSplitOrder() throws {
        let rows = Array(0..<100)
        let split = try #require(MLModelValidation.chronologicalSplit(rows))
        #expect(split.training == Array(0..<80))
        #expect(split.holdOut == Array(80..<100))
    }

    @Test("Hold-out never drops below the minimum even for small data sets")
    func chronologicalSplitMinimumHoldOut() throws {
        let rows = Array(0..<40)
        let split = try #require(MLModelValidation.chronologicalSplit(rows, minimumHoldOut: 10, minimumTraining: 20))
        #expect(split.holdOut.count == 10)
        #expect(split.training.count == 30)
    }

    @Test("Split refuses when the remaining training rows would be under the minimum")
    func chronologicalSplitTooSmall() {
        #expect(MLModelValidation.chronologicalSplit(Array(0..<29), minimumHoldOut: 10, minimumTraining: 20) == nil)
        #expect(MLModelValidation.chronologicalSplit(Array(0..<30), minimumHoldOut: 10, minimumTraining: 20) != nil)
        #expect(MLModelValidation.chronologicalSplit([Int](), minimumHoldOut: 10, minimumTraining: 20) == nil)
    }

    @Test("Validation record round-trips through JSON and reports the same confidence")
    func codableRoundTrip() throws {
        let original = MLModelValidation(accuracy: 0.82, baseline: 0.7, sampleCount: 25, evaluatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MLModelValidation.self, from: data)
        #expect(decoded == original)
        #expect(decoded.confidence == original.confidence)
    }
}
