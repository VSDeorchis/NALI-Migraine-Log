import SwiftUI
import MapKit

struct WeatherLocationEditorView: View {
    let migraine: MigraineEvent
    @ObservedObject var viewModel: MigraineViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager = LocationManager.shared
    
    @State private var latitude: String
    @State private var longitude: String
    @State private var useCurrentLocation = true
    @State private var isRefreshing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(migraine: MigraineEvent, viewModel: MigraineViewModel) {
        self.migraine = migraine
        self.viewModel = viewModel
        
        // Initialize with existing location or current location
        if migraine.hasWeatherData {
            _latitude = State(initialValue: String(format: "%.4f", migraine.weatherLatitude))
            _longitude = State(initialValue: String(format: "%.4f", migraine.weatherLongitude))
            _useCurrentLocation = State(initialValue: false)
        } else if let coords = LocationManager.shared.currentCoordinates {
            _latitude = State(initialValue: String(format: "%.4f", coords.latitude))
            _longitude = State(initialValue: String(format: "%.4f", coords.longitude))
        } else {
            _latitude = State(initialValue: "")
            _longitude = State(initialValue: "")
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Current Weather Data")) {
                    if migraine.hasWeatherData {
                        HStack {
                            Image(systemName: weatherIconForCode(Int(migraine.weatherCode)))
                                .foregroundColor(weatherIconColor(for: migraine.weatherCode))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(WeatherService.weatherCondition(for: Int(migraine.weatherCode)))
                                    .font(.headline)
                                Text(settings.formatTemperature(migraine.weatherTemperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Location")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.4f, %.4f", migraine.weatherLatitude, migraine.weatherLongitude))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No weather data available")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Fetch Weather for Location")) {
                    Toggle("Use Current Location", isOn: $useCurrentLocation)
                        .onChange(of: useCurrentLocation) { newValue in
                            if newValue, let coords = locationManager.currentCoordinates {
                                latitude = String(format: "%.4f", coords.latitude)
                                longitude = String(format: "%.4f", coords.longitude)
                            }
                        }
                    
                    if !useCurrentLocation {
                        HStack {
                            Text("Latitude")
                            TextField("e.g., 40.7128", text: $latitude)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Text("Longitude")
                            TextField("e.g., -74.0060", text: $longitude)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    Text("Weather data will be fetched for the migraine's start time at the specified location.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: {
                        Task {
                            await fetchWeather()
                        }
                    }) {
                        HStack {
                            Spacer()
                            if isRefreshing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isRefreshing ? "Fetching Weather..." : "Fetch Weather Data")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isRefreshing || (!useCurrentLocation && (latitude.isEmpty || longitude.isEmpty)))
                }
            }
            .navigationTitle("Weather Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func fetchWeather() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            let lat: Double
            let lon: Double
            
            if useCurrentLocation {
                // Get current location
                let location = try await locationManager.getCurrentLocation()
                lat = location.coordinate.latitude
                lon = location.coordinate.longitude
            } else {
                // Parse manual coordinates
                guard let parsedLat = Double(latitude),
                      let parsedLon = Double(longitude) else {
                    throw NSError(domain: "WeatherLocationEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid coordinates"])
                }
                
                // Validate coordinates
                guard parsedLat >= -90 && parsedLat <= 90 else {
                    throw NSError(domain: "WeatherLocationEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Latitude must be between -90 and 90"])
                }
                guard parsedLon >= -180 && parsedLon <= 180 else {
                    throw NSError(domain: "WeatherLocationEditor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Longitude must be between -180 and 180"])
                }
                
                lat = parsedLat
                lon = parsedLon
            }
            
            // Fetch weather for custom location
            await viewModel.fetchWeatherForCustomLocation(
                for: migraine,
                latitude: lat,
                longitude: lon
            )
            
            // Check if successful
            if migraine.hasWeatherData {
                dismiss()
            } else {
                await MainActor.run {
                    errorMessage = "Failed to fetch weather data. Please try again."
                    showingError = true
                }
            }
            
        } catch LocationError.unauthorized {
            await MainActor.run {
                errorMessage = "Location access is not authorized. Please enable location services in Settings."
                showingError = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    // Local copy of weather icon mapping
    private func weatherIconForCode(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.rain.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    
    private func weatherIconColor(for code: Int16) -> Color {
        let colorName = WeatherService.weatherColor(for: Int(code))
        switch colorName {
        case "yellow": return .yellow
        case "orange": return .orange
        case "gray": return .gray
        case "blue": return .blue
        case "cyan": return .cyan
        case "purple": return .purple
        default: return .gray
        }
    }
}

