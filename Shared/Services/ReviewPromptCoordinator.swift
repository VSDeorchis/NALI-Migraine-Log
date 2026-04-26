//
//  ReviewPromptCoordinator.swift
//  NALI Migraine Log
//
//  Decides when (and whether) to ask the user "Are you enjoying Headway?"
//  — the gentle pre-prompt that gates Apple's native review sheet.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHY A PRE-PROMPT EXISTS AT ALL
//  ──────────────────────────────────────────────────────────────────────
//  Apple's documented best practice is to call `requestReview()` directly
//  at "appropriate moments" and let the system handle everything else.
//  The system rate-limits prompts to ~3 per 365 days per user, so calling
//  it eagerly is mostly harmless — but it also means a user who is mid-
//  migraine and irritated by an interruption may rate the app one star
//  before Apple ever asks them again.
//
//  For a healthcare app where the median session ends with the user in
//  pain, a "Not really → in-app feedback form" gate is the difference
//  between a 1-star review and an actionable bug report. We accept the
//  small extra friction because users who say "Yes!" still get Apple's
//  unaltered system sheet (we never collect ratings ourselves), and
//  users who say "Not really" get an apology + a way to vent.
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
//      lastEnjoymentPromptDate    Last time we showed the "Enjoying
//                              Headway?" sheet, regardless of outcome.
//      lastReviewRequestDate  Last time we actually called
//                              `requestReview()`. Tracked separately so
//                              we can be more conservative about asking
//                              twice in a year even if Apple wouldn't.
//      lastEnjoymentOutcome   "yes" / "no" / nil — used so we can wait
//                              longer between prompts after a "no".
//
//  ──────────────────────────────────────────────────────────────────────
//  GATING POLICY
//  ──────────────────────────────────────────────────────────────────────
//  `shouldShowEnjoymentPrompt` returns true only when ALL of:
//      • The user has been with us at least `minimumTenureDays` (7).
//      • They have logged at least `minimumEntriesLogged` (5).
//      • At least `cooldownAfterYesDays` (180) has passed since the
//        last "Yes!" — or `cooldownAfterNoDays` (365) since the last
//        "Not really". A user who told us they're unhappy is not the
//        person to interrupt next month.
//      • The most recent prompt is at least `minimumPromptSpacingDays`
//        (120) old, regardless of outcome. Acts as a hard floor.
//
//  ──────────────────────────────────────────────────────────────────────
//  THREADING
//  ──────────────────────────────────────────────────────────────────────
//  Every public surface is `@MainActor`. The coordinator owns no state
//  beyond what it persists to `UserDefaults`, so this is mostly cosmetic
//  — but it lets call sites bind `shouldShowEnjoymentPrompt` directly
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

    /// Hard floor between any two enjoyment prompts.
    private static let minimumPromptSpacingDays: Int = 120

    /// Extra cooldown after a "Yes!" answer. Apple is already going to
    /// rate-limit the actual review sheet, but it's polite not to ask
    /// the same person if they're still enjoying us six weeks later.
    private static let cooldownAfterYesDays: Int = 180

    /// Long cooldown after a "Not really" answer. If someone took the
    /// time to give negative feedback, we owe them at least a year of
    /// quiet before raising it again.
    private static let cooldownAfterNoDays: Int = 365

    // MARK: - UserDefaults keys

    private static let firstLaunchKey            = "review.firstLaunchDate"
    private static let launchCountKey            = "review.launchCount"
    private static let entriesLoggedKey          = "review.entriesLoggedCount"
    private static let lastEnjoymentPromptKey    = "review.lastEnjoymentPromptDate"
    private static let lastReviewRequestKey      = "review.lastReviewRequestDate"
    private static let lastEnjoymentOutcomeKey   = "review.lastEnjoymentOutcome"

    // MARK: - Test seams
    //
    // Both of these are intentionally `internal` (the default visibility)
    // so tests in the same module can swap in a private UserDefaults
    // suite and a controllable clock without touching the public API.
    // App code never references either of these directly — it just calls
    // the `record*` methods and reads `shouldShowEnjoymentPrompt`.

    /// `UserDefaults` instance used for all reads/writes. Production code
    /// always uses `.standard`; tests inject a unique suite-name instance
    /// per test so they never pollute each other or the running app.
    static var defaults: UserDefaults = .standard

    /// "Now" provider, swappable by tests so we can simulate "user
    /// installed the app 200 days ago" without `Thread.sleep`.
    static var now: () -> Date = { Date() }

    /// Wipes every key the coordinator owns from the currently-injected
    /// `defaults` and resets the clock to the system clock. Tests should
    /// call this in `setUp`/`init`, NOT app code. The keys are listed
    /// inline (rather than computed) so a missed key is a compile error
    /// in tests rather than a silent leak.
    static func _resetForTesting() {
        let keys = [
            firstLaunchKey,
            launchCountKey,
            entriesLoggedKey,
            lastEnjoymentPromptKey,
            lastReviewRequestKey,
            lastEnjoymentOutcomeKey,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        now = { Date() }
    }

    /// Stable string values for the outcome key so a future reader of
    /// the defaults file can interpret it without guessing.
    enum Outcome: String {
        case yes
        case no
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

    static var lastEnjoymentPromptDate: Date? {
        defaults.object(forKey: lastEnjoymentPromptKey) as? Date
    }

    static var lastReviewRequestDate: Date? {
        defaults.object(forKey: lastReviewRequestKey) as? Date
    }

    static var lastEnjoymentOutcome: Outcome? {
        guard let raw = defaults.string(forKey: lastEnjoymentOutcomeKey) else {
            return nil
        }
        return Outcome(rawValue: raw)
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

    /// Call when the enjoyment-prompt sheet is presented to the user,
    /// regardless of which button they ultimately tap. Together with
    /// `recordEnjoymentOutcome` this gives us both "have we shown it
    /// recently" and "what did they say last time".
    static func recordEnjoymentPromptShown() {
        defaults.set(now(), forKey: lastEnjoymentPromptKey)
        AppLogger.review.notice("Enjoyment prompt shown; cooldown timer reset.")
    }

    /// Call with the user's actual answer.
    static func recordEnjoymentOutcome(_ outcome: Outcome) {
        defaults.set(outcome.rawValue, forKey: lastEnjoymentOutcomeKey)
        AppLogger.review.notice("Enjoyment prompt outcome: \(outcome.rawValue, privacy: .public).")
    }

    /// Call right before invoking `requestReview()` so we can rate-limit
    /// ourselves more conservatively than Apple does.
    static func recordReviewRequest() {
        defaults.set(now(), forKey: lastReviewRequestKey)
        AppLogger.review.notice("Native review prompt requested.")
    }

    // MARK: - Decision API

    /// Answer to "Should I show the enjoyment prompt right now?".
    /// Read this from a SwiftUI view's `onAppear`/`task` — do NOT poll
    /// it from a timer. The decision is intentionally cheap (a handful
    /// of `UserDefaults` reads + a few date diffs) so it's fine to call
    /// on every navigation.
    static var shouldShowEnjoymentPrompt: Bool {
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

        if let last = lastEnjoymentPromptDate {
            let sincePrompt = daysBetween(last, and: now)

            if sincePrompt < minimumPromptSpacingDays {
                return false
            }

            switch lastEnjoymentOutcome {
            case .yes:
                if sincePrompt < cooldownAfterYesDays { return false }
            case .no:
                if sincePrompt < cooldownAfterNoDays { return false }
            case .none:
                // Prompt shown but outcome never recorded — treat as
                // dismissed and apply the conservative "no" cooldown
                // rather than re-prompt the next session.
                if sincePrompt < cooldownAfterNoDays { return false }
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
