//
//  AnalyticsModels.swift
//  NALI Migraine Log
//
//  Lightweight value types shared by the redesigned Analytics dashboard.
//  Kept separate from `StatisticsView` so tile / heatmap / insight subviews
//  can evolve independently without growing the main file further.
//

import SwiftUI

// MARK: - Severity buckets

/// Clinically meaningful pain ranges, used in place of the old 1-10 histogram.
/// Matches the ranges used elsewhere in the app (`painLevelColor`,
/// HealthKit headache severity mapping, notification copy).
enum SeverityBucket: String, CaseIterable, Identifiable, Hashable {
    case mild       // 1-3
    case moderate   // 4-6
    case severe     // 7-8
    case extremeBucket = "extreme" // 9-10  (avoid `extreme` keyword clashes)

    var id: String { rawValue }

    /// User-facing label.
    var title: String {
        switch self {
        case .mild:           return "Mild"
        case .moderate:       return "Moderate"
        case .severe:         return "Severe"
        case .extremeBucket:  return "Extreme"
        }
    }

    /// Subtitle shown under the bar, e.g. "1-3".
    var rangeDescription: String {
        switch self {
        case .mild:           return "1-3"
        case .moderate:       return "4-6"
        case .severe:         return "7-8"
        case .extremeBucket:  return "9-10"
        }
    }

    var color: Color {
        switch self {
        case .mild:           return .green
        case .moderate:       return .yellow
        case .severe:         return .orange
        case .extremeBucket:  return .red
        }
    }

    /// Maps a 1-10 pain level into the appropriate bucket. Returns `nil` for
    /// invalid values so callers can defensively skip them.
    static func bucket(for painLevel: Int) -> SeverityBucket? {
        switch painLevel {
        case 1...3:  return .mild
        case 4...6:  return .moderate
        case 7...8:  return .severe
        case 9...10: return .extremeBucket
        default:     return nil
        }
    }
}

/// Chartable count for a single severity bucket.
struct SeverityBucketPoint: Identifiable, Hashable {
    var id: SeverityBucket { bucket }
    let bucket: SeverityBucket
    let count: Int
}

// MARK: - Daily severity (heatmap)

/// One calendar day's worst migraine, used to drive the heatmap.
/// `worstPain` of 0 means a migraine-free day in the period.
struct DailyPainCell: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let worstPain: Int           // 0 if no migraine that day
    let migraineCount: Int       // multiple migraines in one day are possible

    var bucket: SeverityBucket? { SeverityBucket.bucket(for: worstPain) }
}

// MARK: - KPI metrics (drill-down)

/// Top-level KPI tiles in the dashboard. Each case is its own drill-down
/// destination via `AnalyticsMetricDetailView`.
enum AnalyticsMetric: String, CaseIterable, Identifiable, Hashable {
    case total
    case averagePain
    case severeDays
    case averageDuration
    case streak
    case topTrigger
    case topMedication
    case missedDays
    case sleepCorrelation
    case hrvCorrelation
    case cyclePhase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .total:             return "Total"
        case .averagePain:       return "Avg Pain"
        case .severeDays:        return "Severe Days"
        case .averageDuration:   return "Avg Duration"
        case .streak:            return "Streak"
        case .topTrigger:        return "Top Trigger"
        case .topMedication:     return "Top Medication"
        case .missedDays:        return "Days Missed"
        case .sleepCorrelation:  return "Sleep & Migraines"
        case .hrvCorrelation:    return "HRV & Migraines"
        case .cyclePhase:        return "Cycle & Migraines"
        }
    }

    /// SF Symbol shown in the tile header.
    var systemImage: String {
        switch self {
        case .total:             return "number.square.fill"
        case .averagePain:       return "waveform.path.ecg"
        case .severeDays:        return "exclamationmark.triangle.fill"
        case .averageDuration:   return "clock.fill"
        case .streak:            return "flame.fill"
        case .topTrigger:        return "bolt.fill"
        case .topMedication:     return "pill.fill"
        case .missedDays:        return "calendar.badge.exclamationmark"
        case .sleepCorrelation:  return "bed.double.fill"
        case .hrvCorrelation:    return "heart.text.square.fill"
        case .cyclePhase:        return "drop.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .total:             return Color(red: 68/255, green: 130/255, blue: 180/255)
        case .averagePain:       return .pink
        case .severeDays:        return .red
        case .averageDuration:   return .indigo
        case .streak:            return .green
        case .topTrigger:        return .blue
        case .topMedication:     return .purple
        case .missedDays:        return .orange
        case .sleepCorrelation:  return Color(red: 80/255, green: 110/255, blue: 200/255)
        case .hrvCorrelation:    return .teal
        case .cyclePhase:        return Color(red: 200/255, green: 80/255, blue: 110/255)
        }
    }
    
    /// True when this metric requires HealthKit data — used by the
    /// dashboard to skip showing tiles for these on devices/locales
    /// where HealthKit isn't authorized.
    var requiresHealthKit: Bool {
        switch self {
        case .sleepCorrelation, .hrvCorrelation, .cyclePhase: return true
        default: return false
        }
    }
}

// MARK: - Insight cards

/// Auto-generated, human-readable observation derived from the filtered data.
struct AnalyticsInsight: Identifiable, Hashable {
    enum Tone { case positive, neutral, alert }

    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let tone: Tone

    var tint: Color {
        switch tone {
        case .positive: return .green
        case .neutral:  return .blue
        case .alert:    return .orange
        }
    }
}
