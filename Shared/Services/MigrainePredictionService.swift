//
//  MigrainePredictionService.swift
//  NALI Migraine Log
//
//  Central prediction engine using a two-tier architecture:
//    Tier 1 – Rule-based risk scoring (works immediately, even with 0 entries)
//    Tier 2 – On-device CoreML model (activates after 20+ entries)
//

import Foundation
import CoreData
import CoreML
import SwiftUI
#if canImport(CreateML)
import CreateML
#endif

@MainActor
class MigrainePredictionService: ObservableObject {
    static let shared = MigrainePredictionService()
    
    // MARK: - Published State
    
    @Published var currentRisk: MigraineRiskScore?
    @Published var hourlyForecast: [HourlyRiskForecast] = []
    @Published var isCalculating = false
    @Published var lastError: Error?
    @Published var modelStatus: ModelStatus = .ruleBased
    
    enum ModelStatus: Equatable {
        case ruleBased
        case trainingML(progress: Double)
        case mlActive(confidence: Double)
        case mlFailed
    }
    
    // MARK: - Dependencies
    
    private let featureExtractor = FeatureExtractor()
    
    // Minimum entries before ML model can be trained
    private let mlMinimumEntries = 20
    
    // MARK: - Tier 1 Weights (evidence-based)
    
    private struct RiskWeights {
        // Weather
        static let pressureDropLarge: Double    = 0.25   // > 5 hPa drop in 24h
        static let pressureDropModerate: Double = 0.15   // 3-5 hPa drop
        static let weatherChange: Double        = 0.10   // rain after clear, etc.
        static let highHumidity: Double         = 0.05   // > 80%
        
        // Sleep
        static let poorSleep: Double            = 0.20   // < 6 hours
        static let veryPoorSleep: Double        = 0.25   // < 5 hours
        
        // Frequency
        static let highRecentFrequency: Double  = 0.15   // 3+ in last 7 days
        static let recentMigraine: Double       = 0.10   // within last 2 days
        
        // Stress / autonomic
        static let highStress: Double           = 0.15   // self-reported >= 4
        static let lowHRV: Double               = 0.12   // HRV < 30ms
        static let elevatedRHR: Double          = 0.08   // RHR > 80 bpm
        
        // Hormonal
        static let menstrualWindow: Double      = 0.15   // days 1-3 of cycle
        
        // Medication rebound
        static let triptanRebound: Double       = 0.12   // triptans 3+ times/week
        static let nsaidRebound: Double         = 0.10   // NSAIDs 4+ times/week
        
        // Behavioral
        static let dehydration: Double          = 0.10   // hydration <= 2
        static let highCaffeine: Double         = 0.08   // > 4 cups
        static let lowActivity: Double          = 0.05   // < 2000 steps
        
        // Temporal patterns
        static let weekendEffect: Double        = 0.05   // schedule change
        static let peakHour: Double             = 0.08   // historical peak hour
        static let peakDayOfWeek: Double        = 0.05   // historical peak day
        
        // Personal trigger history
        static let highTriggerFreq: Double      = 0.10   // trigger present in > 40% of migraines
    }
    
    // MARK: - Public API
    
    /// Calculate the current migraine risk score.
    func calculateRiskScore(
        migraines: [MigraineEvent],
        currentWeather: WeatherSnapshot? = nil,
        healthData: HealthKitSnapshot? = nil,
        dailyCheckIn: DailyCheckInData? = nil
    ) async -> MigraineRiskScore {
        isCalculating = true
        defer { isCalculating = false }
        
        let features = featureExtractor.extractFeatures(
            migraines: migraines,
            currentWeather: currentWeather,
            healthData: healthData,
            dailyCheckIn: dailyCheckIn
        )
        
        // Always compute rule-based score
        let ruleScore = computeRuleBasedScore(features: features, migraines: migraines)
        
        // Try ML if we have enough data
        let finalScore: MigraineRiskScore
        if migraines.count >= mlMinimumEntries {
            if let mlScore = computeMLScore(features: features, migraines: migraines) {
                // Hybrid: blend rule-based and ML scores
                let blended = blendScores(rule: ruleScore, ml: mlScore)
                finalScore = blended
            } else {
                finalScore = ruleScore
            }
        } else {
            finalScore = ruleScore
        }
        
        currentRisk = finalScore
        return finalScore
    }
    
    /// Generate 24-hour risk forecast using upcoming weather data.
    func generate24HourForecast(
        migraines: [MigraineEvent],
        forecastHours: [ForecastHour],
        healthData: HealthKitSnapshot? = nil,
        dailyCheckIn: DailyCheckInData? = nil
    ) -> [HourlyRiskForecast] {
        // Don't generate a forecast with no migraine history
        guard !migraines.isEmpty else {
            hourlyForecast = []
            return []
        }
        
        let now = Date()
        let upcoming = forecastHours
            .filter { $0.date >= now }
            .prefix(24)
        
        var forecasts: [HourlyRiskForecast] = []
        
        for hour in upcoming {
            // Create a synthetic weather snapshot for each forecast hour
            let snapshot = WeatherSnapshot(
                timestamp: hour.date,
                temperature: hour.temperature,
                pressure: hour.pressure,
                pressureChange24h: hour.pressureChange,
                precipitation: hour.precipitation,
                cloudCover: hour.cloudCover,
                weatherCode: hour.weatherCode,
                weatherCondition: hour.weatherCondition,
                weatherIcon: hour.weatherIcon
            )
            
            let features = featureExtractor.extractFeatures(
                migraines: migraines,
                currentWeather: snapshot,
                healthData: healthData,
                dailyCheckIn: dailyCheckIn,
                referenceDate: hour.date
            )
            
            let score = computeRuleBasedScore(features: features, migraines: migraines)
            
            forecasts.append(HourlyRiskForecast(
                hour: hour.hour,
                risk: score.overallRisk,
                primaryFactor: score.topFactors.first?.name ?? "General"
            ))
        }
        
        hourlyForecast = forecasts
        return forecasts
    }
    
    // MARK: - Tier 1: Rule-Based Scoring
    
    private func computeRuleBasedScore(
        features: MigraineFeatureVector,
        migraines: [MigraineEvent]
    ) -> MigraineRiskScore {
        
        // ── Insufficient data guard ────────────────────────────────
        // With no migraine history, we have no basis for a meaningful prediction.
        if migraines.isEmpty {
            return MigraineRiskScore(
                overallRisk: 0.0,
                riskLevel: .low,
                topFactors: [],
                recommendations: ["Log your first migraine to start building your personal risk profile."],
                confidence: 0.0,
                predictionSource: .ruleBased,
                timestamp: Date()
            )
        }
        
        var totalRisk: Double = 0.0
        var factors: [RiskFactor] = []
        var recommendations: [String] = []
        
        // ── Weather Factors ──────────────────────────────────────
        
        let pressureDrop = -features.pressureChange24h  // positive = pressure dropped
        
        if pressureDrop > 5 {
            let contribution = RiskWeights.pressureDropLarge
            totalRisk += contribution
            factors.append(RiskFactor(
                name: "Rapid Pressure Drop",
                contribution: contribution,
                icon: "arrow.down.to.line",
                color: .red,
                detail: "Barometric pressure dropped \(String(format: "%.1f", pressureDrop)) hPa in 24 hours"
            ))
            recommendations.append("A significant barometric pressure drop is detected. Consider preventive medication if your doctor has prescribed one.")
        } else if pressureDrop > 3 {
            let contribution = RiskWeights.pressureDropModerate
            totalRisk += contribution
            factors.append(RiskFactor(
                name: "Moderate Pressure Drop",
                contribution: contribution,
                icon: "arrow.down",
                color: .orange,
                detail: "Pressure dropped \(String(format: "%.1f", pressureDrop)) hPa in 24 hours"
            ))
        }
        
        // Weather change (stormy conditions)
        if features.weatherCode >= 61 {
            let contribution = RiskWeights.weatherChange
            totalRisk += contribution
            factors.append(RiskFactor(
                name: "Adverse Weather",
                contribution: contribution,
                icon: "cloud.rain.fill",
                color: .blue,
                detail: "Current or forecast weather may be a trigger"
            ))
        }
        
        // ── Sleep Factors ────────────────────────────────────────
        
        if let sleep = features.sleepHoursLastNight {
            if sleep < 5 {
                totalRisk += RiskWeights.veryPoorSleep
                factors.append(RiskFactor(
                    name: "Very Poor Sleep",
                    contribution: RiskWeights.veryPoorSleep,
                    icon: "moon.zzz.fill",
                    color: .red,
                    detail: "Only \(String(format: "%.1f", sleep)) hours of sleep last night"
                ))
                recommendations.append("You had very little sleep. Try to rest when possible and stay hydrated.")
            } else if sleep < 6 {
                totalRisk += RiskWeights.poorSleep
                factors.append(RiskFactor(
                    name: "Poor Sleep",
                    contribution: RiskWeights.poorSleep,
                    icon: "moon.fill",
                    color: .orange,
                    detail: "\(String(format: "%.1f", sleep)) hours of sleep last night"
                ))
                recommendations.append("Consider getting extra rest today to reduce migraine risk.")
            }
        }
        
        // ── Frequency Factors ────────────────────────────────────
        
        if features.migrainesInLast7Days >= 3 {
            totalRisk += RiskWeights.highRecentFrequency
            factors.append(RiskFactor(
                name: "High Recent Frequency",
                contribution: RiskWeights.highRecentFrequency,
                icon: "chart.line.uptrend.xyaxis",
                color: .red,
                detail: "\(features.migrainesInLast7Days) migraines in the last 7 days"
            ))
            recommendations.append("Your migraine frequency is elevated. Consider contacting your healthcare provider if this pattern continues.")
        }
        
        if features.daysSinceLastMigraine < 2 {
            totalRisk += RiskWeights.recentMigraine
            factors.append(RiskFactor(
                name: "Recent Migraine",
                contribution: RiskWeights.recentMigraine,
                icon: "clock.arrow.circlepath",
                color: .orange,
                detail: "Migraine occurred within the last 2 days"
            ))
        }
        
        // ── Stress / Autonomic ───────────────────────────────────
        
        if let stress = features.selfReportedStress, stress >= 4 {
            totalRisk += RiskWeights.highStress
            factors.append(RiskFactor(
                name: "High Stress",
                contribution: RiskWeights.highStress,
                icon: "brain.head.profile",
                color: .orange,
                detail: "Self-reported stress level: \(stress)/5"
            ))
            recommendations.append("Your stress level is high. Try relaxation techniques like deep breathing or a short walk.")
        }
        
        if let hrv = features.hrvLastNight, hrv < 30 {
            totalRisk += RiskWeights.lowHRV
            factors.append(RiskFactor(
                name: "Low Heart Rate Variability",
                contribution: RiskWeights.lowHRV,
                icon: "heart.text.square",
                color: .orange,
                detail: "HRV: \(String(format: "%.0f", hrv)) ms (below normal)"
            ))
        }
        
        if let rhr = features.restingHeartRate, rhr > 80 {
            totalRisk += RiskWeights.elevatedRHR
            factors.append(RiskFactor(
                name: "Elevated Resting Heart Rate",
                contribution: RiskWeights.elevatedRHR,
                icon: "heart.fill",
                color: .orange,
                detail: "Resting HR: \(Int(rhr)) bpm"
            ))
        }
        
        // ── Hormonal ─────────────────────────────────────────────
        
        if let days = features.daysSinceMenstruation, days <= 3 {
            totalRisk += RiskWeights.menstrualWindow
            factors.append(RiskFactor(
                name: "Menstrual Window",
                contribution: RiskWeights.menstrualWindow,
                icon: "drop.fill",
                color: .pink,
                detail: "Day \(days) of menstrual cycle — a known trigger window"
            ))
            recommendations.append("Hormonal changes around menstruation are a common migraine trigger. Consider preventive strategies.")
        }
        
        // ── Medication Rebound ───────────────────────────────────
        
        if features.triptanUsesLast7Days >= 3 {
            totalRisk += RiskWeights.triptanRebound
            factors.append(RiskFactor(
                name: "Triptan Overuse Risk",
                contribution: RiskWeights.triptanRebound,
                icon: "pills.fill",
                color: .red,
                detail: "Triptans used \(features.triptanUsesLast7Days) times this week (limit: 2-3)"
            ))
            recommendations.append("Frequent triptan use can cause medication overuse headaches. Discuss with your doctor.")
        }
        
        if features.nsaidUsesLast7Days >= 4 {
            totalRisk += RiskWeights.nsaidRebound
            factors.append(RiskFactor(
                name: "NSAID Overuse Risk",
                contribution: RiskWeights.nsaidRebound,
                icon: "pills.circle",
                color: .orange,
                detail: "NSAIDs used \(features.nsaidUsesLast7Days) times this week"
            ))
        }
        
        // ── Behavioral ───────────────────────────────────────────
        
        if let hydration = features.selfReportedHydration, hydration <= 2 {
            totalRisk += RiskWeights.dehydration
            factors.append(RiskFactor(
                name: "Low Hydration",
                contribution: RiskWeights.dehydration,
                icon: "drop.triangle.fill",
                color: .blue,
                detail: "Hydration level: \(hydration)/5"
            ))
            recommendations.append("Stay hydrated — drink water regularly throughout the day.")
        }
        
        if let caffeine = features.selfReportedCaffeine, caffeine > 4 {
            totalRisk += RiskWeights.highCaffeine
            factors.append(RiskFactor(
                name: "High Caffeine",
                contribution: RiskWeights.highCaffeine,
                icon: "cup.and.saucer.fill",
                color: .brown,
                detail: "\(caffeine) cups of caffeine today"
            ))
        }
        
        if let steps = features.stepsYesterday, steps < 2000 {
            totalRisk += RiskWeights.lowActivity
            factors.append(RiskFactor(
                name: "Low Activity",
                contribution: RiskWeights.lowActivity,
                icon: "figure.walk",
                color: .gray,
                detail: "Only \(steps) steps yesterday"
            ))
        }
        
        // ── Temporal Patterns ────────────────────────────────────
        
        if features.isWeekend {
            totalRisk += RiskWeights.weekendEffect
            factors.append(RiskFactor(
                name: "Weekend Schedule Change",
                contribution: RiskWeights.weekendEffect,
                icon: "calendar",
                color: .purple,
                detail: "Weekend schedule changes can trigger migraines"
            ))
        }
        
        // Historical peak hour
        let hourDist = featureExtractor.hourlyDistribution(from: migraines)
        if let peakProb = hourDist[features.hourOfDay], peakProb > 0.15 {
            totalRisk += RiskWeights.peakHour
            factors.append(RiskFactor(
                name: "Peak Time Window",
                contribution: RiskWeights.peakHour,
                icon: "clock.fill",
                color: .indigo,
                detail: "\(Int(peakProb * 100))% of your migraines occur around this hour"
            ))
        }
        
        // Historical peak day of week
        let dowDist = featureExtractor.dayOfWeekDistribution(from: migraines)
        if let peakDow = dowDist[features.dayOfWeek], peakDow > 0.20 {
            totalRisk += RiskWeights.peakDayOfWeek
            factors.append(RiskFactor(
                name: "High-Risk Day",
                contribution: RiskWeights.peakDayOfWeek,
                icon: "calendar.badge.exclamationmark",
                color: .indigo,
                detail: "\(Int(peakDow * 100))% of your migraines occur on this day"
            ))
        }
        
        // ── Personal trigger frequency ───────────────────────────
        
        let triggerPairs: [(name: String, freq: Double, icon: String)] = [
            ("Stress",       features.triggerStressFreq,      "brain"),
            ("Lack of Sleep", features.triggerSleepFreq,      "bed.double.fill"),
            ("Dehydration",  features.triggerDehydrationFreq, "drop.fill"),
            ("Weather",      features.triggerWeatherFreq,     "cloud.sun.rain.fill"),
            ("Menstrual",    features.triggerHormonesFreq,    "waveform.path.ecg"),
            ("Alcohol",      features.triggerAlcoholFreq,     "wineglass.fill"),
            ("Caffeine",     features.triggerCaffeineFreq,    "cup.and.saucer.fill"),
            ("Food",         features.triggerFoodFreq,        "fork.knife"),
            ("Exercise",     features.triggerExerciseFreq,    "figure.run"),
            ("Screen Time",  features.triggerScreenTimeFreq,  "desktopcomputer"),
        ]
        
        let highFreqTriggers = triggerPairs.filter { $0.freq > 0.40 }
        for trigger in highFreqTriggers.prefix(3) { // limit to top 3
            totalRisk += RiskWeights.highTriggerFreq
            factors.append(RiskFactor(
                name: "\(trigger.name) Trigger Pattern",
                contribution: RiskWeights.highTriggerFreq,
                icon: trigger.icon,
                color: .teal,
                detail: "Present in \(Int(trigger.freq * 100))% of your migraines"
            ))
        }
        
        // ── Clamp & Build Score ──────────────────────────────────
        
        let clampedRisk = min(max(totalRisk, 0.0), 1.0)
        let level = RiskLevel.from(risk: clampedRisk)
        
        // Sort factors by contribution (highest first)
        let sortedFactors = factors.sorted { $0.contribution > $1.contribution }
        
        // Add default recommendation if risk is low
        if recommendations.isEmpty {
            if clampedRisk < 0.25 {
                recommendations.append("Your migraine risk is currently low. Keep up your healthy habits!")
            } else {
                recommendations.append("Monitor your triggers and stay hydrated today.")
            }
        }
        
        // Confidence based on data available
        let confidence = computeConfidence(
            migraineCount: migraines.count,
            hasWeather: features.pressureCurrent != 1013.0,
            hasHealth: features.sleepHoursLastNight != nil,
            hasCheckIn: features.selfReportedStress != nil
        )
        
        return MigraineRiskScore(
            overallRisk: clampedRisk,
            riskLevel: level,
            topFactors: Array(sortedFactors.prefix(6)),
            recommendations: recommendations,
            confidence: confidence,
            predictionSource: .ruleBased,
            timestamp: Date()
        )
    }
    
    // MARK: - Tier 2: CoreML (Placeholder for on-device training)
    
    /// Attempts to compute risk using a locally-trained CoreML model.
    /// Returns nil if no model is available, training hasn't completed,
    /// or the platform doesn't support on-device CoreML compilation (watchOS).
    private func computeMLScore(
        features: MigraineFeatureVector,
        migraines: [MigraineEvent]
    ) -> MigraineRiskScore? {
        #if os(watchOS)
        // MLModel.compileModel(at:) is unavailable on watchOS
        Task { await trainModelIfNeeded(migraines: migraines) }
        return nil
        #else
        // Check if a trained model exists
        guard let modelURL = getTrainedModelURL(),
              FileManager.default.fileExists(atPath: modelURL.path) else {
            // No model trained yet — trigger training in background
            Task { await trainModelIfNeeded(migraines: migraines) }
            return nil
        }
        
        do {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            let model = try MLModel(contentsOf: compiledURL)
            
            let input = try MLDictionaryFeatureProvider(dictionary: features.toDictionary())
            let prediction = try model.prediction(from: input)
            
            // The model should output "migraineRisk" as a Double
            guard let riskValue = prediction.featureValue(for: "migraineRisk")?.doubleValue else {
                return nil
            }
            
            let clampedRisk = min(max(riskValue, 0.0), 1.0)
            let level = RiskLevel.from(risk: clampedRisk)
            
            modelStatus = .mlActive(confidence: 0.75)
            
            return MigraineRiskScore(
                overallRisk: clampedRisk,
                riskLevel: level,
                topFactors: [],   // ML doesn't provide explainability by default
                recommendations: [],
                confidence: 0.75,
                predictionSource: .machineLearning,
                timestamp: Date()
            )
        } catch {
            print("⚠️ CoreML prediction failed: \(error.localizedDescription)")
            modelStatus = .mlFailed
            return nil
        }
        #endif
    }
    
    /// Blends rule-based and ML scores.
    private func blendScores(rule: MigraineRiskScore, ml: MigraineRiskScore) -> MigraineRiskScore {
        // Weight the ML score more as confidence grows
        let mlWeight = ml.confidence * 0.6
        let ruleWeight = 1.0 - mlWeight
        
        let blendedRisk = rule.overallRisk * ruleWeight + ml.overallRisk * mlWeight
        let clampedRisk = min(max(blendedRisk, 0.0), 1.0)
        let level = RiskLevel.from(risk: clampedRisk)
        
        return MigraineRiskScore(
            overallRisk: clampedRisk,
            riskLevel: level,
            topFactors: rule.topFactors,         // Use rule-based explanations
            recommendations: rule.recommendations,
            confidence: max(rule.confidence, ml.confidence),
            predictionSource: .hybrid,
            timestamp: Date()
        )
    }
    
    // MARK: - ML Training
    
    /// Trains a simple boosted tree classifier on the user's data.
    /// This runs periodically or when enough new data is available.
    /// CreateML is only available on iOS 15.4+ and macOS — not on watchOS.
    private func trainModelIfNeeded(migraines: [MigraineEvent]) async {
        #if canImport(CreateML)
        guard migraines.count >= mlMinimumEntries else { return }
        
        // Check if we already trained recently
        let lastTrainKey = "lastMLTrainDate"
        if let lastTrain = UserDefaults.standard.object(forKey: lastTrainKey) as? Date,
           Date().timeIntervalSince(lastTrain) < 7 * 86_400 { // once per week
            return
        }
        
        modelStatus = .trainingML(progress: 0.0)
        
        do {
            // Build training data: for each migraine, look at conditions 24h before
            let trainingData = buildTrainingData(from: migraines)
            
            guard trainingData.count >= mlMinimumEntries else {
                modelStatus = .ruleBased
                return
            }
            
            // Write CSV for CreateML
            let csvURL = getTrainingDataURL()
            try writeCSV(trainingData, to: csvURL)
            
            modelStatus = .trainingML(progress: 0.5)
            
            // Use MLBoostedTreeClassifier (iOS 15.4+, macOS 12+)
            let dataSource = try MLDataTable(contentsOf: csvURL)
            let classifier = try MLBoostedTreeClassifier(
                trainingData: dataSource,
                targetColumn: "hadMigraine"
            )
            
            modelStatus = .trainingML(progress: 0.9)
            
            let modelURL = getTrainedModelURL()!
            try classifier.write(to: modelURL)
            
            UserDefaults.standard.set(Date(), forKey: lastTrainKey)
            modelStatus = .mlActive(confidence: 0.70)
            
            print("✅ ML model trained successfully with \(trainingData.count) samples")
        } catch {
            print("⚠️ ML training failed: \(error.localizedDescription)")
            modelStatus = .mlFailed
        }
        #else
        // CreateML not available on this platform (watchOS)
        print("ℹ️ ML training is not available on this platform")
        #endif
    }
    
    // MARK: - Training Data Preparation
    
    private func buildTrainingData(from migraines: [MigraineEvent]) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        let calendar = Calendar.current
        
        // Sort by date
        let sorted = migraines.sorted { ($0.startTime ?? .distantPast) < ($1.startTime ?? .distantPast) }
        
        guard let firstDate = sorted.first?.startTime,
              let lastDate = sorted.last?.startTime else { return rows }
        
        // Iterate over each day in the range
        var currentDate = firstDate
        while currentDate <= lastDate {
            let hadMigraine = sorted.contains { m in
                guard let d = m.startTime else { return false }
                return calendar.isDate(d, inSameDayAs: currentDate)
            }
            
            // Extract features for this date
            let priorMigraines = sorted.filter { ($0.startTime ?? .distantPast) < currentDate }
            let features = featureExtractor.extractFeatures(
                migraines: priorMigraines,
                currentWeather: nil
            )
            
            var row = features.toDictionary()
            row["hadMigraine"] = hadMigraine ? 1 : 0
            rows.append(row)
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return rows
    }
    
    private func writeCSV(_ data: [[String: Any]], to url: URL) throws {
        guard let first = data.first else { return }
        let keys = first.keys.sorted()
        
        var csv = keys.joined(separator: ",") + "\n"
        for row in data {
            let values = keys.map { "\(row[$0] ?? "")" }
            csv += values.joined(separator: ",") + "\n"
        }
        
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - File Paths
    
    private func getTrainedModelURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("MigrainePredictor.mlmodel")
    }
    
    private func getTrainingDataURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("training_data.csv")
    }
    
    // MARK: - Confidence Calculation
    
    private func computeConfidence(
        migraineCount: Int,
        hasWeather: Bool,
        hasHealth: Bool,
        hasCheckIn: Bool
    ) -> Double {
        var confidence = 0.30  // baseline with any data
        
        // More historical data = higher confidence
        switch migraineCount {
        case 0:       confidence = 0.10
        case 1...5:   confidence += 0.10
        case 6...15:  confidence += 0.20
        case 16...30: confidence += 0.30
        default:      confidence += 0.40
        }
        
        // Additional data sources improve confidence
        if hasWeather  { confidence += 0.10 }
        if hasHealth   { confidence += 0.10 }
        if hasCheckIn  { confidence += 0.05 }
        
        return min(confidence, 0.95)
    }
}
