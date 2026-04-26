//
//  AppContactInfo.swift
//  NALI Migraine Log
//
//  Single source of truth for the addresses we use to contact the user
//  out (rate-the-app deep link) or that the user uses to contact us
//  (feedback email, support phone). Kept at the `Shared/` root because
//  the iOS UI, the macOS UI, and any future Watch entry point all need
//  to reach the same canonical values — duplicating these strings is
//  exactly how a "support@…" address quietly drifts to "info@…" in one
//  target and never gets noticed until a user complains.
//
//  TO CHANGE A VALUE IN SHIPPING UPDATES
//  -------------------------------------
//  Just edit the constant. All call sites pull from here at compile
//  time, so no settings-side toggle is needed.
//

import Foundation

enum AppContactInfo {

    // MARK: - App Store

    /// Numeric App Store identifier for "Headway: Migraine Monitor".
    /// Lifted from the canonical product URL:
    ///
    ///   https://apps.apple.com/app/headway-migraine-monitor/id6741347993
    ///
    /// Used to build deep links into the App Store's review and product
    /// pages. If the app is ever re-released under a new bundle and gets
    /// a new App Store ID, this is the only place that needs updating.
    static let appStoreID = "6741347993"

    /// Deep link that opens the App Store's "Write a Review" sheet for
    /// this app. Apple's documented format. Use this for the always-on
    /// "Rate Headway on the App Store" button in Settings — distinct
    /// from `SKStoreReviewController.requestReview()` / SwiftUI's
    /// `requestReview` action, which shows the in-app sheet but is
    /// rate-limited by the system to ~3 prompts per 365 days per user.
    static var appStoreWriteReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    /// Plain product page on the App Store. Useful for "Share Headway
    /// with a friend" links and any other surface that wants the app's
    /// listing rather than the review prompt.
    static var appStoreProductURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    }

    // MARK: - Feedback

    /// Destination email for in-app feedback submissions. The feedback
    /// form (`FeedbackFormView`) builds a structured message body
    /// (category, optional star rating, free text, app/OS/device
    /// metadata) and pre-fills the system mail composer addressed here.
    ///
    /// This is intentionally a role address on a domain administered
    /// by the developer (cicgconsulting.com), NOT a personal mailbox.
    /// The alias forwards to whoever currently triages app feedback,
    /// so that person can change without an app update — Apple does
    /// not provide any developer-facing "Hide My Email" alias for
    /// inbound mail, so a server-side role address is the standard
    /// way to keep individual mailboxes out of public app metadata.
    ///
    /// If you want feedback to land somewhere else (a shared inbox,
    /// a ticketing system address, etc.), change this single string —
    /// the rest of the flow doesn't care.
    static let feedbackEmailAddress = "support@cicgconsulting.com"

    /// Subject line used by `FeedbackFormView` so support can grep
    /// inboxes by app name. Build number is appended at send time.
    static let feedbackEmailSubjectPrefix = "Headway Feedback"

    // MARK: - Support

    /// Existing practice phone number, mirrored from the macOS
    /// "Contact Support" command and the iOS About screen so all three
    /// platforms quote the same digits. Stored in raw `tel:`-friendly
    /// form (digits only) — UI surfaces should format with spaces or
    /// punctuation as appropriate for display.
    static let supportPhoneRaw = "5164664700"

    /// Pretty-printed version of `supportPhoneRaw` for display in UI.
    static let supportPhoneDisplay = "(516) 466-4700"

    /// Practice website. Same value as the existing About screen and
    /// macOS Help menu link.
    static let websiteURL = URL(string: "https://www.neuroli.com")!
}
