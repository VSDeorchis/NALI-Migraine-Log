//
//  FeatureExtractorTests.swift
//  NALI Migraine LogTests
//
//  Pure-function tests for `FeatureExtractor`. Uses an in-memory Core Data
//  context and a fixed `referenceDate` so every assertion is deterministic
//  regardless of clock or wall-time drift.
//
//  Coverage focuses on the *math*: frequency / recency windows, trigger and
//  medication-rebound counts, weather pass-through, and the hourly /
//  day-of-week histograms used by `MigrainePredictionService`. Calendar-
//  derived temporal features (`dayOfWeek`, `isWeekend`, ...) are intentionally
//  *not* asserted on directly because they depend on the host timezone — those
//  paths are exercised indirectly via the histogram tests, which are
//  timezone-stable when the same calendar interprets both the input date and
//  the bucket lookup.
//

import Testing
import CoreData
import Foundation
@testable import NALI_Migraine_Log

@Suite("FeatureExtractor", .serialized)
@MainActor
struct FeatureExtractorTests {

    // MARK: - Shared fixtures

    private var context: NSManagedObjectContext {
        PersistenceController.preview.container.viewContext
    }

    /// Fixed point-in-time used as `referenceDate` for every test in this
    /// suite — the FeatureExtractor's frequency/recency math is anchored to
    /// this value, so changing it requires updating the date arithmetic in
    /// each test below.
    private var referenceDate: Date {
        // 2026-04-25 17:00:00 UTC — chosen because it's a Saturday in every
        // realistic test-runner timezone, which makes the Calendar-derived
        // bookkeeping behave the same on dev machines and in CI.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 25
        components.hour = 17
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func date(daysAgo days: Int, from reference: Date? = nil) -> Date {
        // Use absolute seconds so the offset doesn't depend on the host
        // timezone or DST transitions — only the *calendar bucket* of the
        // resulting date can shift, which the few tests that care
        // already account for.
        let anchor = reference ?? referenceDate
        return anchor.addingTimeInterval(TimeInterval(-days) * 86_400)
    }

    /// Inserts a `MigraineEvent` with the given attributes into the in-memory
    /// context. Returns the event so callers can tweak additional attributes
    /// inline.
    @discardableResult
    private func makeEvent(
        startDaysAgo: Int,
        painLevel: Int = 5,
        triggers: Set<MigraineTrigger> = [],
        medications: Set<MigraineMedication> = [],
        weather: WeatherSnapshot? = nil
    ) -> MigraineEvent {
        let event = MigraineEvent(context: context)
        event.id = UUID()
        event.startTime = date(daysAgo: startDaysAgo)
        event.painLevel = Int16(painLevel)
        event.triggers = triggers
        event.medications = medications
        if let weather {
            event.updateWeatherData(from: weather)
        }
        return event
    }

    /// Removes every `MigraineEvent` we inserted so that subsequent tests
    /// in this serialized suite see a clean slate. Required because every
    /// test reuses `PersistenceController.preview`.
    private func wipeEvents() {
        let request: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        if let events = try? context.fetch(request) {
            for event in events { context.delete(event) }
        }
    }

    private func makeWeather(
        pressure: Double = 1013,
        pressureChange24h: Double = 0,
        temperature: Double = 70,
        precipitation: Double = 0,
        cloudCover: Int = 0,
        weatherCode: Int = 0
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            timestamp: referenceDate,
            temperature: temperature,
            pressure: pressure,
            pressureChange24h: pressureChange24h,
            precipitation: precipitation,
            cloudCover: cloudCover,
            weatherCode: weatherCode,
            weatherCondition: "Test",
            weatherIcon: "cloud"
        )
    }

    // MARK: - Empty input baseline

    @Test("Empty migraine list yields default-valued frequency features and no weather")
    func emptyInputProducesDefaults() {
        wipeEvents()
        let extractor = FeatureExtractor()

        let features = extractor.extractFeatures(
            migraines: [],
            currentWeather: nil,
            referenceDate: referenceDate
        )

        // Default values come from MigraineFeatureVector — keep these
        // assertions tight so accidentally widening a default surfaces here.
        #expect(features.daysSinceLastMigraine == 30.0)
        #expect(features.migrainesInLast7Days == 0)
        #expect(features.migrainesInLast30Days == 0)
        #expect(features.avgPainLevelLast5 == 0.0)
        #expect(features.triptanUsesLast7Days == 0)
        #expect(features.nsaidUsesLast7Days == 0)
        #expect(features.triggerStressFreq == 0.0)

        // Weather defaults
        #expect(features.pressureCurrent == 1013.0)
        #expect(features.pressureChange24h == 0.0)
        #expect(features.temperature == 70.0)
    }

    // MARK: - Frequency / recency windows

    @Test("daysSinceLastMigraine reflects the most recent startTime")
    func daysSinceLastMigraineIsCorrect() {
        wipeEvents()
        // Three events at 2, 10, 25 days ago. Most recent = 2 days.
        makeEvent(startDaysAgo: 2)
        makeEvent(startDaysAgo: 10)
        makeEvent(startDaysAgo: 25)

        let request: NSFetchRequest<MigraineEvent> = MigraineEvent.fetchRequest()
        let events = (try? context.fetch(request)) ?? []

        let features = FeatureExtractor().extractFeatures(
            migraines: events,
            currentWeather: nil,
            referenceDate: referenceDate
        )

        // Allow a small floating-point tolerance — the math is `interval / 86_400`.
        #expect(abs(features.daysSinceLastMigraine - 2.0) < 0.0001)
    }

    @Test("migrainesInLast7Days / Last30Days respect the rolling windows")
    func migraineWindowCounts() {
        wipeEvents()
        // Inside 7-day window: 2, 5 days ago.
        // Inside 30-day window but outside 7-day: 10, 25 days ago.
        // Outside 30-day window: 40 days ago.
        makeEvent(startDaysAgo: 2)
        makeEvent(startDaysAgo: 5)
        makeEvent(startDaysAgo: 10)
        makeEvent(startDaysAgo: 25)
        makeEvent(startDaysAgo: 40)

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let features = FeatureExtractor().extractFeatures(
            migraines: events,
            currentWeather: nil,
            referenceDate: referenceDate
        )

        #expect(features.migrainesInLast7Days == 2,
                "Expected 2 migraines within 7 days, got \(features.migrainesInLast7Days)")
        #expect(features.migrainesInLast30Days == 4,
                "Expected 4 migraines within 30 days, got \(features.migrainesInLast30Days)")
    }

    @Test("avgPainLevelLast5 averages pain across the five most recent entries")
    func avgPainLastFive() {
        wipeEvents()
        // 6 events; oldest should be excluded from the average. Pain values
        // chosen so the expected average is an integer.
        // Recent five (most-recent-first by date): 2d=8, 5d=4, 10d=6, 25d=2, 40d=10
        // Average = (8+4+6+2+10)/5 = 6.0
        // Sixth (50 days ago, pain 1) should be excluded.
        makeEvent(startDaysAgo: 2,  painLevel: 8)
        makeEvent(startDaysAgo: 5,  painLevel: 4)
        makeEvent(startDaysAgo: 10, painLevel: 6)
        makeEvent(startDaysAgo: 25, painLevel: 2)
        makeEvent(startDaysAgo: 40, painLevel: 10)
        makeEvent(startDaysAgo: 50, painLevel: 1)   // must NOT contribute

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []

        let features = FeatureExtractor().extractFeatures(
            migraines: events,
            currentWeather: nil,
            referenceDate: referenceDate
        )

        #expect(abs(features.avgPainLevelLast5 - 6.0) < 0.0001,
                "avgPainLevelLast5 should be 6.0, got \(features.avgPainLevelLast5)")
    }

    // MARK: - Trigger frequencies

    @Test("Trigger frequencies are counted across all entries, including outside windows")
    func triggerFrequencies() {
        wipeEvents()
        // 4 events. Stress on 3 of them = 0.75. Lack of sleep on 1 = 0.25.
        // Menstrual on 2 = 0.5.
        makeEvent(startDaysAgo: 1,  triggers: [.stress, .menstrual])
        makeEvent(startDaysAgo: 5,  triggers: [.stress, .lackOfSleep])
        makeEvent(startDaysAgo: 14, triggers: [.stress, .menstrual])
        makeEvent(startDaysAgo: 60, triggers: [])

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []
        let features = FeatureExtractor().extractFeatures(
            migraines: events,
            currentWeather: nil,
            referenceDate: referenceDate
        )

        #expect(abs(features.triggerStressFreq - 0.75) < 0.0001)
        #expect(abs(features.triggerSleepFreq  - 0.25) < 0.0001)
        // The menstrual case routes through the legacy `isTriggerHormones`
        // attribute on disk, but the feature column is still `Hormones` —
        // verify the feature name didn't drift away from the storage column.
        #expect(abs(features.triggerHormonesFreq - 0.5)  < 0.0001)
        #expect(features.triggerCaffeineFreq == 0.0)
    }

    // MARK: - Medication rebound counts

    @Test("Triptan and NSAID rebound counts only consider entries inside the 7-day window")
    func medicationReboundCounts() {
        wipeEvents()
        // Inside 7d: 1 triptan, 1 NSAID, 1 with both, 1 with neither.
        // Outside 7d: 1 triptan, 1 NSAID — must be excluded.
        makeEvent(startDaysAgo: 1, medications: [.sumatriptan])           // triptan
        makeEvent(startDaysAgo: 2, medications: [.ibuprofin])             // nsaid
        makeEvent(startDaysAgo: 3, medications: [.naproxen, .rizatriptan]) // both
        makeEvent(startDaysAgo: 4, medications: [.tylenol])               // neither
        makeEvent(startDaysAgo: 9, medications: [.eletriptan])            // outside window
        makeEvent(startDaysAgo: 10, medications: [.excedrin])             // outside window

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []
        let features = FeatureExtractor().extractFeatures(
            migraines: events,
            currentWeather: nil,
            referenceDate: referenceDate
        )

        // Two entries inside 7d touch a triptan (sumatriptan + the 'both' row).
        #expect(features.triptanUsesLast7Days == 2,
                "Expected 2 triptan uses, got \(features.triptanUsesLast7Days)")
        // Two entries inside 7d touch an NSAID (ibuprofin + the 'both' row).
        #expect(features.nsaidUsesLast7Days == 2,
                "Expected 2 NSAID uses, got \(features.nsaidUsesLast7Days)")
    }

    // MARK: - Weather pass-through

    @Test("Weather snapshot fields are passed through verbatim into features")
    func weatherSnapshotPassThrough() {
        wipeEvents()
        let snapshot = makeWeather(
            pressure: 1005.5,
            pressureChange24h: -8.0,
            temperature: 65,
            precipitation: 1.2,
            cloudCover: 90,
            weatherCode: 95
        )

        let features = FeatureExtractor().extractFeatures(
            migraines: [],
            currentWeather: snapshot,
            referenceDate: referenceDate
        )

        #expect(features.pressureCurrent == 1005.5)
        #expect(features.pressureChange24h == -8.0)
        // Hourly rate is the 24h change divided by 24.
        #expect(abs(features.pressureChangeRate - (-8.0 / 24.0)) < 0.0001)
        #expect(features.temperature == 65)
        #expect(features.precipitation == 1.2)
        #expect(features.cloudCover == 90)
        #expect(features.weatherCode == 95)
    }

    // MARK: - HealthKit / check-in pass-through

    @Test("HealthKit and daily check-in values flow into the feature vector")
    func healthAndCheckInPassThrough() {
        wipeEvents()
        let health = HealthKitSnapshot(
            sleepHours: 4.5,
            hrv: 28,
            restingHeartRate: 82,
            steps: 1500,
            daysSinceMenstruation: 2
        )
        var checkIn = DailyCheckInData()
        checkIn.stressLevel = 5
        checkIn.hydrationLevel = 1
        checkIn.caffeineIntake = 6

        let features = FeatureExtractor().extractFeatures(
            migraines: [],
            currentWeather: nil,
            healthData: health,
            dailyCheckIn: checkIn,
            referenceDate: referenceDate
        )

        #expect(features.sleepHoursLastNight == 4.5)
        #expect(features.hrvLastNight == 28)
        #expect(features.restingHeartRate == 82)
        #expect(features.stepsYesterday == 1500)
        #expect(features.daysSinceMenstruation == 2)
        #expect(features.selfReportedStress == 5)
        #expect(features.selfReportedHydration == 1)
        #expect(features.selfReportedCaffeine == 6)
    }

    // MARK: - Histograms

    @Test("hourlyDistribution sums to 1.0 across the 24 buckets when input is non-empty")
    func hourlyDistributionSumsToOne() {
        wipeEvents()
        // 4 events with arbitrary times; what matters is that the sum of the
        // distribution equals 1.0 (within fp tolerance).
        makeEvent(startDaysAgo: 1)
        makeEvent(startDaysAgo: 2)
        makeEvent(startDaysAgo: 3)
        makeEvent(startDaysAgo: 4)

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []
        let dist = FeatureExtractor().hourlyDistribution(from: events)

        let total = (0..<24).map { dist[$0] ?? 0 }.reduce(0, +)
        #expect(abs(total - 1.0) < 0.0001,
                "Hourly distribution should sum to 1.0, got \(total)")
        #expect(dist.count == 24, "Distribution must have one bucket per hour")
    }

    @Test("dayOfWeekDistribution sums to 1.0 across 7 buckets when input is non-empty")
    func dayOfWeekDistributionSumsToOne() {
        wipeEvents()
        makeEvent(startDaysAgo: 1)
        makeEvent(startDaysAgo: 8)
        makeEvent(startDaysAgo: 15)

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []
        let dist = FeatureExtractor().dayOfWeekDistribution(from: events)

        let total = (0..<7).map { dist[$0] ?? 0 }.reduce(0, +)
        #expect(abs(total - 1.0) < 0.0001,
                "Day-of-week distribution should sum to 1.0, got \(total)")
        #expect(dist.count == 7, "Distribution must have one bucket per weekday")
    }

    @Test("Empty histograms return empty dictionaries (not all-zero buckets)")
    func emptyHistogramsAreEmpty() {
        wipeEvents()
        let extractor = FeatureExtractor()
        #expect(extractor.hourlyDistribution(from: []).isEmpty)
        #expect(extractor.dayOfWeekDistribution(from: []).isEmpty)
    }

    // MARK: - Average weather during migraines

    @Test("averageWeatherDuringMigraines averages only events with hasWeatherData")
    func averageWeatherIgnoresMissingWeather() {
        wipeEvents()
        // 2 events with weather, 1 without — the no-weather event must be
        // excluded from the average so a missing snapshot doesn't drag
        // averages toward zero.
        makeEvent(startDaysAgo: 1, weather: makeWeather(pressureChange24h: -10, temperature: 60, precipitation: 2))
        makeEvent(startDaysAgo: 2, weather: makeWeather(pressureChange24h: -2,  temperature: 80, precipitation: 0))
        makeEvent(startDaysAgo: 3, weather: nil)

        let events = (try? context.fetch(MigraineEvent.fetchRequest())) ?? []
        let result = FeatureExtractor().averageWeatherDuringMigraines(events)

        #expect(abs(result.avgPressureChange - (-6.0)) < 0.0001,
                "Expected avg pressureChange = -6.0, got \(result.avgPressureChange)")
        #expect(abs(result.avgTemp - 70.0) < 0.0001,
                "Expected avg temp = 70.0, got \(result.avgTemp)")
        #expect(abs(result.avgPrecip - 1.0) < 0.0001,
                "Expected avg precip = 1.0, got \(result.avgPrecip)")
    }

    @Test("averageWeatherDuringMigraines returns neutral defaults for empty input")
    func averageWeatherDefaultsForEmptyInput() {
        wipeEvents()
        let result = FeatureExtractor().averageWeatherDuringMigraines([])
        // Neutral values used so the rule-engine doesn't false-positive
        // on missing data — keep these in lockstep with FeatureExtractor.
        #expect(result.avgPressureChange == 0)
        #expect(result.avgTemp == 70)
        #expect(result.avgPrecip == 0)
    }
}
