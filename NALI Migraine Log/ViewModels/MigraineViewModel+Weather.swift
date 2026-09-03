import CoreData
import Foundation

// MARK: - Weather Integration

extension MigraineViewModel {
    struct TimeoutError: Error {}

    /// Kicks off the weather lookup for a just-saved entry and keeps the
    /// task so `deleteMigraine`/`deleteAllData` can cancel it. The task is
    /// MainActor-isolated because `MigraineEvent` is a non-Sendable
    /// NSManagedObject owned by the main-queue `viewContext`.
    @MainActor
    func startWeatherFetch(for migraine: MigraineEvent) {
        let objectID = migraine.objectID
        weatherTasks[objectID]?.cancel()
        weatherTasks[objectID] = Task { @MainActor [weak self] in
            defer { self?.weatherTasks.removeValue(forKey: objectID) }
            guard let self else { return }
            await self.fetchWeatherData(for: migraine)
            guard !Task.isCancelled, Self.isLive(migraine) else { return }
            self.saveWeatherChanges(for: migraine)
        }
    }

    /// True while the object is still attached to a context and has not
    /// been deleted; weather results for anything else are dropped.
    static func isLive(_ migraine: MigraineEvent) -> Bool {
        !migraine.isDeleted && migraine.managedObjectContext != nil
    }

    @MainActor
    private func saveWeatherChanges(for migraine: MigraineEvent) {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
            if let id = migraine.id {
                WatchConnectivityManager.shared.recordChange(of: id)
            }
        } catch {
            viewContext.rollback()
            lastError = .saveFailed(error)
            migraineLog.error("Failed to save weather data: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetch weather data for a migraine event.
    ///
    /// `@MainActor` is required: `MigraineEvent` is a non-Sendable
    /// NSManagedObject, so reading/writing its properties must happen on the
    /// thread that owns its context (`viewContext` is main-thread). The
    /// `await` calls below suspend the MainActor cooperatively while the
    /// network request runs on its own executor — we never block main.
    @MainActor
    private func fetchWeatherData(for migraine: MigraineEvent) async {
        migraineLog.debug("🌤️ fetchWeatherData started for migraine id \(migraine.id?.uuidString ?? "nil", privacy: .public)")
        guard let startTime = migraine.startTime else {
            migraineLog.error("No start time; aborting weather fetch")
            weatherFetchStatus = .failed("No start time available")
            return
        }

        weatherFetchStatus = .fetching

        do {
            migraineLog.debug("Requesting current location")
            let location = try await LocationManager.shared.getCurrentLocation()
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude

            AppLogger.weather.debug("Fetching weather for current location (accuracy \(Int(location.horizontalAccuracy), privacy: .public) m)")

            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
            }
            guard Self.isLive(migraine) else {
                migraineLog.debug("Weather snapshot arrived for a deleted entry; discarding")
                weatherFetchStatus = .idle
                return
            }
            migraineLog.debug("Weather snapshot received; updating migraine")

            migraine.updateWeatherData(from: snapshot)
            migraine.updateWeatherLocation(latitude: latitude, longitude: longitude)
            weatherFetchStatus = .success
            AppLogger.weather.notice("Weather data added: \(snapshot.weatherCondition, privacy: .public), \(Int(snapshot.temperature), privacy: .public)°F, 24h pressure change=\(String(format: "%.2f", snapshot.pressureChange24h * 0.75006), privacy: .public) mmHg")

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle

        } catch LocationError.unauthorized {
            AppLogger.weather.notice("Location access not authorized; weather data unavailable")
            weatherFetchStatus = .locationDenied
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            weatherFetchStatus = .idle
        } catch is TimeoutError {
            AppLogger.weather.error("Weather fetch timed out — API slow or unavailable")
            weatherFetchStatus = .failed("Weather service timed out")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
        } catch {
            migraineLog.error("Weather fetch failed: \(error.localizedDescription, privacy: .public)")
            weatherFetchStatus = .failed(error.localizedDescription)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
        }
    }

    /// Races `operation` against a timer. The group always holds two child
    /// tasks, so `group.next()` yields exactly one result before the rest
    /// are cancelled; a `nil` there is impossible by construction and is
    /// treated as a timeout rather than a crash.
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    /// Retry fetching weather data for a migraine (manual retry)
    @MainActor
    func retryWeatherFetch(for migraine: MigraineEvent) async {
        guard !migraine.hasWeatherData else {
            AppLogger.weather.debug("retryWeatherFetch ignored — migraine already has weather data")
            return
        }

        AppLogger.weather.notice("Retrying weather fetch for migraine")
        await fetchWeatherData(for: migraine)
        guard Self.isLive(migraine) else { return }
        saveWeatherChanges(for: migraine)
    }

    /// Fetch weather data for a specific location (manual override)
    @MainActor
    func fetchWeatherForCustomLocation(
        for migraine: MigraineEvent,
        latitude: Double,
        longitude: Double
    ) async {
        guard let startTime = migraine.startTime else {
            AppLogger.weather.error("fetchWeatherForCustomLocation: no start time on migraine")
            weatherFetchStatus = .failed("No start time available")
            return
        }

        weatherFetchStatus = .fetching

        do {
            AppLogger.weather.debug("Fetching weather for a user-chosen location")

            let snapshot = try await withTimeout(seconds: 10) {
                try await WeatherService.shared.fetchWeatherSnapshot(
                    for: startTime,
                    latitude: latitude,
                    longitude: longitude
                )
            }

            guard Self.isLive(migraine) else {
                weatherFetchStatus = .idle
                return
            }

            migraine.updateWeatherData(from: snapshot)
            migraine.updateWeatherLocation(latitude: latitude, longitude: longitude)
            weatherFetchStatus = .success

            try viewContext.save()
            if let id = migraine.id {
                WatchConnectivityManager.shared.recordChange(of: id)
            }
            AppLogger.weather.notice("Weather data updated with custom location")

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle

        } catch {
            if viewContext.hasChanges { viewContext.rollback() }
            AppLogger.weather.error("Failed to fetch weather for custom location: \(error.localizedDescription, privacy: .public)")
            weatherFetchStatus = .failed(error.localizedDescription)

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            weatherFetchStatus = .idle
        }
    }

    /// Bulk fetch weather data for all migraines without weather data
    @MainActor
    func backfillWeatherData(progressCallback: @escaping (Int, Int) -> Void) async -> (success: Int, failed: Int) {
        let migrainesWithoutWeather = migraines.filter { !$0.hasWeatherData }
        let total = migrainesWithoutWeather.count

        guard total > 0 else {
            AppLogger.weather.debug("backfillWeatherData: nothing to do")
            return (0, 0)
        }

        AppLogger.weather.notice("Starting bulk weather fetch for \(total, privacy: .public) migraines")

        var successCount = 0
        var failedCount = 0

        for (index, migraine) in migrainesWithoutWeather.enumerated() {
            if Task.isCancelled { break }
            progressCallback(index + 1, total)

            guard Self.isLive(migraine) else {
                failedCount += 1
                continue
            }

            await fetchWeatherData(for: migraine)

            if Self.isLive(migraine), migraine.hasWeatherData {
                successCount += 1
                saveWeatherChanges(for: migraine)
            } else {
                failedCount += 1
            }

            // Small delay to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        AppLogger.weather.notice("Bulk weather fetch complete: \(successCount, privacy: .public) success, \(failedCount, privacy: .public) failed")
        return (successCount, failedCount)
    }
}
