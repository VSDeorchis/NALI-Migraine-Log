//
//  ICloudSyncPreferenceTests.swift
//  NALI Migraine LogTests
//
//  Tests for the smart default behind "Enable iCloud Sync"
//  (`UserDefaults.headwayICloudSyncEnabled`) and the `SyncStatus` value type.
//
//  The default is what fixes the App Store complaint that two devices don't
//  talk to each other: sync must be ON unless the user has explicitly opted
//  out. An explicit `false` must always be honoured so we never re-enable sync
//  for someone who deliberately turned it off.
//

import Testing
import Foundation
@testable import NALI_Migraine_Log

@Suite("iCloud sync preference default")
struct ICloudSyncPreferenceTests {

    /// A throwaway, isolated `UserDefaults` so tests never touch real app state.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "test.icloudsync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test("Defaults ON when the user has never made a choice")
    func defaultsOnWhenUnset() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.object(forKey: "useICloudSync") == nil)
        #expect(defaults.headwayICloudSyncEnabled == true)
    }

    @Test("Honours an explicit opt-out (false always wins)")
    func respectsExplicitOptOut() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: "useICloudSync")
        #expect(defaults.headwayICloudSyncEnabled == false)
    }

    @Test("Honours an explicit opt-in")
    func respectsExplicitOptIn() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "useICloudSync")
        #expect(defaults.headwayICloudSyncEnabled == true)
    }
}

@Suite("SyncStatus value type")
struct SyncStatusTests {

    @Test("isActive is true only while syncing/enabled/pending")
    func activeStates() {
        #expect(SyncStatus.enabled.isActive)
        #expect(SyncStatus.syncing(0.5).isActive)
        #expect(SyncStatus.pendingChanges(3).isActive)
        #expect(!SyncStatus.disabled.isActive)
        #expect(!SyncStatus.notConfigured.isActive)
        #expect(!SyncStatus.error("boom").isActive)
    }

    @Test("syncing description renders an integer percentage")
    func syncingPercentage() {
        #expect(SyncStatus.syncing(0.0).description == "Syncing 0%")
        #expect(SyncStatus.syncing(0.42).description == "Syncing 42%")
        #expect(SyncStatus.syncing(1.0).description == "Syncing 100%")
    }
}
