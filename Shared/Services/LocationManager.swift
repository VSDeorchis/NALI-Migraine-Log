//
//  LocationManager.swift
//  NALI Migraine Log
//
//  Manages user location for weather data
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: Error?
    
    let locationManager = CLLocationManager()
    /// Callers currently awaiting `getCurrentLocation()`, keyed so that
    /// overlapping requests, timeouts and cancellation each resolve only
    /// their own continuation. Main-actor confined.
    @MainActor private var locationWaiters: [UUID: CheckedContinuation<CLLocation, Error>] = [:]

    /// A cached fix younger than this is returned without touching CoreLocation.
    private let cachedLocationMaxAge: TimeInterval = 3600
    private let locationRequestTimeout: UInt64 = 10_000_000_000
    
    /// Cross-platform check for location authorization
    /// macOS uses .authorized; iOS/watchOS use .authorizedWhenInUse
    var isLocationAuthorized: Bool {
        #if os(macOS)
        return authorizationStatus == .authorizedAlways || authorizationStatus == .authorized
        #else
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #endif
    }
    
    private static func isStatusAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        return status == .authorizedAlways || status == .authorized
        #else
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }
    
    override private init() {
        super.init()
        
        // Set delegate + configuration. These are cheap, local operations that
        // are safe to run synchronously on the main thread.
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 1000 // Update only if moved 1km

        // The first read of `authorizationStatus` (and `startUpdatingLocation()`)
        // makes a synchronous XPC round-trip to `locationd`. Doing that here — on
        // the main thread, inside the SwiftUI `@StateObject` init that runs during
        // the first scene update at launch — can block long enough to trip iOS's
        // launch watchdog (`0x8BADF00D`) and crash the app before it draws a frame.
        // Hop off the main thread for the status read; the `@Published` mutation
        // and any CoreLocation start/request calls are bounced back to the main
        // actor (CLLocationManager wants a thread with a run loop).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let currentStatus = self.locationManager.authorizationStatus

            Task { @MainActor in
                self.authorizationStatus = currentStatus

                AppLogger.location.notice("LocationManager initialized; status=\(self.statusDescription(currentStatus), privacy: .public)")

                if Self.isStatusAuthorized(currentStatus) {
                    self.refreshLocationIfStale()
                }

                // IMPORTANT: Request authorization early so iOS recognizes this app
                // uses location (makes "While Using the App" appear in Settings).
                // If the user already responded, this is a no-op (no dialog).
                if currentStatus == .notDetermined {
                    AppLogger.location.debug("Proactively requesting authorization so iOS shows full permission options")
                    self.locationManager.requestWhenInUseAuthorization()
                }
            }
        }
    }
    
    private func statusDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Authorized Always"
        #if !os(macOS)
        case .authorizedWhenInUse: return "Authorized When In Use"
        #endif
        @unknown default: return "Unknown (\(status.rawValue))"
        }
    }
    
    // MARK: - Public Methods
    
    /// Request location permission (works even if "When I Share" was previously set)
    func requestPermission() {
        AppLogger.location.notice("Requesting location permission")

        // Request on a background thread to avoid UI unresponsiveness warning
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Check if location services are enabled system-wide
            let servicesEnabled = CLLocationManager.locationServicesEnabled()
            let currentStatus = self.locationManager.authorizationStatus

            AppLogger.location.debug("Services enabled=\(servicesEnabled, privacy: .public); status=\(self.statusDescription(currentStatus), privacy: .public)")

            guard servicesEnabled else {
                AppLogger.location.error("Location services are disabled system-wide")
                return
            }

            // Request authorization - this will show the dialog even if "When I Share" was set
            self.locationManager.requestWhenInUseAuthorization()

            // Set a timer to check if authorization changed
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let newStatus = self.locationManager.authorizationStatus
                if newStatus == .notDetermined {
                    AppLogger.location.notice("Status still notDetermined 3s after request; likely 'When I Share' mode")
                }
            }
        }
    }
    
    /// Refresh authorization status (useful when returning from Settings)
    func refreshAuthorizationStatus() {
        let currentStatus = locationManager.authorizationStatus

        if currentStatus != authorizationStatus {
            AppLogger.location.notice("Status changed: \(self.statusDescription(self.authorizationStatus), privacy: .public) → \(self.statusDescription(currentStatus), privacy: .public)")
            authorizationStatus = currentStatus
        }

        if Self.isStatusAuthorized(currentStatus) {
            refreshLocationIfStale()
        }
    }

    private var hasFreshLocation: Bool {
        guard let location else { return false }
        return abs(location.timestamp.timeIntervalSinceNow) < cachedLocationMaxAge
    }

    /// One-shot location fix (waits up to 10 s). Multiple concurrent callers
    /// each get their own result; cancelling the calling task releases only
    /// that caller.
    @MainActor
    func getCurrentLocation() async throws -> CLLocation {
        let status = locationManager.authorizationStatus
        AppLogger.location.debug("getCurrentLocation called; status=\(self.statusDescription(status), privacy: .public)")

        // `.notDetermined` can also mean the iOS 18 "Ask Next Time / When I
        // Share" mode; `requestLocation()` then surfaces the system prompt.
        if status != .notDetermined, !Self.isStatusAuthorized(status) {
            AppLogger.location.error("Location not authorized; throwing LocationError.unauthorized")
            throw LocationError.unauthorized
        }

        if hasFreshLocation, let location {
            AppLogger.location.debug("Using cached location")
            return location
        }

        try Task.checkCancellation()
        AppLogger.location.debug("Requesting fresh location")

        let waiterID = UUID()
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.locationRequestTimeout ?? 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.resolveWaiter(waiterID, with: .failure(LocationError.timeout))
        }
        defer { timeout.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locationWaiters[waiterID] = continuation
                locationManager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolveWaiter(waiterID, with: .failure(CancellationError()))
            }
        }
    }

    @MainActor
    private func resolveWaiter(_ id: UUID, with result: Result<CLLocation, Error>) {
        guard let continuation = locationWaiters.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    @MainActor
    private func resolveAllWaiters(with result: Result<CLLocation, Error>) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        for continuation in waiters.values {
            continuation.resume(with: result)
        }
    }
    
    /// Get stored location or default
    var currentCoordinates: (latitude: Double, longitude: Double)? {
        guard let location = location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    
    /// Requests a single fix when the cached one is missing or older than an
    /// hour. Weather lookups only need a coarse, occasional position, so the
    /// app never runs continuous location updates.
    func refreshLocationIfStale() {
        guard isLocationAuthorized, !hasFreshLocation else { return }
        locationManager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        AppLogger.location.notice("Authorization changed to: \(self.statusDescription(status), privacy: .public)")

        Task { @MainActor in
            self.authorizationStatus = status

            if Self.isStatusAuthorized(status) {
                self.refreshLocationIfStale()
            } else if status == .denied || status == .restricted {
                AppLogger.location.error("Location denied or restricted")
                self.lastError = LocationError.unauthorized
                self.resolveAllWaiters(with: .failure(LocationError.unauthorized))
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        AppLogger.location.debug("Location updated (accuracy \(Int(newLocation.horizontalAccuracy), privacy: .public) m)")

        Task { @MainActor in
            self.location = newLocation
            self.resolveAllWaiters(with: .success(newLocation))
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        let errorCode = clError?.code.rawValue ?? -1

        AppLogger.location.error("Location error code=\(errorCode, privacy: .public): \(error.localizedDescription, privacy: .private)")
        if errorCode == 1 {
            AppLogger.location.notice("CLError.denied — user denied permission, dialog didn't appear, or services disabled system-wide")
        }

        Task { @MainActor in
            self.lastError = error
            self.resolveAllWaiters(with: .failure(error))
        }
    }
}

// MARK: - Location Errors

enum LocationError: LocalizedError {
    case unauthorized
    case unavailable
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Location access not authorized. Please enable location services in Settings."
        case .unavailable:
            return "Location services unavailable"
        case .timeout:
            return "Location request timed out"
        }
    }
}

