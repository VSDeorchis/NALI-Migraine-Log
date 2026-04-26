//
//  FeatureExtractor.swift
//  NALI Migraine Log
//
//  Converts raw Core Data entries, weather, and HealthKit data into
//  a normalized feature vector for the prediction engine.
//

import Foundation
import CoreData

class FeatureExtractor {
    
    private let calendar = Calendar.current
    
    // MARK: - Public API
    
    /// Build a feature vector for the given moment using historical migraine data,
    /// the latest weather forecast, and optional HealthKit / daily check-in data.
    /// - Parameter referenceDate: The point in time to evaluate. Defaults to now.
    func extractFeatures(
        migraines: [MigraineEvent],
        currentWeather: WeatherSnapshot?,
        healthData: HealthKitSnapshot? = nil,
        dailyCheckIn: DailyCheckInData? = nil,
        referenceDate: Date = Date()
    ) -> MigraineFeatureVector {
        
        let now = referenceDate
        var features = MigraineFeatureVector()
        
        // ── Temporal ──────────────────────────────────────────────
        features.dayOfWeek       = calendar.component(.weekday, from: now) - 1 // 0-6
        features.hourOfDay       = calendar.component(.hour, from: now)
        features.monthOfYear     = calendar.component(.month, from: now)
        features.isWeekend       = calendar.isDateInWeekend(now)
        
        // ── Frequency / recency ───────────────────────────────────
        let sorted = migraines
            .compactMap { $0.startTime }
            .sorted(by: >)                   // most recent first
        
        if let lastDate = sorted.first {
            features.daysSinceLastMigraine =
                max(0, now.timeIntervalSince(lastDate) / 86_400)
        }
        
        let sevenDaysAgo  = calendar.date(byAdding: .day, value: -7, to: now)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        
        features.migrainesInLast7Days  = sorted.filter { $0 >= sevenDaysAgo }.count
        features.migrainesInLast30Days = sorted.filter { $0 >= thirtyDaysAgo }.count
        
        // Average pain of last 5 migraines
        let recentPain = migraines
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
            .prefix(5)
            .map { Double($0.painLevel) }
        if !recentPain.isEmpty {
            features.avgPainLevelLast5 = recentPain.reduce(0, +) / Double(recentPain.count)
        }
        
        // ── Weather ───────────────────────────────────────────────
        if let weather = currentWeather {
            features.pressureCurrent     = weather.pressure
            features.pressureChange24h   = weather.pressureChange24h
            features.pressureChangeRate  = weather.pressureChange24h / 24.0  // hPa/hr
            features.temperature         = weather.temperature
            features.precipitation       = weather.precipitation
            features.cloudCover          = weather.cloudCover
            features.weatherCode         = weather.weatherCode
        }
        
        // ── Trigger frequencies ───────────────────────────────────
        // Map each model feature to the canonical enum case so adding a new
        // trigger only requires touching one place (the enum + the feature
        // vector struct), not a parallel boolean ladder.
        let total = Double(max(migraines.count, 1))
        func freq(of trigger: MigraineTrigger) -> Double {
            Double(migraines.filter { $0.triggers.contains(trigger) }.count) / total
        }

        features.triggerStressFreq      = freq(of: .stress)
        features.triggerSleepFreq       = freq(of: .lackOfSleep)
        features.triggerDehydrationFreq = freq(of: .dehydration)
        features.triggerWeatherFreq     = freq(of: .weather)
        features.triggerHormonesFreq    = freq(of: .menstrual)
        features.triggerAlcoholFreq     = freq(of: .alcohol)
        features.triggerCaffeineFreq    = freq(of: .caffeine)
        features.triggerFoodFreq        = freq(of: .food)
        features.triggerExerciseFreq    = freq(of: .exercise)
        features.triggerScreenTimeFreq  = freq(of: .screenTime)

        // ── Medication rebound risk ───────────────────────────────
        let recentMigraines = migraines.filter {
            guard let d = $0.startTime else { return false }
            return d >= sevenDaysAgo
        }

        let triptans: Set<MigraineMedication> = [
            .sumatriptan, .rizatriptan, .eletriptan, .naratriptan, .frovatriptan
        ]
        let nsaids: Set<MigraineMedication> = [.ibuprofin, .naproxen, .excedrin]

        features.triptanUsesLast7Days = recentMigraines
            .filter { !$0.medications.isDisjoint(with: triptans) }
            .count
        features.nsaidUsesLast7Days = recentMigraines
            .filter { !$0.medications.isDisjoint(with: nsaids) }
            .count
        
        // ── HealthKit (optional) ──────────────────────────────────
        if let health = healthData {
            features.sleepHoursLastNight     = health.sleepHours
            features.hrvLastNight            = health.hrv
            features.restingHeartRate        = health.restingHeartRate
            features.stepsYesterday          = health.steps
            features.daysSinceMenstruation   = health.daysSinceMenstruation
        }
        
        // ── Daily check-in (optional) ─────────────────────────────
        if let checkIn = dailyCheckIn {
            features.selfReportedStress    = checkIn.stressLevel
            features.selfReportedHydration = checkIn.hydrationLevel
            features.selfReportedCaffeine  = checkIn.caffeineIntake
        }
        
        return features
    }
    
    // MARK: - Time-of-day pattern analysis
    
    /// Returns the probability of a migraine at each hour of the day
    /// based on historical distribution.
    func hourlyDistribution(from migraines: [MigraineEvent]) -> [Int: Double] {
        guard !migraines.isEmpty else { return [:] }
        
        var hourCounts: [Int: Int] = [:]
        for m in migraines {
            guard let d = m.startTime else { continue }
            let hour = calendar.component(.hour, from: d)
            hourCounts[hour, default: 0] += 1
        }
        
        let total = Double(migraines.count)
        var distribution: [Int: Double] = [:]
        for hour in 0..<24 {
            distribution[hour] = Double(hourCounts[hour] ?? 0) / total
        }
        return distribution
    }
    
    /// Returns the probability of a migraine on each day of the week.
    func dayOfWeekDistribution(from migraines: [MigraineEvent]) -> [Int: Double] {
        guard !migraines.isEmpty else { return [:] }
        
        var dayCounts: [Int: Int] = [:]
        for m in migraines {
            guard let d = m.startTime else { continue }
            let dow = calendar.component(.weekday, from: d) - 1  // 0-6
            dayCounts[dow, default: 0] += 1
        }
        
        let total = Double(migraines.count)
        var distribution: [Int: Double] = [:]
        for day in 0..<7 {
            distribution[day] = Double(dayCounts[day] ?? 0) / total
        }
        return distribution
    }
    
    /// Calculates average weather values during migraines that had weather data.
    func averageWeatherDuringMigraines(_ migraines: [MigraineEvent]) -> (
        avgPressureChange: Double,
        avgTemp: Double,
        avgPrecip: Double
    ) {
        let withWeather = migraines.filter(\.hasWeatherData)
        guard !withWeather.isEmpty else { return (0, 70, 0) }
        
        let n = Double(withWeather.count)
        let avgPC   = withWeather.reduce(0.0) { $0 + $1.weatherPressureChange24h } / n
        let avgTemp = withWeather.reduce(0.0) { $0 + $1.weatherTemperature } / n
        let avgPrec = withWeather.reduce(0.0) { $0 + $1.weatherPrecipitation } / n
        return (avgPC, avgTemp, avgPrec)
    }
}

// MARK: - Supporting Data Structures

/// Snapshot of HealthKit data used for feature extraction.
struct HealthKitSnapshot {
    var sleepHours: Double?
    var hrv: Double?
    var restingHeartRate: Double?
    var steps: Int?
    var daysSinceMenstruation: Int?
}

/// Snapshot of the user's daily check-in.
struct DailyCheckInData: Codable {
    var stressLevel: Int?       // 1-5
    var hydrationLevel: Int?    // 1-5
    var caffeineIntake: Int?    // cups
    var date: Date = Date()
    
    static var storageKey: String { "dailyCheckIn" }
    
    /// Save today's check-in to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    /// Load the most recent check-in (only valid for today).
    static func loadToday() -> DailyCheckInData? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let checkIn = try? JSONDecoder().decode(DailyCheckInData.self, from: data),
              Calendar.current.isDateInToday(checkIn.date) else {
            return nil
        }
        return checkIn
    }
}
