//
//  ReviewPromptCoordinatorTests.swift
//  NALI Migraine LogTests
//
//  Exercises the gating policy in `ReviewPromptCoordinator`:
//
//    • baseline state of every UserDefaults-backed accessor,
//    • idempotency of `recordLaunch()` (first-launch date is sticky),
//    • engagement counter behaviour (`recordEntryLogged()`),
//    • each rejection path of `shouldShowReviewPrompt`
//      (tenure too short, too few entries, cooldown active),
//    • the time-based recovery of the gate after the 180-day cooldown
//      elapses,
//    • the legacy-key fallback that carries the cooldown over for
//      users upgrading from the old custom-pre-prompt build.
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
        #expect(ReviewPromptCoordinator.lastReviewRequestDate == nil)
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == false)
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

    // MARK: - shouldShowReviewPrompt — rejection paths

    @Test("Gate closed: launch recorded but tenure < 7 days")
    func gateClosed_TenureTooShort() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<10 { ReviewPromptCoordinator.recordEntryLogged() }

        // Six days later — still below the 7-day floor.
        freezeClock(at: date(daysFrom: day0, by: 6))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == false)
    }

    @Test("Gate closed: tenure OK but fewer than 5 entries logged")
    func gateClosed_NotEnoughEntries() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<4 { ReviewPromptCoordinator.recordEntryLogged() }

        freezeClock(at: date(daysFrom: day0, by: 30))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == false)
    }

    // MARK: - shouldShowReviewPrompt — happy path

    @Test("Gate open: tenure ≥ 7 days, ≥ 5 entries, no prior prompt")
    func gateOpen_FreshUser() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        freezeClock(at: date(daysFrom: day0, by: 8))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == true)
    }

    // MARK: - shouldShowReviewPrompt — cooldown

    @Test("Gate closed: prompt fired + 179 days < 180-day cooldown")
    func gateClosed_WithinCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        // First prompt fires at day 8.
        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordReviewRequest()

        // 179 days later — still inside the 180-day cooldown.
        freezeClock(at: date(daysFrom: promptDay, by: 179))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == false)
    }

    @Test("Gate open: prompt fired + 181 days clears the 180-day cooldown")
    func gateOpen_BeyondCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let promptDay = date(daysFrom: day0, by: 8)
        freezeClock(at: promptDay)
        ReviewPromptCoordinator.recordReviewRequest()

        freezeClock(at: date(daysFrom: promptDay, by: 181))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == true)
    }

    // MARK: - Legacy-key upgrade fallback
    //
    // Users upgrading from the previous custom-pre-prompt build have a
    // `review.lastEnjoymentPromptDate` key in UserDefaults but no
    // `review.lastReviewRequestDate`. The cooldown must still honor
    // that legacy stamp so the new build doesn't immediately re-prompt
    // someone who saw the old "Enjoying Headway?" alert last week.

    @Test("Gate closed: only the legacy lastEnjoymentPromptDate is set, within cooldown")
    func gateClosed_LegacyKeyOnly_WithinCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        // Simulate an upgrade: legacy key was written 30 days ago, new
        // key never has been.
        let legacyPromptDay = date(daysFrom: day0, by: 8)
        testDefaults.set(legacyPromptDay, forKey: "review.lastEnjoymentPromptDate")

        // 30 days later — still inside the 180-day cooldown via the
        // legacy fallback.
        freezeClock(at: date(daysFrom: legacyPromptDay, by: 30))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == false)
    }

    @Test("Gate open: legacy lastEnjoymentPromptDate is older than the 180-day cooldown")
    func gateOpen_LegacyKeyOnly_BeyondCooldown() {
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: day0)
        ReviewPromptCoordinator.recordLaunch()
        for _ in 0..<5 { ReviewPromptCoordinator.recordEntryLogged() }

        let legacyPromptDay = date(daysFrom: day0, by: 8)
        testDefaults.set(legacyPromptDay, forKey: "review.lastEnjoymentPromptDate")

        freezeClock(at: date(daysFrom: legacyPromptDay, by: 181))
        #expect(ReviewPromptCoordinator.shouldShowReviewPrompt == true)
    }

    // MARK: - recordReviewRequest()

    @Test("recordReviewRequest() stamps lastReviewRequestDate")
    func recordReviewRequestStamps() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        freezeClock(at: now)
        #expect(ReviewPromptCoordinator.lastReviewRequestDate == nil)
        ReviewPromptCoordinator.recordReviewRequest()
        #expect(ReviewPromptCoordinator.lastReviewRequestDate != nil)
    }
}
