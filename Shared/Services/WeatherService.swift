//
//  WeatherService.swift
//  NALI Migraine Log
//
//  Weather data service using Open-Meteo API
//

import Foundation
import CoreLocation

// MARK: - Weather Data Models

struct WeatherData: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let hourly: HourlyWeather
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, hourly
    }
}

struct HourlyWeather: Codable {
    let time: [String]
    let temperature2m: [Double]
    let surfacePressure: [Double]
    let precipitation: [Double]
    let cloudCover: [Int]
    let weatherCode: [Int]
    
    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case surfacePressure = "surface_pressure"
        case precipitation
        case cloudCover = "cloudcover"
        case weatherCode = "weathercode"
    }
}

struct WeatherSnapshot: Codable {
    let timestamp: Date
    let temperature: Double
    let pressure: Double
    let pressureChange24h: Double
    let precipitation: Double
    let cloudCover: Int
    let weatherCode: Int
    let weatherCondition: String
    let weatherIcon: String
    
    var weatherDescription: String {
        WeatherService.weatherDescription(for: weatherCode)
    }
}

// MARK: - Weather Service

@MainActor
class WeatherService: ObservableObject {
    static let shared = WeatherService()
    
    @Published var lastError: Error?
    @Published var isLoading = false
    
    private let baseURL = "https://archive-api.open-meteo.com/v1/archive"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Fetch historical weather data for a specific date and location
    func fetchWeatherSnapshot(
        for date: Date,
        latitude: Double,
        longitude: Double
    ) async throws -> WeatherSnapshot {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        
        // Get the date range: 24 hours before to 1 hour after the migraine
        let startDate = calendar.date(byAdding: .hour, value: -24, to: date) ?? date
        let endDate = calendar.date(byAdding: .hour, value: 1, to: date) ?? date
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        // Build URL with parameters
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "start_date", value: startDateString),
            URLQueryItem(name: "end_date", value: endDateString),
            URLQueryItem(name: "hourly", value: "temperature_2m,surface_pressure,precipitation,cloudcover,weathercode"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        print("Fetching weather from: \(url.absoluteString)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw WeatherError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let weatherData = try decoder.decode(WeatherData.self, from: data)
        
        // Find the closest hour to the migraine time
        let snapshot = try createSnapshot(from: weatherData, targetDate: date)
        
        return snapshot
    }
    
    /// Calculate 24-hour pressure change
    func calculatePressureChange(pressureData: [Double], targetIndex: Int) -> Double {
        guard targetIndex >= 24, targetIndex < pressureData.count else {
            // If we don't have 24 hours of data, calculate what we can
            let startIndex = max(0, targetIndex - min(targetIndex, 24))
            let currentPressure = pressureData[targetIndex]
            let previousPressure = pressureData[startIndex]
            return currentPressure - previousPressure
        }
        
        let currentPressure = pressureData[targetIndex]
        let pressure24hAgo = pressureData[targetIndex - 24]
        return currentPressure - pressure24hAgo
    }
    
    // MARK: - Private Methods
    
    private func createSnapshot(from weatherData: WeatherData, targetDate: Date) throws -> WeatherSnapshot {
        let hourly = weatherData.hourly
        
        guard !hourly.time.isEmpty else {
            throw WeatherError.noData
        }
        
        // Open-Meteo returns dates in format "2025-11-28T00:00" (no timezone suffix)
        // We need to try multiple formats
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Try parsing with the Open-Meteo format first (most common)
        let formats = [
            "yyyy-MM-dd'T'HH:mm",      // Open-Meteo format: 2025-11-28T00:00
            "yyyy-MM-dd'T'HH:mm:ss",   // With seconds: 2025-11-28T00:00:00
            "yyyy-MM-dd'T'HH:mm:ssZ",  // With timezone: 2025-11-28T00:00:00Z
            "yyyy-MM-dd'T'HH:mm:ssXXX" // With offset: 2025-11-28T00:00:00+00:00
        ]
        
        func parseDate(_ timeString: String) -> Date? {
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: timeString) {
                    return date
                }
            }
            // Also try ISO8601 as fallback
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: timeString) {
                return date
            }
            isoFormatter.formatOptions = [.withInternetDateTime]
            return isoFormatter.date(from: timeString)
        }
        
        var closestIndex = 0
        var smallestDifference = TimeInterval.infinity
        var foundValidDate = false
        
        for (index, timeString) in hourly.time.enumerated() {
            guard let timestamp = parseDate(timeString) else {
                print("⚠️ Could not parse date: \(timeString)")
                continue
            }
            foundValidDate = true
            let difference = abs(timestamp.timeIntervalSince(targetDate))
            if difference < smallestDifference {
                smallestDifference = difference
                closestIndex = index
            }
        }
        
        // If no valid dates were found, throw an error
        guard foundValidDate else {
            print("❌ No valid dates found in weather data. Sample time strings: \(hourly.time.prefix(3))")
            throw WeatherError.invalidDate
        }
        
        // Extract data for the closest hour
        let temperature = hourly.temperature2m[closestIndex]
        let pressure = hourly.surfacePressure[closestIndex]
        let precipitation = hourly.precipitation[closestIndex]
        let cloudCover = hourly.cloudCover[closestIndex]
        let weatherCode = hourly.weatherCode[closestIndex]
        
        // Calculate 24-hour pressure change
        let pressureChange = calculatePressureChange(
            pressureData: hourly.surfacePressure,
            targetIndex: closestIndex
        )
        
        let condition = Self.weatherCondition(for: weatherCode)
        let icon = Self.weatherIcon(for: weatherCode)
        
        // Get the timestamp for the snapshot
        guard let timestamp = parseDate(hourly.time[closestIndex]) else {
            print("❌ Could not parse timestamp for index \(closestIndex): \(hourly.time[closestIndex])")
            throw WeatherError.invalidDate
        }
        
        print("✅ Weather snapshot created: \(condition) at \(temperature)°F, pressure: \(pressure) hPa")
        
        return WeatherSnapshot(
            timestamp: timestamp,
            temperature: temperature,
            pressure: pressure,
            pressureChange24h: pressureChange,
            precipitation: precipitation,
            cloudCover: cloudCover,
            weatherCode: weatherCode,
            weatherCondition: condition,
            weatherIcon: icon
        )
    }
    
    // MARK: - Weather Code Mapping
    
    nonisolated static func weatherCondition(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with Hail"
        default: return "Unknown"
        }
    }
    
    nonisolated static func weatherIcon(for code: Int) -> String {
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
    
    nonisolated static func weatherDescription(for code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Light to moderate drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Light to heavy rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Light to heavy snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown conditions"
        }
    }
    
    nonisolated static func weatherColor(for code: Int) -> String {
        switch code {
        case 0, 1: return "yellow"
        case 2: return "orange"
        case 3: return "gray"
        case 45, 48: return "gray"
        case 51...57: return "blue"
        case 61...67: return "blue"
        case 71...77: return "cyan"
        case 80...86: return "blue"
        case 95...99: return "purple"
        default: return "gray"
        }
    }
}

// MARK: - Weather Errors

enum WeatherError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noData
    case invalidDate
    case locationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid weather API URL"
        case .invalidResponse:
            return "Invalid response from weather service"
        case .httpError(let code):
            return "Weather service error (HTTP \(code))"
        case .noData:
            return "No weather data available for this date"
        case .invalidDate:
            return "Invalid date format in weather data"
        case .locationUnavailable:
            return "Location data unavailable"
        }
    }
}

