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
    let hourly: HourlyForecast
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, hourly
    }
}

struct HourlyForecast: Codable {
    let time: [String]
    let temperature2m: [Double]
    let surfacePressure: [Double]
    let precipitation: [Double]
    let cloudCover: [Int]
    let weatherCode: [Int]
    let relativeHumidity2m: [Int]
    
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
        // Return cached data if still fresh
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout,
           !currentForecast.isEmpty {
            return currentForecast
        }
        
        isLoading = true
        defer { isLoading = false }
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,surface_pressure,precipitation,cloudcover,weathercode,relativehumidity_2m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.invalidResponse
        }
        
        let forecast = try JSONDecoder().decode(ForecastData.self, from: data)
        let hours = parseForecast(forecast)
        
        currentForecast = hours
        lastFetchTime = Date()
        lastError = nil
        
        return hours
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
    
    private func parseForecast(_ forecast: ForecastData) -> [ForecastHour] {
        let hourly = forecast.hourly
        guard !hourly.time.isEmpty else { return [] }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        
        func parseDate(_ s: String) -> Date? {
            for fmt in formats {
                dateFormatter.dateFormat = fmt
                if let d = dateFormatter.date(from: s) { return d }
            }
            return nil
        }
        
        let basePressure = hourly.surfacePressure.first ?? 1013.0
        var hours: [ForecastHour] = []
        
        for i in 0..<hourly.time.count {
            guard let date = parseDate(hourly.time[i]) else { continue }
            let code = hourly.weatherCode[i]
            
            hours.append(ForecastHour(
                date: date,
                hour: Calendar.current.component(.hour, from: date),
                temperature: hourly.temperature2m[i],
                pressure: hourly.surfacePressure[i],
                pressureChange: hourly.surfacePressure[i] - basePressure,
                precipitation: hourly.precipitation[i],
                cloudCover: hourly.cloudCover[i],
                weatherCode: code,
                humidity: hourly.relativeHumidity2m[i],
                weatherCondition: WeatherService.weatherCondition(for: code),
                weatherIcon: WeatherService.weatherIcon(for: code)
            ))
        }
        return hours
    }
}
