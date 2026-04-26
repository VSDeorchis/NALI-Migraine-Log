//
//  ReviewPromptCoordinatorTests.swift
//  NALI Migraine LogTests
//
//  Exercises the gating policy in `ReviewPromptCoordinator`:
//
//    • baseline state of every UserDefaults-backed accessor,
//    • idempotency of `recordLaunch()` (first-launch date is sticky),
//    • engagement counter behaviour (`recordEntryLogged()`),
//    • enjoyment-prompt outcome round-trips,
//    • each rejection path of `shouldShowEnjoymentPrompt`
//      (tenure too short, too few entries, cooldown active, etc.),
//    • the time-based recovery of the gate for both "yes" and "no"
//      outcomes after their respective cooldowns elapse,
//    • the conservative "no-outcome" branch (a prompt that was shown
//      but never answered should apply the long cooldown).
//
//  The coordinator is `enum`-only static state backed by UserDefaults
//  and a clock closure. Both seams are mutated per-test, so the suite
//  is `.serialized` to keep the static globals deterministic — running
//  these in parallel would be racey by construction.
//

import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("ReviewPromptCoordinator", .serialized)
@MainActor
struct ReviewPromptCoordinatorTests {

    // MARK: - Per-test fixture
    //
    // `init` runs before every `@Test` method (Swift Testing's standard
    // contract — no shared mutable state between tests), so this is the
    // equivalent of XCTest's `setUp`.

    private let suiteName: String
    private let testDefaults: UserDefaults

    init() {
        // A fresh suite per test means we don't have to call
        // `removePersistentDomain` and risk yanking another test's
        // state when Swift Testing reuses the runner.
        suiteName = "ReviewPromptCoordinatorTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!

        ReviewPromptCoordinator.defaults = testDefaults
        ReviewPromptCoordinator._resetForTesting()
    }

    // Note: there is no `deinit` cleanup — Swift Testing creates a new
    // suite instance per test, and we restore `defaults` to `.standard`
    // implicitly by calling `_resetForTesting()` in `init` of the next
    // test. The tiny disk leak from anonymous suite-name plists is
    // bounded (one per test run, max a few hundred bytes each) and
    // ephemeral — `removePersistentDomain` on every teardown was the
    // first design and turned out to fight Swift Testing's lifecycle.

    // MARK: - Helpers

    /// Pin the coordinator's clock to a fixed instant.
    private func freezeClock(at date: Date) {
        ReviewPromptCoordinator.now = { date }
    }

    /// Calendar-aware "N days from `from`" so the cooldown checks line
    /// up exactly with the production `daysBetween` calculation (which
    /// uses `Calendar.current.startOfDay`).
    private func date(daysFrom date: Date, by days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date)!
    }

    // MARK: - Baseline

    @Test("Default state: all accessors return zero/nil and the gate is closed")
    func defaultState() {
        #expect(ReviewPromptCoordinator.firstLaunchDate == nil)
        #expect(ReviewPromptCoordinator.launchCount == 0)
        #expect(ReviewPromptCoordinator.entriesLoggedCount == 0)
        #expect(ReviewPromptCoordinator.lastEnjoymentPromptDate == nil)
        #expect(ReviewPromptCoordinator.lastReviewRequestDate == nil)
        #expect(ReviewPromptCoordinator.lastEnjoymentOutcome == nil)
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == false)
    }

    // MARK: - recordLaunch()

    @Test("recordLaunch() stamps firstLaunchDate exactly once")
    func recordLaunchFirstLaunchDateIsSticky() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()

        let stamped = ReviewPromptCoordinator.firstLaunchDate
        #expect(stamped != nil)

        // Advance the clock and call again — the stamped date must NOT
        // move, otherwise tenure resets every launch and the prompt
        // can never fire.
        freezeClock(at: date(daysFrom: day0, by: 30))
        ReviewPromptCoordinator.recordLaunch()
        #expect(ReviewPromptCoordinator.firstLaunchDate == stamped)
    }

    @Test("recordLaunch() bumps the launch counter on every call")
    func recordLaunchIncrementsCounter() {
        ReviewPromptCoordinator.recordLaunch()
        ReviewPromptCoordinator.recordLaunch()
        ReviewPromptCoordinator.recordLaunch()
        #expect(ReviewPromptCoordinator.launchCount == 3)
    }

    // MARK: - recordEntryLogged()

    @Test("recordEntryLogged() monotonically increments")
    func entriesLoggedCounterIncrements() {
        for expected in 1...7 {
            ReviewPromptCoordinator.recordEntryLogged()
            #expect(ReviewPromptCoordinator.entriesLoggedCount == expected)
        }
    }

    // MARK: - recordEnjoymentOutcome()

    @Test("Enjoyment outcome round-trips through the accessor")
    func enjoymentOutcomeRoundTrip() {
        ReviewPromptCoordinator.recordEnjoymentOutcome(.yes)
        #expect(ReviewPromptCoordinator.lastEnjoymentOutcome == .yes)

        ReviewPromptCoordinator.recordEnjoymentOutcome(.no)
        #expect(ReviewPromptCoordinator.lastEnjoymentOutcome == .no)
    }

    // MARK: - shouldShowEnjoymentPrompt — rejection paths

    @Test("Gate closed: launch recorded but tenure < 7 days")
    func gateClosed_TenureTooShort() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<10 { ReviewPromptCoordinator.recordEntryLogged() }

        // Six days later — still below the 7-day floor.
        freezeClock(at: date(daysFrom: day0, by: 6))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == false)
    }

    @Test("Gate closed: tenure OK but fewer than 5 entries logged")
    func gateClosed_NotEnoughEntries() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<4 { ReviewPromptCoordinator.recordEntryLogged() }

        freezeClock(at: date(daysFrom: day0, by: 30))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == false)
    }

    // MARK: - shouldShowEnjoymentPrompt — happy path

    @Test("Gate open: tenure ≥ 7 days, ≥ 5 entries, no prior prompt")
    func gateOpen_FreshUser() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        freezeClock(at: date(daysFrom: day0, by: 8))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == true)
    }

    // MARK: - shouldShowEnjoymentPrompt — cooldown after "yes"

    @Test("Gate closed: 'yes' answer + 179 days < 180-day cooldown")
    func gateClosed_AfterYes_WithinCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        // First prompt fires at day 8.
        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordEnjoymentPromptShown()
        ReviewPromptCoordinator.recordEnjoymentOutcome(.yes)

        // 179 days later — still inside the 180-day cooldown.
        freezeClock(at: date(daysFrom: promptDay, by: 179))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == false)
    }

    @Test("Gate open: 'yes' answer + 181 days clears the 180-day cooldown")
    func gateOpen_AfterYes_BeyondCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordEnjoymentPromptShown()
        ReviewPromptCoordinator.recordEnjoymentOutcome(.yes)

        freezeClock(at: date(daysFrom: promptDay, by: 181))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == true)
    }

    // MARK: - shouldShowEnjoymentPrompt — cooldown after "no"

    @Test("Gate closed: 'no' answer + 364 days < 365-day cooldown")
    func gateClosed_AfterNo_WithinCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordEnjoymentPromptShown()
        ReviewPromptCoordinator.recordEnjoymentOutcome(.no)

        freezeClock(at: date(daysFrom: promptDay, by: 364))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == false)
    }

    @Test("Gate open: 'no' answer + 366 days clears the 365-day cooldown")
    func gateOpen_AfterNo_BeyondCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordEnjoymentPromptShown()
        ReviewPromptCoordinator.recordEnjoymentOutcome(.no)

        freezeClock(at: date(daysFrom: promptDay, by: 366))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == true)
    }

    // MARK: - Dismiss-without-answer path

    @Test("Gate closed: prompt shown but no outcome, treated as conservative 'no'")
    func gateClosed_PromptShownNoOutcome_AppliesLongCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordEnjoymentPromptShown()
        // Deliberately do NOT record an outcome — simulates a swipe-down
        // dismiss of the alert.

        // 200 days later — past the 120-day floor and the 180-day "yes"
        // cooldown, but BELOW the 365-day "no" cooldown that the
        // no-outcome path is supposed to apply.
        freezeClock(at: date(daysFrom: promptDay, by: 200))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == false)
    }

    @Test("Gate open: prompt shown without outcome, then 366 days elapse")
    func gateOpen_PromptShownNoOutcome_AfterLongCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordEnjoymentPromptShown()

        freezeClock(at: date(daysFrom: promptDay, by: 366))
        #expect(ReviewPromptCoordinator.shouldShowEnjoymentPrompt == true)
    }

    // MARK: - recordReviewRequest()

    @Test("recordReviewRequest() stamps the timestamp")
    func recordReviewRequestStamps() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: now)
        #expect(ReviewPromptCoordinator.lastReviewRequestDate == nil)
        ReviewPromptCoordinator.recordReviewRequest()
        #expect(ReviewPromptCoordinator.lastReviewRequestDate != nil)
    }
}
