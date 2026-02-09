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
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    
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
        
        // Set delegate first
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 1000 // Update only if moved 1km
        
        // Check authorization status using the class method (more reliable)
        let currentStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            currentStatus = locationManager.authorizationStatus
        } else {
            currentStatus = CLLocationManager.authorizationStatus()
        }
        
        authorizationStatus = currentStatus
        
        print("📍 LocationManager initialized")
        print("📍 Current authorization status: \(currentStatus.rawValue)")
        print("📍 Status description: \(statusDescription(currentStatus))")
        
        // If already authorized, start monitoring
        if Self.isStatusAuthorized(currentStatus) {
            print("📍 Already authorized, starting monitoring")
            locationManager.startUpdatingLocation()
        }
        
        // IMPORTANT: Request authorization early so iOS recognizes this app uses location
        // This makes "While Using the App" appear in Settings
        // If user already responded, this does nothing (won't show dialog again)
        if currentStatus == .notDetermined {
            print("📍 Proactively requesting authorization so iOS shows full permission options")
            // Delay slightly to ensure app is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("📍 Calling requestWhenInUseAuthorization() to register location usage")
                self.locationManager.requestWhenInUseAuthorization()
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
        print("📍 Requesting location permission...")
        
        // Request on a background thread to avoid UI unresponsiveness warning
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check if location services are enabled system-wide
            let servicesEnabled = CLLocationManager.locationServicesEnabled()
            let currentStatus = self.locationManager.authorizationStatus
            
            print("📍 Location services enabled: \(servicesEnabled)")
            print("📍 Current status before request: \(currentStatus.rawValue)")
            
            guard servicesEnabled else {
                print("⚠️ Location services are disabled system-wide")
                return
            }
            
            // Request authorization - this will show the dialog even if "When I Share" was set
            print("📍 Calling requestWhenInUseAuthorization()...")
            self.locationManager.requestWhenInUseAuthorization()
            print("📍 Permission request dispatched - iOS dialog should appear...")
            
            // Set a timer to check if authorization changed
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let newStatus = self.locationManager.authorizationStatus
                print("📍 Status after 3 seconds: \(newStatus.rawValue)")
                if newStatus == .notDetermined {
                    print("⚠️ WARNING: Status still notDetermined after 3 seconds")
                    print("⚠️ This may indicate 'When I Share' is set")
                    print("⚠️ The permission dialog should have appeared - please select 'While Using the App'")
                }
            }
        }
    }
    
    /// Refresh authorization status (useful when returning from Settings)
    func refreshAuthorizationStatus() {
        // Use class method for more reliable status check
        let currentStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            currentStatus = locationManager.authorizationStatus
        } else {
            currentStatus = CLLocationManager.authorizationStatus()
        }
        
        print("📍 Refreshing authorization status: \(statusDescription(currentStatus))")
        print("📍 Previous status was: \(statusDescription(authorizationStatus))")
        
        // Only update if changed
        if currentStatus != authorizationStatus {
            print("📍 Status changed! Updating from \(authorizationStatus.rawValue) to \(currentStatus.rawValue)")
            authorizationStatus = currentStatus
        } else {
            print("📍 Status unchanged at \(currentStatus.rawValue)")
        }
        
        // Start monitoring if authorized
        if Self.isStatusAuthorized(currentStatus) {
            print("📍 Starting location monitoring")
            startMonitoring()
        }
    }
    
    /// Get current location (one-time)
    func getCurrentLocation() async throws -> CLLocation {
        // Check authorization status from the actual manager
        let status = locationManager.authorizationStatus
        
        print("📍 getCurrentLocation called, current status: \(status.rawValue) (\(statusDescription(status)))")
        
        // In iOS 25+, "When I Share" shows as .notDetermined but we can still request location
        // If status is .notDetermined, try requesting location anyway (iOS will show permission dialog)
        if status == .notDetermined {
            print("📍 Status is .notDetermined, will request location (iOS 25+ 'When I Share' mode)")
            print("📍 iOS should show permission dialog when requestLocation() is called")
            // Fall through to request location - iOS will handle the permission
        } else if !Self.isStatusAuthorized(status) {
            print("⚠️ Location not authorized (status: \(status.rawValue))")
            throw LocationError.unauthorized
        } else {
            print("✅ Location is authorized (status: \(status.rawValue))")
        }
        
        // If we have a recent location (within 1 hour), use it
        if let location = location,
           abs(location.timestamp.timeIntervalSinceNow) < 3600 {
            print("📍 Using cached location")
            return location
        }
        
        // Request new location with timeout
        print("📍 Requesting fresh location...")
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            // Add location request task
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task { @MainActor in
                        self.locationContinuation = continuation
                    }
                    self.locationManager.requestLocation()
                }
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw LocationError.timeout
            }
            
            // Return first result (either location or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Get stored location or default
    var currentCoordinates: (latitude: Double, longitude: Double)? {
        guard let location = location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
    
    /// Start monitoring location changes
    func startMonitoring() {
        guard isLocationAuthorized else {
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    /// Stop monitoring location changes
    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("📍 Authorization changed to: \(status.rawValue) (\(self.statusDescription(status)))")
        
        Task { @MainActor in
            self.authorizationStatus = status
            
            if Self.isStatusAuthorized(status) {
                print("✅ Location authorized - starting monitoring")
                self.startMonitoring()
            } else if status == .denied || status == .restricted {
                print("❌ Location denied or restricted")
                self.lastError = LocationError.unauthorized
            } else if status == .notDetermined {
                print("⚠️ Location not determined")
            } else {
                print("⚠️ Unknown authorization status")
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        print("📍 Location updated: \(newLocation.coordinate.latitude), \(newLocation.coordinate.longitude)")
        
        Task { @MainActor in
            // Update stored location
            self.location = newLocation
            
            // Resolve any pending continuation
            if let continuation = self.locationContinuation {
                continuation.resume(returning: newLocation)
                self.locationContinuation = nil
                print("📍 Location continuation resolved")
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        let errorCode = clError?.code.rawValue ?? -1
        
        print("❌ Location error: \(error.localizedDescription)")
        print("❌ Error code: \(errorCode)")
        
        if errorCode == 1 {
            print("❌ CLError.denied (1) - User denied location permission or dialog didn't appear")
            print("❌ This typically means:")
            print("   1. User tapped 'Don't Allow' on the permission dialog")
            print("   2. Permission dialog didn't show (iOS bug)")
            print("   3. Location services disabled system-wide")
        }
        
        Task { @MainActor in
            self.lastError = error
            
            // Resolve any pending continuation with error
            if let continuation = self.locationContinuation {
                continuation.resume(throwing: error)
                self.locationContinuation = nil
                print("📍 Location continuation resolved with error")
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

