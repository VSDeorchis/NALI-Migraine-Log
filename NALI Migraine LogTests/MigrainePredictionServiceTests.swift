//
//  MigrainePredictionServiceTests.swift
//  NALI Migraine LogTests
//
//  Behaviour tests for the rule-based scoring tier of `MigrainePredictionService`.
//  The ML tier (`computeMLScore`) is intentionally not exercised here because:
//
//   * It depends on a trained `MigrainePredictor.mlmodel` file that lives in
//     the user's Documents directory and is only produced after 20+ entries.
//   * `CreateML` is unavailable on watchOS, so any test that *requires* the
//     ML path would be platform-conditional and brittle.
//
//  Instead we lock down the rule-based contract: the empty-history guard,
//  monotonicity (more risk inputs => higher or equal score), the [0, 1]
//  clamp, and the predictionSource label. Together with the
//  `FeatureExtractorTests` suite, these regressions cover the signal path
//  end-to-end without booting CoreML.
//

import Testing
import CoreData
import Foundation
@testable import NALI_Migraine_Log

@Suite("MigrainePredictionService — rule-based tier", .serialized)
@MainActor
struct MigrainePredictionServiceTests {

    private var context: NSManagedObjectContext {
        PersistenceController.preview.container.viewContext
    }

    private var referenceDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 25; c.hour = 17
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeEvent(
        startDaysAgo: Int,
        painLevel: Int = 5,
        triggers: Set<MigraineTrigger> = [],
        medications: Set<MigraineMedication> = []
    ) -> MigraineEvent {
        let event = MigraineEvent(context: context)
        event.id = UUID()
        event.startTime = referenceDate.addingTimeInterval(TimeInterval(-startDaysAgo) * 86_400)
        event.painLevel = Int16(painLevel)
        event.triggers = triggers
        event.medications = medications
        return event
    }

    private func wipeEvents() {
        let request: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        if let events = try? context.fetch(request) {
            for event in events { context.delete(event) }
        }
    }

    private func makeWeather(
        pressure: Double = 1013,
        pressureChange24h: Double = 0,
        weatherCode: Int = 0
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            timestamp: referenceDate,
            temperature: 70,
            pressure: pressure,
            pressureChange24h: pressureChange24h,
            precipitation: 0,
            cloudCover: 0,
            weatherCode: weatherCode,
            weatherCondition: "Test",
            weatherIcon: "cloud"
        )
    }

    // MARK: - Empty-history guard

    @Test("Empty migraine history returns 0 risk and a coaching recommendation")
    func emptyHistoryProducesZeroRisk() async {
        wipeEvents()
        let service = MigrainePredictionService.shared
        let score = await service.calculateRiskScore(migraines: [])

        #expect(score.overallRisk == 0.0)
        #expect(score.riskLevel == .low)
        #expect(score.confidence == 0.0)
        #expect(score.predictionSource == .ruleBased)
        #expect(score.topFactors.isEmpty)
        #expect(!score.recommendations.isEmpty,
                "Empty-history users must always get a 'log your first migraine' nudge")
    }

    // MARK: - Score is always clamped to [0, 1]

    @Test("Risk score is always clamped between 0 and 1, even with stacked risk factors")
    func riskIsClampedToUnitInterval() async {
        wipeEvents()
        // Pile on every conceivable risk: large pressure drop, stormy weather,
        // recent migraine, high-frequency week, triptan/NSAID overuse, and
        // an obvious trigger pattern. The raw sum exceeds 1.0; the public
        // contract is that the user-facing score never does.
        for daysAgo in [1, 2, 3, 4, 5] {
            makeEvent(
                startDaysAgo: daysAgo,
                painLevel: 9,
                triggers: [.stress, .lackOfSleep],
                medications: [.sumatriptan, .ibuprofin]
            )
        }
        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let weather = makeWeather(
            pressure: 990,
            pressureChange24h: -15,   // huge drop
            weatherCode: 95           // thunderstorm
        )
        let health = HealthKitSnapshot(
            sleepHours: 3.0,          // very poor sleep
            hrv: 22,                  // low HRV
            restingHeartRate: 90,     // elevated RHR
            steps: 500,               // low activity
            daysSinceMenstruation: 1
        )
        var checkIn = DailyCheckInData()
        checkIn.stressLevel = 5
        checkIn.hydrationLevel = 1
        checkIn.caffeineIntake = 6

        let service = MigrainePredictionService.shared
        let score = await service.calculateRiskScore(
            migraines: events,
            currentWeather: weather,
            healthData: health,
            dailyCheckIn: checkIn
        )

        #expect(score.overallRisk <= 1.0, "Risk must clamp to ≤ 1.0, got \(score.overallRisk)")
        #expect(score.overallRisk >= 0.0, "Risk must be non-negative, got \(score.overallRisk)")
        // With this much input piled on, we should at minimum reach the
        // 'high' bucket (>= 0.5). If this drops, a weight regressed.
        #expect(score.overallRisk >= 0.5,
                "Stacked-risk scenario should land in 'high' bucket or higher, got \(score.overallRisk)")
    }

    // MARK: - Monotonicity

    @Test("Adding a known risk factor never decreases the overall score")
    func addingRiskFactorIsMonotonic() async {
        wipeEvents()
        // Modest baseline history so we're past the empty-history guard but
        // still below saturation, leaving room for risk factors to move
        // the score upward.
        makeEvent(startDaysAgo: 10)
        makeEvent(startDaysAgo: 20)
        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let service = MigrainePredictionService.shared

        // Baseline: no weather, no health, no check-in.
        let baseline = await service.calculateRiskScore(migraines: events)

        // Same data + a 10 hPa pressure drop. Should never go below baseline.
        let withPressureDrop = await service.calculateRiskScore(
            migraines: events,
            currentWeather: makeWeather(pressureChange24h: -10)
        )

        // Same data + very poor sleep. Should never go below baseline.
        let withPoorSleep = await service.calculateRiskScore(
            migraines: events,
            healthData: HealthKitSnapshot(sleepHours: 4, hrv: nil,
                                          restingHeartRate: nil,
                                          steps: nil,
                                          daysSinceMenstruation: nil)
        )

        #expect(withPressureDrop.overallRisk >= baseline.overallRisk,
                "Adding a pressure-drop signal should never reduce risk")
        #expect(withPoorSleep.overallRisk >= baseline.overallRisk,
                "Adding a poor-sleep signal should never reduce risk")
    }

    // MARK: - Source labeling

    @Test("Below the ML minimum (20 entries) the prediction source is rule-based")
    func belowMLThresholdUsesRuleBasedSource() async {
        wipeEvents()
        for daysAgo in 1...5 { // well below the 20-entry ML minimum
            makeEvent(startDaysAgo: daysAgo)
        }
        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let score = await MigrainePredictionService.shared
            .calculateRiskScore(migraines: events)

        #expect(score.predictionSource == .ruleBased,
                "Sub-threshold runs must report rule-based source, got \(score.predictionSource)")
    }

    // MARK: - Top factors / recommendations contract

    @Test("Top factors are sorted by contribution descending and capped at 6")
    func topFactorsAreSortedAndCapped() async {
        wipeEvents()
        // Stack lots of distinct factors so we can exercise both the sort
        // and the cap. With 5+ migraines in 7 days we'll trigger:
        // recent migraine, high frequency, triptan overuse, NSAID overuse,
        // weather drop, weather code, poor sleep, low HRV, elevated RHR,
        // menstrual window, low hydration, high caffeine, low activity,
        // weekend (depending on TZ). At least 6 will be present.
        for daysAgo in 1...5 {
            makeEvent(
                startDaysAgo: daysAgo,
                triggers: [.stress, .menstrual],
                medications: [.sumatriptan, .ibuprofin, .naproxen]
            )
        }
        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let weather = makeWeather(pressureChange24h: -10, weatherCode: 95)
        let health = HealthKitSnapshot(
            sleepHours: 4, hrv: 25, restingHeartRate: 85,
            steps: 800, daysSinceMenstruation: 2
        )
        var checkIn = DailyCheckInData()
        checkIn.stressLevel = 5
        checkIn.hydrationLevel = 1
        checkIn.caffeineIntake = 6

        let score = await MigrainePredictionService.shared.calculateRiskScore(
            migraines: events,
            currentWeather: weather,
            healthData: health,
            dailyCheckIn: checkIn
        )

        #expect(score.topFactors.count <= 6,
                "topFactors should be capped at 6, got \(score.topFactors.count)")
        #expect(!score.topFactors.isEmpty,
                "Stacked-risk scenario must surface at least one factor")
        let contributions = score.topFactors.map(\.contribution)
        let sorted = contributions.sorted(by: >)
        #expect(contributions == sorted,
                "topFactors must be sorted by contribution descending: \(contributions)")
    }

    @Test("Recommendations always contain at least one entry")
    func recommendationsAreAlwaysPresent() async {
        wipeEvents()
        // Even a trivial baseline (one entry, nothing exciting) must emit
        // *some* coaching string — the UI relies on this to avoid an empty
        // list cell.
        makeEvent(startDaysAgo: 30)
        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let score = await MigrainePredictionService.shared
            .calculateRiskScore(migraines: events)

        #expect(!score.recommendations.isEmpty,
                "Rule engine must always emit at least one recommendation")
    }
}
