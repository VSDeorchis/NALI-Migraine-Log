//
//  MLModelConfidence.swift
//  NALI Migraine Log
//
//  Turns a trained model's hold-out performance into the 0...1 confidence
//  shown next to ML-backed risk scores and used to weight the ML/rule blend.
//

import Foundation

/// Hold-out evaluation of a trained risk model.
///
/// `accuracy` is the share of hold-out days the model classified correctly;
/// `baseline` is what always guessing the majority class would have scored
/// on the same days. Only the improvement over that baseline counts as
/// skill: a model that is 90% accurate on days that are 90% migraine-free
/// has learned nothing.
struct MLModelValidation: Codable, Equatable {
    var accuracy: Double
    var baseline: Double
    var sampleCount: Int
    var evaluatedAt: Date

    /// `floor` when the model is no better than the baseline, rising toward
    /// `ceiling` with skill and with the size of the hold-out set (full credit
    /// at `fullCreditSampleCount` days, so a lucky 8-day hold-out cannot
    /// claim 90%).
    var confidence: Double {
        Self.confidence(accuracy: accuracy, baseline: baseline, sampleCount: sampleCount)
    }

    static let floor = 0.30
    static let ceiling = 0.90
    static let fullCreditSampleCount = 60

    /// Confidence to report for a model that exists but was trained before
    /// hold-out evaluation was recorded.
    static let unvalidated = 0.40

    static func confidence(accuracy: Double, baseline: Double, sampleCount: Int) -> Double {
        guard accuracy.isFinite, baseline.isFinite, sampleCount > 0, baseline < 1 else {
            return floor
        }
        let skill = min(max((accuracy - baseline) / (1 - baseline), 0), 1)
        let sizeFactor = min(Double(sampleCount) / Double(fullCreditSampleCount), 1)
        return min(max(floor + (ceiling - floor) * skill * sizeFactor, floor), ceiling)
    }

    /// Share of the most common label; the accuracy of always guessing it.
    static func majorityBaseline(labels: [Int]) -> Double {
        guard !labels.isEmpty else { return 1 }
        let positives = labels.filter { $0 != 0 }.count
        return Double(max(positives, labels.count - positives)) / Double(labels.count)
    }

    /// Chronological split so the model is judged on days after the ones it
    /// learned from, as it will be in use. Returns `nil` when either side
    /// would be too small to mean anything.
    static func chronologicalSplit<Row>(
        _ rows: [Row],
        holdOutFraction: Double = 0.2,
        minimumHoldOut: Int = 10,
        minimumTraining: Int = 20
    ) -> (training: [Row], holdOut: [Row])? {
        let holdOutCount = max(minimumHoldOut, Int((Double(rows.count) * holdOutFraction).rounded()))
        guard rows.count - holdOutCount >= minimumTraining else { return nil }
        return (Array(rows.prefix(rows.count - holdOutCount)), Array(rows.suffix(holdOutCount)))
    }
}
