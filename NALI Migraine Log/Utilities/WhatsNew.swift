//
//  WhatsNew.swift
//  NALI Migraine Log
//
//  Decides whether to show the one-time "What's New" announcement sheet
//  after an app update. Gating lives here (separate from the view) so it
//  can be unit-tested without a UI.
//
//  Policy:
//   • Show the sheet once per *feature release* — identified by
//     `currentRelease` rather than the marketing version, so the
//     announcement is decoupled from routine build-number bumps.
//   • Never show it to a brand-new install (launch count 1): nothing is
//     "new" to a first-time user. We silently stamp the current release
//     so they only ever see *future* announcements.
//

import Foundation

enum WhatsNew {
    /// Bump this whenever there's a new announcement to show. The string
    /// is opaque — only equality matters.
    static let currentRelease = "watch-cycle-analytics-2026.09"

    /// Injectable for tests; production uses `.standard`.
    static var defaults: UserDefaults = .standard

    /// Whether the What's New sheet should be presented this launch.
    ///
    /// - Parameter launchCount: the monotonic launch counter (post-increment
    ///   for this launch), e.g. `ReviewPromptCoordinator.launchCount`.
    /// - Returns: `true` only for an upgrading user who hasn't yet seen
    ///   `currentRelease`. Brand-new installs are suppressed *and* stamped
    ///   as seen so they don't get the announcement retroactively.
    static func shouldPresentOnLaunch(launchCount: Int) -> Bool {
        if defaults.string(forKey: Constants.lastSeenWhatsNewRelease) == currentRelease {
            return false
        }
        if launchCount <= 1 {
            markSeen()
            return false
        }
        return true
    }

    /// Records that the user has seen the current announcement so it
    /// isn't shown again until `currentRelease` changes.
    static func markSeen() {
        defaults.set(currentRelease, forKey: Constants.lastSeenWhatsNewRelease)
    }
}
