//
//  CoordinatePrivacyTests.swift
//  NALI Migraine LogTests
//
//  Weather coordinates are rounded to two decimals (~1 km) before they are
//  stored or sent. Covers the rounding helper, the Core Data setter every
//  save path goes through, and the 3.01 upgrade step that backfills
//  entries saved with a raw GPS fix.
//

import CoreData
import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("Coordinate privacy", .serialized)
@MainActor
struct CoordinatePrivacyTests {

    @Test("coarseCoordinate rounds to two decimals and leaves non-finite values alone")
    func rounding() {
        #expect(OpenMeteo.coarseCoordinate(40.712_776) == 40.71)
        #expect(OpenMeteo.coarseCoordinate(-74.005_974) == -74.01)
        #expect(OpenMeteo.coarseCoordinate(0.004_999) == 0)
        #expect(OpenMeteo.coarseCoordinate(0.005_001) == 0.01)
        #expect(OpenMeteo.coarseCoordinate(51.5) == 51.5)
        #expect(OpenMeteo.coarseCoordinate(Double.nan).isNaN)
        #expect(OpenMeteo.coarseCoordinate(Double.infinity) == .infinity)
    }

    @Test("Rounding is idempotent so a migrated value never drifts on re-save")
    func idempotent() {
        let once = OpenMeteo.coarseCoordinate(-33.868_820)
        #expect(OpenMeteo.coarseCoordinate(once) == once)
    }

    @Test("Request coordinate strings are locale-independent and two decimals wide")
    func coordinateString() {
        #expect(OpenMeteo.coordinateString(40.712_776) == "40.71")
        #expect(OpenMeteo.coordinateString(-74.005_974) == "-74.01")
        #expect(OpenMeteo.coordinateString(2) == "2.00")
        #expect(!OpenMeteo.coordinateString(1.5).contains(","))
    }

    @Test("updateWeatherLocation never stores more than two decimals")
    func storedCoordinatesAreCoarse() throws {
        let context = PersistenceController.preview.container.viewContext
        let event = MigraineEvent(context: context)
        event.id = UUID()
        event.startTime = Date()

        event.updateWeatherLocation(latitude: 37.331_686, longitude: -122.030_656)

        #expect(event.weatherLatitude == 37.33)
        #expect(event.weatherLongitude == -122.03)
        context.delete(event)
        try context.save()
    }

    @Test("3.01 upgrade step coarsens legacy coordinates and leaves unset ones untouched")
    func migrationBackfill() throws {
        let context = PersistenceController.preview.container.viewContext

        let legacy = MigraineEvent(context: context)
        legacy.id = UUID()
        legacy.startTime = Date()
        legacy.weatherLatitude = 48.858_370
        legacy.weatherLongitude = 2.294_481

        let untouched = MigraineEvent(context: context)
        untouched.id = UUID()
        untouched.startTime = Date()
        try context.save()

        try MigrationCoordinator.coarsenStoredWeatherCoordinates(in: context)

        #expect(legacy.weatherLatitude == 48.86)
        #expect(legacy.weatherLongitude == 2.29)
        #expect(untouched.weatherLatitude == 0)
        #expect(untouched.weatherLongitude == 0)
        // Only the entry that actually changed is dirty.
        #expect(legacy.hasChanges)
        #expect(!untouched.hasChanges)

        context.delete(legacy)
        context.delete(untouched)
        try context.save()
    }

    @Test("Upgrade step applies only when coming from a version below 3.01")
    func migrationGate() {
        let step = MigrationCoordinator.upgradeStep(id: "v3.01-coarsen-weather-coordinates")
        #expect(step != nil)
        #expect(step?.appliesWhen("2.83", "3.01") == true)
        #expect(step?.appliesWhen("3.0", "3.01") == true)
        #expect(step?.appliesWhen("3.01", "3.02") == false)
        #expect(step?.appliesWhen("3.1", "3.2") == false)
    }
}
