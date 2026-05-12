//
//  ReviewPromptCoordinator.swift
//  NALI Migraine Log
//
//  Decides when (and whether) to call Apple's native review prompt
//  (`SKStoreReviewController.requestReview()`) so we don't pester
//  users who only just installed the app.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHAT THIS COORDINATOR DOES — AND WHAT IT DELIBERATELY DOES NOT
//  ──────────────────────────────────────────────────────────────────────
//  Apple's `requestReview()` is already rate-limited (~3 prompts per
//  365 days per user) and renders the same standard sheet across every
//  app on iOS:
//
//      Enjoying <App Name>?
//      Tap a star to rate it on the App Store.
//      [☆ ☆ ☆ ☆ ☆]
//      Not Now
//
//  We do NOT show a custom "Enjoying Headway?" pre-prompt of our own —
//  users expect the system sheet, and adding our own alert in front of
//  it just adds friction. Users who actively want to send feedback can
//  do so unconditionally from Settings → "Send Feedback".
//
//  What this coordinator *does* add on top of `requestReview()` is a
//  gate that prevents us from even calling it on freshly-installed
//  apps. Apple's own HIG says to wait until the user has demonstrated
//  meaningful engagement, and the system rate-limiter only kicks in
//  AFTER we've called it — so an eager first call on a brand-new
//  install will count toward the user's annual quota even if they
//  immediately dismiss it.
//
//  ──────────────────────────────────────────────────────────────────────
//  SIGNALS WE TRACK (all in UserDefaults; nothing leaves the device)
//  ──────────────────────────────────────────────────────────────────────
//      firstLaunchDate        Date set the very first time `recordLaunch`
//                              runs. Used to enforce a minimum tenure
//                              before we ever ask for anything.
//      launchCount            Monotonic counter, incremented per process
//                              launch. Used as a soft-engagement signal.
//      entriesLoggedCount     Number of migraines saved while the
//                              coordinator was alive. Persisted across
//                              launches.
//      lastReviewRequestDate  Last time we actually called
//                              `requestReview()`. Drives our own
//                              cooldown on top of Apple's.
//
//  ──────────────────────────────────────────────────────────────────────
//  GATING POLICY
//  ──────────────────────────────────────────────────────────────────────
//  `shouldShowReviewPrompt` returns true only when ALL of:
//      • The user has been with us at least `minimumTenureDays` (7).
//      • They have logged at least `minimumEntriesLogged` (5).
//      • At least `cooldownDays` (180) has passed since the last time
//        we called `requestReview()`. Apple itself rate-limits to ~3
//        per 365 days regardless, but our half-yearly floor keeps us
//        comfortably under that ceiling.
//
//  ──────────────────────────────────────────────────────────────────────
//  THREADING
//  ──────────────────────────────────────────────────────────────────────
//  Every public surface is `@MainActor`. The coordinator owns no state
//  beyond what it persists to `UserDefaults`, so this is mostly cosmetic
//  — but it lets call sites bind `shouldShowReviewPrompt` directly
//  to SwiftUI state without ceremony.
//

import Foundation

@MainActor
enum ReviewPromptCoordinator {

    // MARK: - Tunable surface
    //
    // Constants are intentionally generous on the side of "don't bother
    // the user". If real-world telemetry shows we're under-asking, these
    // are the only knobs that need adjusting.

    /// Days the user has to have had the app installed before we
    /// consider asking for any feedback.
    private static let minimumTenureDays: Int = 7

    /// Migraines the user has to have logged. We log a meaningful event
    /// only when someone actually interacts with the core feature, so
    /// this filters out installs that never moved past the disclaimer.
    private static let minimumEntriesLogged: Int = 5

    /// Hard floor between any two `requestReview()` calls. Apple's own
    /// rate limiter is ~3 prompts per 365 days; a 180-day floor keeps
    /// us comfortably below that ceiling and matches the cadence we
    /// previously applied to "user said Yes!" answers under the old
    /// custom pre-prompt.
    private static let cooldownDays: Int = 180

    // MARK: - UserDefaults keys

    private static let firstLaunchKey         = "review.firstLaunchDate"
    private static let launchCountKey         = "review.launchCount"
    private static let entriesLoggedKey       = "review.entriesLoggedCount"
    private static let lastReviewRequestKey   = "review.lastReviewRequestDate"

    // Legacy keys from the previous custom-pre-prompt design. We no
    // longer write to them, but we DO read `lastEnjoymentPromptKey` as
    // a fallback when computing `lastReviewRequestDate` so existing
    // users don't get re-prompted on the first launch after upgrade.
    private static let legacyLastEnjoymentPromptKey  = "review.lastEnjoymentPromptDate"
    private static let legacyLastEnjoymentOutcomeKey = "review.lastEnjoymentOutcome"

    // MARK: - Test seams
    //
    // Both of these are intentionally `internal` (the default visibility)
    // so tests in the same module can swap in a private UserDefaults
    // suite and a controllable clock without touching the public API.
    // App code never references either of these directly — it just calls
    // the `record*` methods and reads `shouldShowReviewPrompt`.

    /// `UserDefaults` instance used for all reads/writes. Production code
    /// always uses `.standard`; tests inject a unique suite-name instance
    /// per test so they never pollute each other or the running app.
    static var defaults: UserDefaults = .standard

    /// "Now" provider, swappable by tests so we can simulate "user
    /// installed the app 200 days ago" without `Thread.sleep`.
    static var now: () -> Date = { Date() }

    /// Wipes every key the coordinator owns from the currently-injected
    /// `defaults` and resets the clock to the system clock. Tests should
    /// call this in `setUp`/`init`, NOT app code. Legacy keys are
    /// included so we can write tests for the upgrade-fallback path
    /// without leaking state across test runs.
    static func _resetForTesting() {
        let keys = [
            firstLaunchKey,
            launchCountKey,
            entriesLoggedKey,
            lastReviewRequestKey,
            legacyLastEnjoymentPromptKey,
            legacyLastEnjoymentOutcomeKey,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        now = { Date() }
    }

    // MARK: - Public diagnostic accessors
    //
    // Useful from a Settings → Diagnostics row or from unit tests.
    // Read-only on purpose — mutation goes through the `record*`
    // entry points so the policy is enforced in one place.

    static var firstLaunchDate: Date? {
        defaults.object(forKey: firstLaunchKey) as? Date
    }

    static var launchCount: Int {
        defaults.integer(forKey: launchCountKey)
    }

    static var entriesLoggedCount: Int {
        defaults.integer(forKey: entriesLoggedKey)
    }

    /// Most recent moment we asked for a review. Falls back to the old
    /// `lastEnjoymentPromptDate` key on upgrade so the cooldown carries
    /// over for users who already saw a prompt under the previous
    /// custom pre-prompt design. If both keys exist (i.e. the user has
    /// also been prompted since upgrade), the more recent value wins.
    static var lastReviewRequestDate: Date? {
        let new = defaults.object(forKey: lastReviewRequestKey) as? Date
        let legacy = defaults.object(forKey: legacyLastEnjoymentPromptKey) as? Date
        switch (new, legacy) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    // MARK: - Lifecycle hooks (call from app code)

    /// Call once per `@main` `App.init()`. Stamps the first-launch date
    /// if absent and bumps the launch counter. Cheap; safe to call on
    /// every launch.
    static func recordLaunch() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(now(), forKey: firstLaunchKey)
            AppLogger.review.notice("Recorded first launch for review-prompt tracking.")
        }

        let next = defaults.integer(forKey: launchCountKey) + 1
        defaults.set(next, forKey: launchCountKey)
        AppLogger.review.debug("Launch count is now \(next, privacy: .public).")
    }

    /// Call after every successful migraine save. Increments the
    /// engagement counter that gates the prompt.
    static func recordEntryLogged() {
        let next = defaults.integer(forKey: entriesLoggedKey) + 1
        defaults.set(next, forKey: entriesLoggedKey)
        AppLogger.review.debug("Entries-logged counter is now \(next, privacy: .public).")
    }

    /// Call right before invoking `requestReview()` so we can rate-limit
    /// ourselves more conservatively than Apple does.
    static func recordReviewRequest() {
        defaults.set(now(), forKey: lastReviewRequestKey)
        AppLogger.review.notice("Native review prompt requested.")
    }

    // MARK: - Decision API

    /// Answer to "Should I call `requestReview()` right now?". Read
    /// this from a SwiftUI view's `onAppear`/`task` — do NOT poll it
    /// from a timer. The decision is intentionally cheap (a handful
    /// of `UserDefaults` reads + a few date diffs) so it's fine to
    /// call on every navigation.
    static var shouldShowReviewPrompt: Bool {
        let now = self.now()

        guard let first = firstLaunchDate else {
            // We've never recorded a launch — caller is asking before
            // `recordLaunch()` ran. Don't prompt; the next launch will
            // record it and we'll re-evaluate then.
            return false
        }

        let tenureDays = daysBetween(first, and: now)
        guard tenureDays >= minimumTenureDays else {
            return false
        }

        guard entriesLoggedCount >= minimumEntriesLogged else {
            return false
        }

        if let last = lastReviewRequestDate {
            let sinceLast = daysBetween(last, and: now)
            guard sinceLast >= cooldownDays else {
                return false
            }
        }

        return true
    }

    // MARK: - Private helpers

    /// Calendar-aware day delta. Avoids the "subtract `TimeInterval`s
    /// and divide by 86400" approximation, which silently misbehaves
    /// across DST transitions.
    private static func daysBetween(_ a: Date, and b: Date) -> Int {
        let calendar = Calendar.current
        let dayA = calendar.startOfDay(for: a)
        let dayB = calendar.startOfDay(for: b)
        return calendar.dateComponents([.day], from: dayA, to: dayB).day ?? 0
    }
}
