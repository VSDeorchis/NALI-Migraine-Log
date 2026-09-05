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
    /// Weather models resolve ~1 km at best, so two decimals is all the
    /// precision the app ever needs. Rounding here (rather than at the URL
    /// only) keeps street-level coordinates out of the store, iCloud and
    /// anything derived from them.
    static func coarseCoordinate(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        return (value * 100).rounded() / 100
    }

    static func coordinateString(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), coarseCoordinate(value))
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

    /// Largest JSON body either endpoint legitimately returns is well under
    /// 1 MB (48 h × 6 hourly series); anything bigger is not a forecast.
    static let maxResponseBytes = 2 * 1_024 * 1_024

    /// Session with bounded timeouts and no persistent cookie/cache state;
    /// the app never needs the weather API to remember it.
    static func makeSession(requestTimeout: TimeInterval, resourceTimeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = false
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }

    static func makeRequest(url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Performs a GET and applies status, content-type and size checks before
    /// any byte of the body reaches a decoder.
    static func fetch(_ url: URL, using session: URLSession) async throws -> Data {
        let timeout = session.configuration.timeoutIntervalForRequest
        let (data, response) = try await session.data(for: makeRequest(url: url, timeout: timeout))
        try validateHTTP(response, bodyLength: data.count)
        return data
    }

    static func validateHTTP(_ response: URLResponse, bodyLength: Int) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherError.httpError(statusCode: http.statusCode)
        }
        if let contentType = http.value(forHTTPHeaderField: "Content-Type") {
            let mediaType = contentType
                .split(separator: ";", maxSplits: 1)
                .first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            guard mediaType == "application/json" || mediaType.hasSuffix("+json") else {
                AppLogger.weather.error("Open-Meteo returned unexpected content type \(mediaType, privacy: .public)")
                throw WeatherError.invalidResponse
            }
        }
        if http.expectedContentLength > Int64(maxResponseBytes) || bodyLength > maxResponseBytes {
            AppLogger.weather.error("Open-Meteo response too large: \(bodyLength, privacy: .public) bytes")
            throw WeatherError.responseTooLarge
        }
    }
}
