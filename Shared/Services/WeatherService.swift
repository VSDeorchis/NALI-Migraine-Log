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
    let timezone: String?
    let hourly: HourlyWeather
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, hourly
    }
}

/// Hourly series are decoded as optionals because Open-Meteo emits `null`
/// for hours it has no data for (very recent archive hours, model gaps).
struct HourlyWeather: Codable {
    let time: [String]
    let temperature2m: [Double?]
    let surfacePressure: [Double?]
    let precipitation: [Double?]
    let cloudCover: [Int?]
    let weatherCode: [Int?]
    
    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case surfacePressure = "surface_pressure"
        case precipitation
        case cloudCover = "cloudcover"
        case weatherCode = "weathercode"
    }
}

struct WeatherSnapshot: Codable, Sendable {
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
        self.session = OpenMeteo.makeSession(requestTimeout: 30, resourceTimeout: 60)
    }
    
    // MARK: - Public Methods
    
    /// Fetch historical weather data for a specific date and location
    func fetchWeatherSnapshot(
        for date: Date,
        latitude: Double,
        longitude: Double
    ) async throws -> WeatherSnapshot {
        try OpenMeteo.validate(latitude: latitude, longitude: longitude)

        isLoading = true
        defer { isLoading = false }

        // Request a generous window (2 days back, 1 day forward) in UTC so the
        // 24-hour pressure baseline is present regardless of the offset
        // between the device's zone and the location's zone.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        // The archive endpoint rejects future dates.
        let endDate = min(utc.date(byAdding: .day, value: 1, to: date) ?? date, Date())
        let startDate = min(utc.date(byAdding: .day, value: -2, to: date) ?? date, endDate)

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = utc.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let url = try OpenMeteo.makeURL(base: baseURL, queryItems: [
            URLQueryItem(name: "latitude", value: OpenMeteo.coordinateString(latitude)),
            URLQueryItem(name: "longitude", value: OpenMeteo.coordinateString(longitude)),
            URLQueryItem(name: "start_date", value: dayFormatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: dayFormatter.string(from: endDate)),
            URLQueryItem(name: "hourly", value: "temperature_2m,surface_pressure,precipitation,cloudcover,weathercode"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto")
        ])

        AppLogger.weather.debug("Fetching archive weather for \(dayFormatter.string(from: startDate), privacy: .public)..\(dayFormatter.string(from: endDate), privacy: .public)")

        let data = try await OpenMeteo.fetch(url, using: session)

        // Decoding + nearest-hour search are pure functions of the payload;
        // run them off the main actor.
        let target = date
        return try await Task.detached(priority: .userInitiated) {
            let weatherData = try JSONDecoder().decode(WeatherData.self, from: data)
            return try Self.createSnapshot(from: weatherData, targetDate: target)
        }.value
    }
    
    /// Pressure change over the 24 hours preceding `targetIndex`, falling
    /// back to the earliest available reading when fewer than 24 hours of
    /// data precede it. Returns `nil` if either endpoint is missing.
    nonisolated static func calculatePressureChange(pressureData: [Double?], targetIndex: Int) -> Double? {
        guard pressureData.indices.contains(targetIndex),
              let currentPressure = pressureData[targetIndex] else {
            return nil
        }
        let baselineIndex = max(0, targetIndex - 24)
        // Walk forward from the ideal baseline until a non-null sample is found.
        for index in baselineIndex..<targetIndex {
            if let previous = pressureData[index] {
                return currentPressure - previous
            }
        }
        return 0
    }
    
    // MARK: - Private Methods
    
    nonisolated static func createSnapshot(from weatherData: WeatherData, targetDate: Date) throws -> WeatherSnapshot {
        let hourly = weatherData.hourly

        try OpenMeteo.requireAlignedSeries(timeCount: hourly.time.count, series: [
            ("temperature_2m", hourly.temperature2m.count),
            ("surface_pressure", hourly.surfacePressure.count),
            ("precipitation", hourly.precipitation.count),
            ("cloudcover", hourly.cloudCover.count),
            ("weathercode", hourly.weatherCode.count)
        ])

        let parser = OpenMeteo.TimeParser(timeZoneIdentifier: weatherData.timezone)

        // Nearest hour that has a complete set of readings.
        var best: (index: Int, timestamp: Date, distance: TimeInterval)?
        for (index, timeString) in hourly.time.enumerated() {
            guard let timestamp = parser.date(from: timeString) else {
                AppLogger.weather.error("Could not parse date string: \(timeString, privacy: .public)")
                continue
            }
            guard hourly.temperature2m[index] != nil,
                  hourly.surfacePressure[index] != nil,
                  hourly.weatherCode[index] != nil else { continue }
            let distance = abs(timestamp.timeIntervalSince(targetDate))
            if let current = best, distance >= current.distance { continue }
            best = (index, timestamp, distance)
        }

        guard let best,
              let temperature = hourly.temperature2m[best.index],
              let pressure = hourly.surfacePressure[best.index],
              let weatherCode = hourly.weatherCode[best.index] else {
            AppLogger.weather.error("No usable hourly sample in weather payload (\(hourly.time.count, privacy: .public) hours)")
            throw WeatherError.noData
        }
        let closestIndex = best.index
        let timestamp = best.timestamp

        let pressureChange = calculatePressureChange(
            pressureData: hourly.surfacePressure,
            targetIndex: closestIndex
        ) ?? 0

        let condition = Self.weatherCondition(for: weatherCode)
        AppLogger.weather.debug("Weather snapshot built: \(condition, privacy: .public) at \(temperature, privacy: .public)°F, pressure \(pressure, privacy: .public) hPa")

        return WeatherSnapshot(
            timestamp: timestamp,
            temperature: temperature,
            pressure: pressure,
            pressureChange24h: pressureChange,
            precipitation: hourly.precipitation[closestIndex] ?? 0,
            cloudCover: hourly.cloudCover[closestIndex] ?? 0,
            weatherCode: weatherCode,
            weatherCondition: condition,
            weatherIcon: Self.weatherIcon(for: weatherCode)
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

enum WeatherError: LocalizedError, Equatable {
    case invalidURL
    case invalidCoordinates
    case invalidResponse
    case httpError(statusCode: Int)
    case responseTooLarge
    case malformedResponse(field: String)
    case noData
    case invalidDate
    case locationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid weather API URL"
        case .invalidCoordinates:
            return "Location coordinates are out of range"
        case .invalidResponse:
            return "Invalid response from weather service"
        case .httpError(let code):
            return "Weather service error (HTTP \(code))"
        case .responseTooLarge:
            return "Weather service returned an unexpectedly large response"
        case .malformedResponse(let field):
            return "Weather service returned incomplete data (\(field))"
        case .noData:
            return "No weather data available for this date"
        case .invalidDate:
            return "Invalid date format in weather data"
        case .locationUnavailable:
            return "Location data unavailable"
        }
    }
}

