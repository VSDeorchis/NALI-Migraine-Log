//
//  EnjoymentPromptView.swift
//  NALI Migraine Log
//
//  The two-button "Enjoying Headway?" pre-prompt that gates the App
//  Store review sheet — and, on the negative branch, opens the in-app
//  feedback form instead.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHY A VIEW MODIFIER AND NOT A STANDALONE VIEW
//  ──────────────────────────────────────────────────────────────────────
//  The native review prompt is invoked via SwiftUI's
//  `@Environment(\.requestReview)` action, which is only valid inside a
//  `View`. The cleanest packaging is therefore a `ViewModifier` you
//  attach to whatever container view should be the prompt's host (we
//  use `MigraineLogView`). Hosts only have to manage a `Bool` binding
//  for "should this show right now"; everything else — the alert, the
//  outcome recording, the chained feedback sheet — lives here.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHAT EACH BUTTON DOES
//  ──────────────────────────────────────────────────────────────────────
//      "Yes!"          → records the outcome, asks the system review
//                        prompt to appear (Apple still rate-limits,
//                        so it may not actually show), and dismisses.
//      "Not really"    → records the outcome and presents the in-app
//                        feedback form (`FeedbackFormView`).
//      Swipe-down /
//      Cancel button   → treated as a soft "no" by the coordinator
//                        (see `ReviewPromptCoordinator.swift` —
//                        a no-outcome prompt applies the conservative
//                        cooldown so we don't pester).
//

// The whole file is iOS-only: SwiftUI's `requestReview` action and the
// in-app `FeedbackFormView` (which depends on UIKit + MessageUI) are
// both iOS-bound. The shared `Views/` folder is a synchronized root
// across all three app targets, so the file is *visible* to the watch
// and macOS targets too — guarding the body with `#if os(iOS)` makes
// it compile to an empty translation unit there instead of hard-failing
// on the missing imports. This is the same pattern other shared views
// use when they need iOS-only modifiers.
#if os(iOS)

import SwiftUI
import StoreKit

// MARK: - Modifier

/// Attaches the "Enjoying Headway?" alert (and its feedback-form sheet)
/// to the host view. The host owns a `Bool` binding it flips on when
/// `ReviewPromptCoordinator.shouldShowEnjoymentPrompt` is true.
private struct EnjoymentPromptModifier: ViewModifier {

    @Binding var isPresented: Bool

    @State private var showFeedbackForm: Bool = false

    /// Native review-request action. Available on iOS 16+ / iPadOS 16+
    /// and resolves to a no-op on platforms that don't have a review
    /// pipeline. Apple rate-limits the actual prompt to ~3 per 365
    /// days per user; calling it inside our gate is purely additive.
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
            // Hand-off A: the actual pre-prompt. Apple HIG: keep copy
            // short, concrete, and avoid emojis or marketing voice.
            .alert("Enjoying Headway?", isPresented: $isPresented) {
                Button("Not really", role: .destructive) {
                    handleNotReally()
                }
                Button("Yes!") {
                    handleYes()
                }
            } message: {
                Text("If Headway has been useful, we'd love a quick rating on the App Store. If not, tap \"Not really\" and tell us what's not working.")
            }
            // Hand-off B: the feedback form sheet. Modeled as a
            // separate state because SwiftUI cannot present an alert
            // and a sheet from the same trigger in the same frame —
            // we set the bool inside the alert action and SwiftUI
            // routes it to the next runloop tick.
            .sheet(isPresented: $showFeedbackForm) {
                FeedbackFormView(origin: .enjoymentPromptNegative)
            }
    }

    // MARK: - Outcome handlers

    private func handleYes() {
        AppLogger.review.notice("Enjoyment prompt: user tapped Yes.")
        ReviewPromptCoordinator.recordEnjoymentOutcome(.yes)
        ReviewPromptCoordinator.recordReviewRequest()

        // SwiftUI's requestReview action is synchronous-call /
        // asynchronous-effect: by the time we return, the system has
        // queued the prompt (or decided to suppress it because it's
        // already shown three this year). Either way our work is done.
        requestReview()
    }

    private func handleNotReally() {
        AppLogger.review.notice("Enjoyment prompt: user tapped Not really.")
        ReviewPromptCoordinator.recordEnjoymentOutcome(.no)
        // Defer the sheet to the next runloop so SwiftUI has a chance
        // to fully tear down the alert before presenting it. Without
        // this, on some iOS minor versions the sheet refuses to come
        // up and you end up with a dead-end UI.
        DispatchQueue.main.async {
            showFeedbackForm = true
        }
    }
}

// MARK: - Public API

extension View {
    /// Attach the "Enjoying Headway?" pre-prompt to this view. The
    /// caller is responsible for *deciding* when to set the binding
    /// to `true` (typically by consulting
    /// `ReviewPromptCoordinator.shouldShowEnjoymentPrompt` and calling
    /// `ReviewPromptCoordinator.recordEnjoymentPromptShown()` to start
    /// the cooldown clock).
    ///
    /// Use it once per host scene; attaching it to multiple views in
    /// the same scene will produce overlapping alerts.
    func enjoymentPrompt(isPresented: Binding<Bool>) -> some View {
        self.modifier(EnjoymentPromptModifier(isPresented: isPresented))
    }
}

#endif
