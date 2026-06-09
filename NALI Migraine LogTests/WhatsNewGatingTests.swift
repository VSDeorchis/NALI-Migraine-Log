//
//  WhatsNewGatingTests.swift
//  NALI Migraine LogTests
//
//  Tests the one-time "What's New" presentation gate (`WhatsNew`).
//
//  Policy under test:
//   • Show once per `currentRelease`, then never again.
//   • Suppress (and silently stamp as seen) for a brand-new install so a
//     first-time user never gets an "update" announcement.
//

import Testing
import Foundation
@testable import NALI_Migraine_Log

@Suite("What's New presentation gate", .serialized)
struct WhatsNewGatingTests {

    /// Runs `body` with `WhatsNew.defaults` pointed at a throwaway suite,
    /// restoring the real one afterwards.
    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "test.whatsnew.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let original = WhatsNew.defaults
        WhatsNew.defaults = defaults
        defer {
            WhatsNew.defaults = original
            defaults.removePersistentDomain(forName: suiteName)
        }
        body(defaults)
    }

    @Test("Upgrading user who hasn't seen this release is shown the sheet")
    func upgraderSeesSheet() {
        withIsolatedDefaults { _ in
            #expect(WhatsNew.shouldPresentOnLaunch(launchCount: 8) == true)
        }
    }

    @Test("Brand-new install (launch 1) is suppressed and stamped as seen")
    func freshInstallSuppressed() {
        withIsolatedDefaults { defaults in
            #expect(WhatsNew.shouldPresentOnLaunch(launchCount: 1) == false)
            // Stamped, so a later upgrade-style launch won't show it either.
            #expect(defaults.string(forKey: Constants.lastSeenWhatsNewRelease) == WhatsNew.currentRelease)
            #expect(WhatsNew.shouldPresentOnLaunch(launchCount: 5) == false)
        }
    }

    @Test("Shown only once: after markSeen the sheet is not presented again")
    func shownOnlyOnce() {
        withIsolatedDefaults { _ in
            #expect(WhatsNew.shouldPresentOnLaunch(launchCount: 8) == true)
            WhatsNew.markSeen()
            #expect(WhatsNew.shouldPresentOnLaunch(launchCount: 9) == false)
        }
    }

    @Test("A different (older) stamped release still triggers the current one")
    func newReleaseRetriggers() {
        withIsolatedDefaults { defaults in
            defaults.set("some-older-release", forKey: Constants.lastSeenWhatsNewRelease)
            #expect(WhatsNew.shouldPresentOnLaunch(launchCount: 12) == true)
        }
    }
}
