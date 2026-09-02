//
//  OpenMeteoSupport.swift
//  NALI Migraine Log
//
//  Shared request/response plumbing for the Open-Meteo archive and forecast
//  endpoints: coordinate validation, URL building, timezone-aware timestamp
//  parsing and parallel-array length checks.
//

import Foundation

enum OpenMeteo {
    /// Rounds to ~1 km so URLs (and cache keys) never carry more precision
    /// than the weather model resolves.
    static func coordinateString(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func validate(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            throw WeatherError.invalidCoordinates
        }
    }

    static func makeURL(base: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw WeatherError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw WeatherError.invalidURL
        }
        return url
    }

    /// Open-Meteo returns local wall-clock strings ("2025-11-28T00:00") in the
    /// timezone named by the response's `timezone` field when `timezone=auto`
    /// is requested. Parsing them in the device's zone shifts every sample by
    /// the offset difference whenever the user logs from a different zone.
    struct TimeParser {
        private let formatter: DateFormatter
        private let iso: ISO8601DateFormatter
        private static let formats = [
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXX"
        ]

        init(timeZoneIdentifier: String?) {
            let zone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            iso = ISO8601DateFormatter()
        }

        func date(from string: String) -> Date? {
            for format in Self.formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: string) { return date }
            }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: string)
        }
    }

    /// Ensures every hourly series has one value per timestamp so index
    /// `i` of any array refers to `time[i]`.
    static func requireAlignedSeries(timeCount: Int, series: [(name: String, count: Int)]) throws {
        guard timeCount > 0 else { throw WeatherError.noData }
        for (name, count) in series where count != timeCount {
            AppLogger.weather.error("Open-Meteo series '\(name, privacy: .public)' has \(count, privacy: .public) values for \(timeCount, privacy: .public) timestamps")
            throw WeatherError.malformedResponse(field: name)
        }
    }

    static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherError.httpError(statusCode: http.statusCode)
        }
    }
}
