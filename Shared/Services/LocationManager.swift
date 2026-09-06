//
//  LocationManager.swift
//  NALI Migraine Log
//
//  Manages user location for weather data
//

import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: Error?
    
    /// Kept for authorization requests and the delegate's status callbacks;
    /// fixes themselves come from `CLLocationUpdate.liveUpdates()`.
    let locationManager = CLLocationManager()

    /// A cached fix younger than this is returned without touching CoreLocation.
    private let cachedLocationMaxAge: TimeInterval = 3600
    private let locationRequestTimeout: Duration = .seconds(10)
    private var isRefreshingLocation = false
    
    /// Cross-platform check for location authorization
    /// macOS uses .authorized; iOS/watchOS use .authorizedWhenInUse
    var isLocationAuthorized: Bool {
        #if os(macOS)
        return authorizationStatus == .authorizedAlways || authorizationStatus == .authorized
        #else
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #endif
    }
    
    private nonisolated static func isStatusAuthorized(_ status: CLAuthorizationStatus) -> Bool {
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

        // The first read of `authorizationStatus` makes a synchronous XPC
        // round-trip to `locationd`. Doing that here — on the main thread, inside
        // the SwiftUI `@StateObject` init that runs during the first scene update
        // at launch — can block long enough to trip iOS's launch watchdog
        // (`0x8BADF00D`) and crash the app before it draws a frame. The probe
        // runs off the main thread; the `@Published` mutation and any CoreLocation
        // request calls happen back on the main actor (CLLocationManager wants a
        // thread with a run loop).
        Task { [weak self] in
            let probe = await Self.probeAuthorization()
            guard let self else { return }
            let currentStatus = probe.status
            self.authorizationStatus = currentStatus

            AppLogger.location.notice("LocationManager initialized; status=\(Self.statusDescription(currentStatus), privacy: .public)")

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

    /// Snapshot of the system-wide and per-app authorization state.
    private struct AuthorizationProbe: Sendable {
        let servicesEnabled: Bool
        let status: CLAuthorizationStatus
    }

    /// Reads `locationServicesEnabled()` and `authorizationStatus` off the main
    /// thread. Both block on `locationd` the first time they are called, which
    /// is why the read happens on a throwaway manager in a detached task
    /// rather than on the main-actor-owned `locationManager`.
    private nonisolated static func probeAuthorization() async -> AuthorizationProbe {
        await Task.detached(priority: .userInitiated) {
            AuthorizationProbe(
                servicesEnabled: CLLocationManager.locationServicesEnabled(),
                status: CLLocationManager().authorizationStatus
            )
        }.value
    }
    
    private nonisolated static func statusDescription(_ status: CLAuthorizationStatus) -> String {
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

        // The status/services reads run off the main thread to avoid the UI
        // unresponsiveness warning; the request itself goes back to the main actor.
        Task { [weak self] in
            let probe = await Self.probeAuthorization()
            guard let self else { return }

            AppLogger.location.debug("Services enabled=\(probe.servicesEnabled, privacy: .public); status=\(Self.statusDescription(probe.status), privacy: .public)")

            guard probe.servicesEnabled else {
                AppLogger.location.error("Location services are disabled system-wide")
                return
            }

            // Request authorization - this will show the dialog even if "When I Share" was set
            self.locationManager.requestWhenInUseAuthorization()

            // Check whether the request produced a decision
            try? await Task.sleep(for: .seconds(3))
            if self.locationManager.authorizationStatus == .notDetermined {
                AppLogger.location.notice("Status still notDetermined 3s after request; likely 'When I Share' mode")
            }
        }
    }
    
    /// Refresh authorization status (useful when returning from Settings)
    func refreshAuthorizationStatus() {
        let currentStatus = locationManager.authorizationStatus

        if currentStatus != authorizationStatus {
            AppLogger.location.notice("Status changed: \(Self.statusDescription(self.authorizationStatus), privacy: .public) → \(Self.statusDescription(currentStatus), privacy: .public)")
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

    /// One-shot location fix (waits up to 10 s) from the first usable
    /// `CLLocationUpdate.liveUpdates()` element. Each caller consumes its
    /// own short-lived stream, so cancelling the calling task tears down
    /// only that stream and never affects other callers.
    func getCurrentLocation() async throws -> CLLocation {
        let status = locationManager.authorizationStatus
        AppLogger.location.debug("getCurrentLocation called; status=\(Self.statusDescription(status), privacy: .public)")

        // `.notDetermined` can also mean the iOS 18 "Ask Next Time / When I
        // Share" mode; `liveUpdates()` then surfaces the system prompt.
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

        do {
            let fix = try await Self.firstFix(timeout: locationRequestTimeout)
            self.location = fix
            lastError = nil
            return fix
        } catch {
            if !(error is CancellationError) {
                lastError = error
            }
            throw error
        }
    }

    /// Races the first usable live update against the request timeout.
    private nonisolated static func firstFix(timeout: Duration) async throws -> CLLocation {
        try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { try await firstLiveUpdate() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationError.timeout
            }
            defer { group.cancelAll() }
            guard let fix = try await group.next() else { throw LocationError.unavailable }
            return fix
        }
    }

    /// Consumes `liveUpdates()` until a location or a terminal condition
    /// (denied, restricted, unavailable) arrives. Reduced-accuracy fixes
    /// are accepted as-is; weather lookups only need a coarse position.
    private nonisolated static func firstLiveUpdate() async throws -> CLLocation {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let fix = update.location {
                AppLogger.location.debug("Location updated (accuracy \(Int(fix.horizontalAccuracy), privacy: .public) m)")
                return fix
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                AppLogger.location.error("Live updates reported denied/restricted authorization")
                throw LocationError.unauthorized
            }
            if update.locationUnavailable {
                AppLogger.location.error("Live updates reported location unavailable")
                throw LocationError.unavailable
            }
            // Remaining diagnostic states (authorization prompt in progress,
            // insufficiently in use, stationary) resolve on a later element.
        }
        throw CancellationError()
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
        guard isLocationAuthorized, !hasFreshLocation, !isRefreshingLocation else { return }
        isRefreshingLocation = true
        Task { @MainActor [weak self] in
            defer { self?.isRefreshingLocation = false }
            _ = try? await self?.getCurrentLocation()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        AppLogger.location.notice("Authorization changed to: \(Self.statusDescription(status), privacy: .public)")

        Task { @MainActor in
            self.authorizationStatus = status

            if Self.isStatusAuthorized(status) {
                self.lastError = nil
                self.refreshLocationIfStale()
            } else if status == .denied || status == .restricted {
                AppLogger.location.error("Location denied or restricted")
                self.lastError = LocationError.unauthorized
            }
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

