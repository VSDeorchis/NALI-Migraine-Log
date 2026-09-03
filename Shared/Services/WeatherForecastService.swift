//
//  WeatherForecastService.swift
//  NALI Migraine Log
//
//  Forward-looking weather forecast using Open-Meteo Forecast API.
//  Free, no API key required.
//

import Foundation
import CoreLocation

// MARK: - Forecast Data Models

struct ForecastData: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let hourly: HourlyForecast
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, hourly
    }
}

/// See `HourlyWeather` for why the series are optional.
struct HourlyForecast: Codable {
    let time: [String]
    let temperature2m: [Double?]
    let surfacePressure: [Double?]
    let precipitation: [Double?]
    let cloudCover: [Int?]
    let weatherCode: [Int?]
    let relativeHumidity2m: [Int?]
    
    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case surfacePressure = "surface_pressure"
        case precipitation
        case cloudCover = "cloudcover"
        case weatherCode = "weathercode"
        case relativeHumidity2m = "relativehumidity_2m"
    }
}

/// A single hour in the forecast, enriched with computed fields.
struct ForecastHour: Identifiable {
    let id = UUID()
    let date: Date
    let hour: Int
    let temperature: Double
    let pressure: Double
    let pressureChange: Double          // change from first hour in forecast
    let precipitation: Double
    let cloudCover: Int
    let weatherCode: Int
    let humidity: Int
    let weatherCondition: String
    let weatherIcon: String
}

// MARK: - Forecast Service

@MainActor
class WeatherForecastService: ObservableObject {
    static let shared = WeatherForecastService()
    
    @Published var currentForecast: [ForecastHour] = []
    @Published var isLoading = false
    @Published var lastError: Error?
    @Published var lastFetchTime: Date?
    
    private let baseURL = "https://api.open-meteo.com/v1/forecast"
    private let session: URLSession
    private let cacheTimeout: TimeInterval = 1800  // 30 minutes
    /// Coordinates the cached forecast was fetched for, rounded like the
    /// request itself so tiny GPS jitter still hits the cache.
    private var cachedCoordinateKey: String?
    private var inFlight: Task<[ForecastHour], Error>?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Fetch the next 48 hours of weather forecast.
    /// Results are cached for 30 minutes.
    func fetchForecast(latitude: Double, longitude: Double) async throws -> [ForecastHour] {
        try OpenMeteo.validate(latitude: latitude, longitude: longitude)
        let coordinateKey = "\(OpenMeteo.coordinateString(latitude)),\(OpenMeteo.coordinateString(longitude))"

        if let lastFetch = lastFetchTime,
           cachedCoordinateKey == coordinateKey,
           Date().timeIntervalSince(lastFetch) < cacheTimeout,
           !currentForecast.isEmpty {
            return currentForecast
        }

        // Coalesce concurrent callers (risk view, background refresh, Watch
        // push) onto one network request.
        if let inFlight {
            return try await inFlight.value
        }

        let request = Task<[ForecastHour], Error> { @MainActor [baseURL, session] in
            let url = try OpenMeteo.makeURL(base: baseURL, queryItems: [
                URLQueryItem(name: "latitude", value: OpenMeteo.coordinateString(latitude)),
                URLQueryItem(name: "longitude", value: OpenMeteo.coordinateString(longitude)),
                URLQueryItem(name: "hourly", value: "temperature_2m,surface_pressure,precipitation,cloudcover,weathercode,relativehumidity_2m"),
                URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
                URLQueryItem(name: "precipitation_unit", value: "inch"),
                URLQueryItem(name: "forecast_days", value: "2"),
                URLQueryItem(name: "timezone", value: "auto")
            ])

            let (data, response) = try await session.data(from: url)
            try OpenMeteo.validateHTTP(response)

            return try await Task.detached(priority: .userInitiated) {
                let forecast = try JSONDecoder().decode(ForecastData.self, from: data)
                return try Self.parseForecast(forecast)
            }.value
        }
        inFlight = request
        isLoading = true
        defer {
            inFlight = nil
            isLoading = false
        }

        do {
            let hours = try await request.value
            currentForecast = hours
            cachedCoordinateKey = coordinateKey
            lastFetchTime = Date()
            lastError = nil
            return hours
        } catch {
            lastError = error
            throw error
        }
    }
    
    /// Get the forecast for the next N hours from now.
    func next(hours count: Int) -> [ForecastHour] {
        let now = Date()
        return currentForecast
            .filter { $0.date >= now }
            .prefix(count)
            .map { $0 }
    }
    
    /// Get the maximum absolute pressure change expected in the next N hours.
    func maxPressureChange(inNext hours: Int) -> Double {
        let upcoming = next(hours: hours)
        guard let first = upcoming.first else { return 0 }
        let basePressure = first.pressure
        return upcoming.map { abs($0.pressure - basePressure) }.max() ?? 0
    }
    
    /// Build a WeatherSnapshot from the forecast for "right now"
    /// so the prediction engine can consume it the same way as historical data.
    func currentWeatherSnapshot() -> WeatherSnapshot? {
        guard let closest = next(hours: 1).first else { return nil }
        
        // Calculate pressure change relative to 24 hours back if available
        let pressureChange: Double
        if currentForecast.count > 24,
           let idx = currentForecast.firstIndex(where: { $0.date >= closest.date }) {
            let backIdx = max(0, idx - 24)
            pressureChange = closest.pressure - currentForecast[backIdx].pressure
        } else {
            pressureChange = closest.pressureChange
        }
        
        return WeatherSnapshot(
            timestamp: closest.date,
            temperature: closest.temperature,
            pressure: closest.pressure,
            pressureChange24h: pressureChange,
            precipitation: closest.precipitation,
            cloudCover: closest.cloudCover,
            weatherCode: closest.weatherCode,
            weatherCondition: closest.weatherCondition,
            weatherIcon: closest.weatherIcon
        )
    }
    
    // MARK: - Private
    
    nonisolated private static func parseForecast(_ forecast: ForecastData) throws -> [ForecastHour] {
        let hourly = forecast.hourly
        try OpenMeteo.requireAlignedSeries(timeCount: hourly.time.count, series: [
            ("temperature_2m", hourly.temperature2m.count),
            ("surface_pressure", hourly.surfacePressure.count),
            ("precipitation", hourly.precipitation.count),
            ("cloudcover", hourly.cloudCover.count),
            ("weathercode", hourly.weatherCode.count),
            ("relativehumidity_2m", hourly.relativeHumidity2m.count)
        ])

        let parser = OpenMeteo.TimeParser(timeZoneIdentifier: forecast.timezone)
        // `hour` is displayed to the user, so express it in the device's zone.
        let calendar = Calendar.current
        let basePressure = hourly.surfacePressure.compactMap { $0 }.first ?? 1013.0
        var hours: [ForecastHour] = []
        hours.reserveCapacity(hourly.time.count)

        for i in hourly.time.indices {
            guard let date = parser.date(from: hourly.time[i]),
                  let temperature = hourly.temperature2m[i],
                  let pressure = hourly.surfacePressure[i],
                  let code = hourly.weatherCode[i] else { continue }

            hours.append(ForecastHour(
                date: date,
                hour: calendar.component(.hour, from: date),
                temperature: temperature,
                pressure: pressure,
                pressureChange: pressure - basePressure,
                precipitation: hourly.precipitation[i] ?? 0,
                cloudCover: hourly.cloudCover[i] ?? 0,
                weatherCode: code,
                humidity: hourly.relativeHumidity2m[i] ?? 0,
                weatherCondition: WeatherService.weatherCondition(for: code),
                weatherIcon: WeatherService.weatherIcon(for: code)
            ))
        }
        return hours
    }
}
