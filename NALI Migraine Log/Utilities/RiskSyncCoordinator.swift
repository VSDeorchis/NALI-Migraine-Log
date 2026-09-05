//
//  RiskSyncCoordinator.swift
//  NALI Migraine Log
//
//  Single iPhone-side pipeline that computes the current migraine risk
//  (weather forecast → Health snapshot → prediction) and publishes it to
//  the Watch. The Predict tab, the scene-active hook, the background
//  refresh task and inbound Watch sync requests all funnel through here,
//  so the Watch shows the same number the phone would — even when the
//  user never opens the Predict tab.
//

#if os(iOS)

import Foundation
import CoreData

@MainActor
enum RiskSyncCoordinator {

    struct Outcome {
        let riskScore: MigraineRiskScore
        let forecastHours: [ForecastHour]
    }

    /// Time of the last successful publish, used to throttle opportunistic
    /// refreshes (sync requests, foregrounding). Explicit user refreshes
    /// bypass it via `force: true`.
    private(set) static var lastPublished: Date?

    /// Opportunistic callers skip the pipeline if a publish this recent exists.
    static let staleAfter: TimeInterval = 300

    private static var inFlight: Task<Outcome?, Never>?

    static var isStale: Bool {
        guard let lastPublished else { return true }
        return Date().timeIntervalSince(lastPublished) > staleAfter
    }

    /// Computes the risk for `migraines` and pushes it to the Watch.
    /// Concurrent callers share one in-flight run. Returns `nil` only when
    /// throttled (`force == false` and a fresh publish exists).
    @discardableResult
    static func refresh(migraines: [MigraineEvent], force: Bool = false) async -> Outcome? {
        if let inFlight {
            return await inFlight.value
        }
        guard force || isStale else { return nil }

        let task = Task<Outcome?, Never> { @MainActor in
            await run(migraines: migraines)
        }
        inFlight = task
        defer { inFlight = nil }
        return await task.value
    }

    /// Convenience for callers without a view model (WatchConnectivity,
    /// background refresh): reads the entries from the shared view context.
    @discardableResult
    static func refreshFromStore(force: Bool = false) async -> Outcome? {
        guard force || isStale else { return nil }
        let context = PersistenceController.shared.container.viewContext
        let migraines: [MigraineEvent]
        do {
            migraines = try context.fetch(MigraineEvent.fetchRequest())
        } catch {
            AppLogger.prediction.error("Risk sync migraine fetch failed: \(error.localizedDescription, privacy: .private)")
            migraines = []
        }
        return await refresh(migraines: migraines, force: force)
    }

    private static func run(migraines: [MigraineEvent]) async -> Outcome {
        let predictionService = MigrainePredictionService.shared
        let forecastService = WeatherForecastService.shared
        let healthKit = HealthKitManager.shared

        var forecastHours: [ForecastHour] = []
        var weatherSnapshot: WeatherSnapshot?
        if let coords = await resolveCoordinates() {
            do {
                forecastHours = try await forecastService.fetchForecast(
                    latitude: coords.latitude,
                    longitude: coords.longitude
                )
                weatherSnapshot = forecastService.currentWeatherSnapshot()
            } catch {
                AppLogger.prediction.error("Forecast fetch failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        // `isAuthorized` is in-memory only and resets on cold launch, so for
        // users who previously granted we rehydrate first (no UI; Apple
        // no-ops the call once the user has decided).
        var healthData: HealthKitSnapshot?
        if !healthKit.isAuthorized && healthKit.hasRequestedAuthorization {
            await healthKit.rehydrateAuthorizationStatus()
        }
        if healthKit.isAuthorized {
            healthData = await healthKit.fetchSnapshot()
        }

        let checkIn = DailyCheckInData.loadToday()

        if !forecastHours.isEmpty {
            _ = predictionService.generate24HourForecast(
                migraines: migraines,
                forecastHours: forecastHours,
                healthData: healthData,
                dailyCheckIn: checkIn
            )
        }

        let riskScore = await predictionService.calculateRiskScore(
            migraines: migraines,
            currentWeather: weatherSnapshot,
            healthData: healthData,
            dailyCheckIn: checkIn
        )

        WatchConnectivityManager.shared.sendRiskScore(riskScore)
        lastPublished = Date()
        AppLogger.prediction.info("Risk published to Watch: \(riskScore.riskPercentage, privacy: .public)%")

        return Outcome(riskScore: riskScore, forecastHours: forecastHours)
    }

    /// Cached fix when fresh, otherwise a one-shot fix for already-authorized
    /// users; never triggers the system permission prompt. Falls back to any
    /// stale cached fix when no new one arrives.
    private static func resolveCoordinates() async -> (latitude: Double, longitude: Double)? {
        let locationManager = LocationManager.shared
        if locationManager.isLocationAuthorized {
            if let location = try? await locationManager.getCurrentLocation() {
                return (location.coordinate.latitude, location.coordinate.longitude)
            }
        }
        return locationManager.currentCoordinates
    }
}

#endif
