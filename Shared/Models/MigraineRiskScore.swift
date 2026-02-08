//
//  MigraineRiskScore.swift
//  NALI Migraine Log
//
//  Data model for migraine risk prediction results.
//

import Foundation
import SwiftUI

// MARK: - Risk Score Model

struct MigraineRiskScore {
    let overallRisk: Double              // 0.0 to 1.0
    let riskLevel: RiskLevel
    let topFactors: [RiskFactor]
    let recommendations: [String]
    let confidence: Double               // 0.0 to 1.0
    let predictionSource: PredictionSource
    let timestamp: Date
    
    var riskPercentage: Int {
        Int(overallRisk * 100)
    }
}

// MARK: - Risk Level

enum RiskLevel: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case veryHigh = "Very High"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "checkmark.shield.fill"
        case .moderate: return "exclamationmark.shield.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .veryHigh: return "xmark.shield.fill"
        }
    }
    
    static func from(risk: Double) -> RiskLevel {
        switch risk {
        case 0..<0.25: return .low
        case 0.25..<0.50: return .moderate
        case 0.50..<0.75: return .high
        default: return .veryHigh
        }
    }
}

// MARK: - Risk Factor

struct RiskFactor: Identifiable {
    let id = UUID()
    let name: String
    let contribution: Double   // 0.0 to 1.0
    let icon: String
    let color: Color
    let detail: String
    
    var contributionPercentage: Int {
        Int(contribution * 100)
    }
}

// MARK: - Prediction Source

enum PredictionSource: String {
    case ruleBased = "Pattern Analysis"
    case machineLearning = "Personalized ML Model"
    case hybrid = "Hybrid Analysis"
    
    var description: String { rawValue }
    
    var icon: String {
        switch self {
        case .ruleBased: return "brain"
        case .machineLearning: return "cpu"
        case .hybrid: return "brain.head.profile"
        }
    }
}

// MARK: - Feature Vector

/// Normalized feature vector for ML input
struct MigraineFeatureVector {
    // Temporal
    var dayOfWeek: Int = 0              // 0-6
    var hourOfDay: Int = 0              // 0-23
    var monthOfYear: Int = 1            // 1-12
    var isWeekend: Bool = false
    
    // Frequency
    var daysSinceLastMigraine: Double = 30.0
    var migrainesInLast7Days: Int = 0
    var migrainesInLast30Days: Int = 0
    var avgPainLevelLast5: Double = 0.0
    
    // Weather
    var pressureCurrent: Double = 1013.0      // hPa
    var pressureChange24h: Double = 0.0       // hPa
    var pressureChangeRate: Double = 0.0      // hPa/hr
    var temperature: Double = 70.0            // F
    var precipitation: Double = 0.0
    var cloudCover: Int = 0
    var weatherCode: Int = 0
    var humidity: Double = 50.0
    
    // Trigger frequencies (from historical data)
    var triggerStressFreq: Double = 0.0       // 0-1
    var triggerSleepFreq: Double = 0.0
    var triggerDehydrationFreq: Double = 0.0
    var triggerWeatherFreq: Double = 0.0
    var triggerHormonesFreq: Double = 0.0
    var triggerAlcoholFreq: Double = 0.0
    var triggerCaffeineFreq: Double = 0.0
    var triggerFoodFreq: Double = 0.0
    var triggerExerciseFreq: Double = 0.0
    var triggerScreenTimeFreq: Double = 0.0
    
    // HealthKit (optional, defaults to neutral values)
    var sleepHoursLastNight: Double? = nil
    var hrvLastNight: Double? = nil
    var restingHeartRate: Double? = nil
    var stepsYesterday: Int? = nil
    var daysSinceMenstruation: Int? = nil
    
    // Daily check-in (optional)
    var selfReportedStress: Int? = nil       // 1-5
    var selfReportedHydration: Int? = nil    // 1-5
    var selfReportedCaffeine: Int? = nil     // cups
    
    // Medication rebound
    var triptanUsesLast7Days: Int = 0
    var nsaidUsesLast7Days: Int = 0
    
    /// Convert to dictionary for CoreML input
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "dayOfWeek": dayOfWeek,
            "hourOfDay": hourOfDay,
            "monthOfYear": monthOfYear,
            "isWeekend": isWeekend ? 1 : 0,
            "daysSinceLastMigraine": daysSinceLastMigraine,
            "migrainesInLast7Days": migrainesInLast7Days,
            "migrainesInLast30Days": migrainesInLast30Days,
            "avgPainLevelLast5": avgPainLevelLast5,
            "pressureCurrent": pressureCurrent,
            "pressureChange24h": pressureChange24h,
            "pressureChangeRate": pressureChangeRate,
            "temperature": temperature,
            "precipitation": precipitation,
            "cloudCover": cloudCover,
            "weatherCode": weatherCode,
            "triggerStressFreq": triggerStressFreq,
            "triggerSleepFreq": triggerSleepFreq,
            "triggerDehydrationFreq": triggerDehydrationFreq,
            "triggerWeatherFreq": triggerWeatherFreq,
            "triggerHormonesFreq": triggerHormonesFreq,
            "triggerAlcoholFreq": triggerAlcoholFreq,
            "triggerCaffeineFreq": triggerCaffeineFreq,
            "triggerFoodFreq": triggerFoodFreq,
            "triggerExerciseFreq": triggerExerciseFreq,
            "triggerScreenTimeFreq": triggerScreenTimeFreq,
            "triptanUsesLast7Days": triptanUsesLast7Days,
            "nsaidUsesLast7Days": nsaidUsesLast7Days
        ]
        
        // Optional HealthKit features
        if let sleep = sleepHoursLastNight { dict["sleepHoursLastNight"] = sleep }
        if let hrv = hrvLastNight { dict["hrvLastNight"] = hrv }
        if let rhr = restingHeartRate { dict["restingHeartRate"] = rhr }
        if let steps = stepsYesterday { dict["stepsYesterday"] = steps }
        if let menstruation = daysSinceMenstruation { dict["daysSinceMenstruation"] = menstruation }
        
        // Optional daily check-in
        if let stress = selfReportedStress { dict["selfReportedStress"] = stress }
        if let hydration = selfReportedHydration { dict["selfReportedHydration"] = hydration }
        if let caffeine = selfReportedCaffeine { dict["selfReportedCaffeine"] = caffeine }
        
        return dict
    }
}

// MARK: - Hourly Risk Forecast

struct HourlyRiskForecast: Identifiable {
    let id = UUID()
    let hour: Int               // 0-23
    let risk: Double            // 0.0 to 1.0
    let primaryFactor: String
}
