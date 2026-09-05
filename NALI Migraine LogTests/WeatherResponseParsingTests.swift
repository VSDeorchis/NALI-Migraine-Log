//
//  WeatherResponseParsingTests.swift
//  NALI Migraine LogTests
//
//  Open-Meteo payloads as they actually arrive: nulls for hours without
//  data, series of unequal length, unparsable timestamps, and responses that
//  aren't JSON at all. None of these may crash or produce a snapshot built
//  from misaligned values.
//

import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("Weather response parsing")
struct WeatherResponseParsingTests {

    private static let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> WeatherData {
        try Self.decoder.decode(WeatherData.self, from: Data(json.utf8))
    }

    /// Three hours in Europe/Paris on 2025-11-28 starting at 09:00 local.
    private let baseline = """
    {
      "latitude": 48.86, "longitude": 2.29, "timezone": "Europe/Paris",
      "hourly": {
        "time": ["2025-11-28T09:00", "2025-11-28T10:00", "2025-11-28T11:00"],
        "temperature_2m": [41.0, 42.5, 44.0],
        "surface_pressure": [1010.0, 1008.0, 1005.5],
        "precipitation": [0.0, 0.1, 0.0],
        "cloudcover": [20, 60, 100],
        "weathercode": [0, 2, 3]
      }
    }
    """

    @Test("Well-formed payload picks the hour nearest the target and honours the response timezone")
    func nearestHourInResponseTimezone() throws {
        let data = try decode(baseline)
        var components = DateComponents()
        components.year = 2025; components.month = 11; components.day = 28
        components.hour = 10; components.minute = 20
        components.timeZone = TimeZone(identifier: "Europe/Paris")
        let target = try #require(Calendar(identifier: .gregorian).date(from: components))

        let snapshot = try WeatherService.createSnapshot(from: data, targetDate: target)

        #expect(snapshot.temperature == 42.5)
        #expect(snapshot.pressure == 1008.0)
        #expect(snapshot.weatherCode == 2)
        #expect(snapshot.cloudCover == 60)
        #expect(snapshot.precipitation == 0.1)
        // Local 10:00 Paris == 09:00 UTC
        #expect(snapshot.timestamp == Date(timeIntervalSince1970: 1_764_320_400))
        // Only one earlier reading exists, so the 24 h change falls back to it.
        #expect(snapshot.pressureChange24h == -2.0)
    }

    @Test("Null hours are skipped rather than read as zero")
    func nullHoursSkipped() throws {
        let json = baseline
            .replacingOccurrences(of: "[41.0, 42.5, 44.0]", with: "[41.0, null, 44.0]")
            .replacingOccurrences(of: "[1010.0, 1008.0, 1005.5]", with: "[1010.0, null, 1005.5]")
        let data = try decode(json)
        // Target sits exactly on the null 10:00 sample; 09:00 and 11:00 are equidistant.
        let target = Date(timeIntervalSince1970: 1_764_320_400)

        let snapshot = try WeatherService.createSnapshot(from: data, targetDate: target)

        #expect(snapshot.temperature != 0)
        #expect(snapshot.pressure != 0)
        #expect([41.0, 44.0].contains(snapshot.temperature))
    }

    @Test("Payload where every hour is null throws noData")
    func allNullThrows() throws {
        let json = baseline
            .replacingOccurrences(of: "[41.0, 42.5, 44.0]", with: "[null, null, null]")
        let data = try decode(json)

        #expect(throws: WeatherError.noData) {
            try WeatherService.createSnapshot(from: data, targetDate: Date(timeIntervalSince1970: 1_764_320_400))
        }
    }

    @Test("Truncated series is rejected before any index is read")
    func truncatedSeriesRejected() throws {
        let json = baseline.replacingOccurrences(of: "[1010.0, 1008.0, 1005.5]", with: "[1010.0, 1008.0]")
        let data = try decode(json)

        #expect(throws: WeatherError.malformedResponse(field: "surface_pressure")) {
            try WeatherService.createSnapshot(from: data, targetDate: Date(timeIntervalSince1970: 1_764_320_400))
        }
    }

    @Test("Empty time series throws noData")
    func emptyTimeSeries() throws {
        let json = """
        {"latitude": 0, "longitude": 0, "timezone": "UTC",
         "hourly": {"time": [], "temperature_2m": [], "surface_pressure": [],
                    "precipitation": [], "cloudcover": [], "weathercode": []}}
        """
        let data = try decode(json)
        #expect(throws: WeatherError.noData) {
            try WeatherService.createSnapshot(from: data, targetDate: Date())
        }
    }

    @Test("Unparsable timestamps are skipped; a usable neighbour is still returned")
    func badTimestampSkipped() throws {
        let json = baseline.replacingOccurrences(of: "\"2025-11-28T10:00\"", with: "\"not-a-date\"")
        let data = try decode(json)
        let snapshot = try WeatherService.createSnapshot(from: data, targetDate: Date(timeIntervalSince1970: 1_764_320_400))
        #expect(snapshot.weatherCode != 2)
    }

    @Test("Wrong JSON shape and non-JSON bodies fail decoding instead of crashing")
    func malformedBodies() {
        let notJSON = Data("<html>Service Unavailable</html>".utf8)
        #expect(throws: (any Error).self) { try Self.decoder.decode(WeatherData.self, from: notJSON) }

        let stringsInsteadOfNumbers = Data("""
        {"latitude": 0, "longitude": 0, "hourly": {"time": ["2025-11-28T09:00"],
         "temperature_2m": ["warm"], "surface_pressure": [1], "precipitation": [0],
         "cloudcover": [0], "weathercode": [0]}}
        """.utf8)
        #expect(throws: (any Error).self) { try Self.decoder.decode(WeatherData.self, from: stringsInsteadOfNumbers) }

        let missingHourly = Data("{\"latitude\": 0, \"longitude\": 0}".utf8)
        #expect(throws: (any Error).self) { try Self.decoder.decode(WeatherData.self, from: missingHourly) }
    }

    @Test("Pressure change walks forward past nulls and returns nil without a current reading")
    func pressureChange() {
        let series: [Double?] = [1000, nil, nil, 1004, 1006]
        #expect(WeatherService.calculatePressureChange(pressureData: series, targetIndex: 4) == 6)
        #expect(WeatherService.calculatePressureChange(pressureData: series, targetIndex: 3) == 4)
        #expect(WeatherService.calculatePressureChange(pressureData: series, targetIndex: 1) == nil)
        #expect(WeatherService.calculatePressureChange(pressureData: series, targetIndex: 0) == 0)
        #expect(WeatherService.calculatePressureChange(pressureData: series, targetIndex: 99) == nil)
        #expect(WeatherService.calculatePressureChange(pressureData: [], targetIndex: 0) == nil)
    }

    @Test("HTTP validation rejects non-JSON content types, error statuses and oversized bodies")
    func httpValidation() throws {
        let url = try #require(URL(string: "https://archive-api.open-meteo.com/v1/archive"))
        func response(_ status: Int, contentType: String?, length: Int64 = -1) -> HTTPURLResponse? {
            var headers: [String: String] = [:]
            if let contentType { headers["Content-Type"] = contentType }
            return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        }

        let ok = try #require(response(200, contentType: "application/json; charset=utf-8"))
        #expect(throws: Never.self) { try OpenMeteo.validateHTTP(ok, bodyLength: 512) }

        let html = try #require(response(200, contentType: "text/html"))
        #expect(throws: WeatherError.invalidResponse) { try OpenMeteo.validateHTTP(html, bodyLength: 512) }

        let serverError = try #require(response(503, contentType: "application/json"))
        #expect(throws: WeatherError.httpError(statusCode: 503)) { try OpenMeteo.validateHTTP(serverError, bodyLength: 0) }

        #expect(throws: WeatherError.responseTooLarge) {
            try OpenMeteo.validateHTTP(ok, bodyLength: OpenMeteo.maxResponseBytes + 1)
        }

        #expect(throws: WeatherError.invalidResponse) {
            try OpenMeteo.validateHTTP(URLResponse(), bodyLength: 0)
        }
    }

    @Test("Coordinates outside the valid range are rejected before a URL is built")
    func coordinateValidation() {
        #expect(throws: Never.self) { try OpenMeteo.validate(latitude: 89.9, longitude: -179.9) }
        #expect(throws: WeatherError.invalidCoordinates) { try OpenMeteo.validate(latitude: 90.1, longitude: 0) }
        #expect(throws: WeatherError.invalidCoordinates) { try OpenMeteo.validate(latitude: 0, longitude: 180.5) }
        #expect(throws: WeatherError.invalidCoordinates) { try OpenMeteo.validate(latitude: .nan, longitude: 0) }
        #expect(throws: WeatherError.invalidCoordinates) { try OpenMeteo.validate(latitude: 0, longitude: .infinity) }
    }
}
