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
import CloudKit
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
        #expect(!SyncStatus.signInRequired("sign in").isActive)
    }

    @Test("syncing description renders an integer percentage")
    func syncingPercentage() {
        #expect(SyncStatus.syncing(0.0).description == "Syncing 0%")
        #expect(SyncStatus.syncing(0.42).description == "Syncing 42%")
        #expect(SyncStatus.syncing(1.0).description == "Syncing 100%")
    }

    @Test("signInRequired surfaces its message verbatim (no 'Error:' prefix)")
    func signInRequiredDescription() {
        #expect(SyncStatus.signInRequired("Sign in to iCloud").description == "Sign in to iCloud")
    }
}

@Suite("No-iCloud-account error detection")
struct NoAccountErrorTests {

    @Test("Recognizes the Cocoa 134400 'no iCloud account' setup error")
    func cocoa134400IsNoAccount() {
        // NSPersistentCloudKitContainer reports a missing account this way:
        // NSCocoaErrorDomain Code=134400 "Unable to initialize without an
        // iCloud account (CKAccountStatusNoAccount)."
        let error = NSError(domain: NSCocoaErrorDomain, code: 134400)
        #expect(PersistenceController.isNoAccountError(error))
    }

    @Test("Recognizes a direct CKError.notAuthenticated")
    func directNotAuthenticatedIsNoAccount() {
        #expect(PersistenceController.isNoAccountError(CKError(.notAuthenticated)))
    }

    @Test("Recognizes a CKError.notAuthenticated buried in the underlying-error chain")
    func nestedNotAuthenticatedIsNoAccount() {
        let nested = NSError(
            domain: "SomeWrapperDomain",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: CKError(.notAuthenticated)]
        )
        #expect(PersistenceController.isNoAccountError(nested))
    }

    @Test("Unrelated errors are not treated as no-account")
    func unrelatedErrorIsNotNoAccount() {
        #expect(!PersistenceController.isNoAccountError(CKError(.networkUnavailable)))
        #expect(!PersistenceController.isNoAccountError(NSError(domain: NSCocoaErrorDomain, code: 134060)))
    }
}
