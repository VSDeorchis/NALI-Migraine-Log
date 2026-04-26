//
//  FeedbackFormView.swift
//  NALI Migraine Log
//
//  In-app feedback form. Used in two places:
//
//    1. As the "Not really" follow-up to the enjoyment pre-prompt
//       (`EnjoymentPromptView`) — i.e. the user has already told us
//       they aren't loving the app and we want to capture *why* before
//       we ever think about asking again.
//
//    2. As the always-available "Send Feedback" entry point in
//       Settings → Help & Feedback, for users who want to reach out
//       unprompted (bug report, feature request, "you forgot a med
//       in the dropdown", etc.).
//
//  ──────────────────────────────────────────────────────────────────────
//  WHY AN IN-APP FORM AND NOT JUST A `mailto:` LINK
//  ──────────────────────────────────────────────────────────────────────
//  Two reasons:
//
//    • The user picks a category and rating in a structured way, so
//      support can triage 100 messages by skimming subject lines
//      instead of opening every body.
//
//    • App / OS / device metadata is auto-attached (with explicit user
//      consent via a toggle) so we don't have to play "what version
//      are you on?" tennis to reproduce a bug.
//
//  Both of those are lost the instant we hand the user off to a blank
//  Mail composer with just our address pre-filled.
//
//  ──────────────────────────────────────────────────────────────────────
//  HOW THE MESSAGE ACTUALLY LEAVES THE DEVICE
//  ──────────────────────────────────────────────────────────────────────
//  1. Submit assembles a structured body and tries `MFMailComposeView-
//     Controller.canSendMail()`. If true, present the system mail
//     composer pre-filled — the user reviews and taps Send themselves,
//     so the app never silently transmits anything.
//
//  2. If Mail is not configured (third-party mail-only users, or
//     simulators in CI), fall back to copying the formatted body to
//     the system pasteboard and showing a confirmation that explains
//     where it went and how to send it manually.
//
//  Either path keeps the user in control of the actual transmission,
//  which matches the "all data stays on device unless you choose to
//  share it" stance documented in About / the privacy banner.
//

// The whole file is iOS-only: it depends on UIKit + MessageUI, neither
// of which are available on watchOS or macOS. The shared `Views/`
// folder is a synchronized root across all three app targets, so the
// file is *visible* to the watch and macOS targets too — guarding the
// body with `#if os(iOS)` makes it compile to an empty translation
// unit there instead of hard-failing on the missing imports.
#if os(iOS)

import SwiftUI
import UIKit
import MessageUI

// MARK: - View

struct FeedbackFormView: View {

    /// Where the form was launched from. Affects copy ("you tapped
    /// Not really…" vs "Send us feedback") and whether dismissing
    /// records an enjoyment-prompt outcome on the way out.
    enum Origin {
        case enjoymentPromptNegative
        case settings
    }

    let origin: Origin

    // MARK: - State

    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackCategory = .general
    @State private var rating: Int = 0  // 0 = no selection
    @State private var bodyText: String = ""
    @State private var includeDiagnostics: Bool = true

    @State private var showingMailComposer = false
    @State private var mailResult: Result<MFMailComposeResult, Error>?

    @State private var showingMailUnavailableAlert = false
    @State private var showingClipboardConfirmation = false

    // MARK: - Computed

    /// Trimmed body length is the only validation gate. We don't insist
    /// on a category picker since "General" is the default, and we don't
    /// require a rating — sometimes people just want to vent.
    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubmitEnabled: Bool {
        trimmedBody.count >= 10
    }

    private var headerText: String {
        switch origin {
        case .enjoymentPromptNegative:
            return "Sorry to hear that."
        case .settings:
            return "We read every message."
        }
    }

    private var subheadText: String {
        switch origin {
        case .enjoymentPromptNegative:
            return "Tell us what's not working — bug, missing feature, anything. The more specific you can be, the more likely we can fix it."
        case .settings:
            return "Bugs, feature requests, gripes, kind words — all welcome. Replies come from the practice's team, not an autoresponder."
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Intro section: short prose so the user understands
                // where this is going and that it's not a survey form
                // they've been hijacked into.
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headerText)
                            .font(.headline)
                        Text(subheadText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("What kind of feedback?") {
                    Picker("Category", selection: $category) {
                        ForEach(FeedbackCategory.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("Categorizes your feedback so it gets to the right person.")
                }

                Section {
                    StarRatingPicker(rating: $rating)
                        .padding(.vertical, 4)
                } header: {
                    Text("How would you rate the app right now? (optional)")
                } footer: {
                    if rating > 0 {
                        Text("Tap a star again to clear.")
                            .font(.caption)
                    }
                }

                Section {
                    // `axis: .vertical` plus `lineLimit(5...20)` gives us
                    // a self-growing multi-line field with a sane min and
                    // max. Avoids needing to drop down to UITextView.
                    TextField(
                        "What's on your mind?",
                        text: $bodyText,
                        axis: .vertical
                    )
                    .lineLimit(5...20)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Feedback message")
                    .accessibilityHint("Required. At least 10 characters.")
                } header: {
                    Text("Your feedback")
                } footer: {
                    let remaining = max(0, 10 - trimmedBody.count)
                    if remaining > 0 {
                        Text("\(remaining) more character\(remaining == 1 ? "" : "s") needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Include device & app info", isOn: $includeDiagnostics)
                        .accessibilityHint("Attaches your app version, iOS version, and device model so we can reproduce bugs.")

                    if includeDiagnostics {
                        DisclosureGroup("What gets included?") {
                            DiagnosticsPreview()
                        }
                        .font(.subheadline)
                    }
                } footer: {
                    Text("We don't include any of your migraine data, location, or notes.")
                        .font(.caption)
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        submit()
                    }
                    .disabled(!isSubmitEnabled)
                    .accessibilityHint(
                        isSubmitEnabled
                        ? "Opens the Mail composer with your feedback pre-filled."
                        : "Add at least 10 characters first."
                    )
                }
            }
        }
        .sheet(isPresented: $showingMailComposer, onDismiss: handleMailComposerDismissed) {
            MailComposer(
                recipient: AppContactInfo.feedbackEmailAddress,
                subject: emailSubject(),
                body: emailBody(),
                result: $mailResult
            )
        }
        .alert("Mail isn't set up on this device", isPresented: $showingMailUnavailableAlert) {
            Button("Copy to Clipboard") {
                copyToClipboardAndConfirm()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("We can copy your message to the clipboard so you can paste it into your preferred email or messaging app and send it to \(AppContactInfo.feedbackEmailAddress).")
        }
        .alert("Copied to clipboard", isPresented: $showingClipboardConfirmation) {
            Button("Done") {
                finalizeAndDismiss()
            }
        } message: {
            Text("Your feedback is on the clipboard. Paste it into any email or messaging app and send it to \(AppContactInfo.feedbackEmailAddress).")
        }
    }

    // MARK: - Actions

    private func cancel() {
        AppLogger.review.notice("Feedback form cancelled (origin=\(String(describing: origin), privacy: .public)).")
        // If we got here from the negative path of the enjoyment
        // prompt, recordEnjoymentOutcome(.no) has already fired by the
        // time this sheet was presented. Nothing else to do.
        dismiss()
    }

    private func submit() {
        AppLogger.review.notice("Feedback form submit tapped; category=\(category.rawValue, privacy: .public), rating=\(rating, privacy: .public), includeDiagnostics=\(includeDiagnostics, privacy: .public).")

        if MFMailComposeViewController.canSendMail() {
            showingMailComposer = true
        } else {
            AppLogger.review.notice("MFMailComposeViewController.canSendMail() returned false; offering clipboard fallback.")
            showingMailUnavailableAlert = true
        }
    }

    private func handleMailComposerDismissed() {
        switch mailResult {
        case .success(let result):
            switch result {
            case .sent:
                AppLogger.review.notice("Feedback email reported sent by mail composer.")
            case .saved:
                AppLogger.review.notice("Feedback email saved as draft.")
            case .cancelled:
                AppLogger.review.notice("Feedback email cancelled in mail composer.")
            case .failed:
                AppLogger.review.error("Mail composer reported a send failure.")
            @unknown default:
                AppLogger.review.error("Mail composer returned an unrecognized result.")
            }
        case .failure(let error):
            AppLogger.review.error("Mail composer error: \(error.localizedDescription, privacy: .public).")
        case .none:
            // Composer was dismissed without producing a result — most
            // likely a swipe-down on the sheet. Treat as cancel; no log
            // noise needed.
            break
        }

        // Whether the user actually sent or backed out, the form has
        // done its job. Dismiss so the host UI can re-evaluate any
        // follow-up state (e.g. enjoyment prompt cooldown).
        finalizeAndDismiss()
    }

    private func copyToClipboardAndConfirm() {
        let combined = """
        To: \(AppContactInfo.feedbackEmailAddress)
        Subject: \(emailSubject())

        \(emailBody())
        """
        UIPasteboard.general.string = combined
        AppLogger.review.notice("Feedback copied to clipboard as Mail-unavailable fallback.")
        showingClipboardConfirmation = true
    }

    private func finalizeAndDismiss() {
        dismiss()
    }

    // MARK: - Email assembly
    //
    // Body format is intentionally plain-text so it survives every
    // mail client's quirks. Section headers use `==` underlines so a
    // human reading the inbox can scan them. The diagnostics block is
    // appended only if the user kept the toggle on.

    private func emailSubject() -> String {
        let version = AppMetadata.shortVersion
        return "\(AppContactInfo.feedbackEmailSubjectPrefix) (\(category.displayName)) — v\(version)"
    }

    private func emailBody() -> String {
        var lines: [String] = []
        lines.append("Category")
        lines.append("========")
        lines.append(category.displayName)
        lines.append("")

        if rating > 0 {
            lines.append("Rating")
            lines.append("======")
            lines.append("\(rating) of 5 stars")
            lines.append("")
        }

        lines.append("Message")
        lines.append("=======")
        lines.append(trimmedBody)
        lines.append("")

        if includeDiagnostics {
            lines.append("Diagnostics")
            lines.append("===========")
            lines.append(AppMetadata.diagnosticsReport())
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Feedback category

/// Subset of categories tuned to what this app actually receives in
/// support email today. Adding a new case here automatically extends
/// both the picker and the email subject line — no other edits needed.
enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case featureRequest
    case general
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug:            return "Bug Report"
        case .featureRequest: return "Feature Request"
        case .general:        return "General Feedback"
        case .other:          return "Other"
        }
    }
}

// MARK: - Star rating picker

/// Tap a star to set the rating to that value, or tap the currently
/// selected star to clear back to "no rating" (0). Kept private to this
/// file because no other surface needs it.
private struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = (rating == value) ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(value <= rating ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                .accessibilityValue(value <= rating ? "Selected" : "Not selected")
                .accessibilityHint("Sets the rating to \(value).")
            }
            Spacer()
        }
    }
}

// MARK: - Diagnostics preview

/// Shows the user exactly what will be appended to the email body if
/// they keep the diagnostics toggle on. Same data, same formatting —
/// no surprises.
private struct DiagnosticsPreview: View {
    var body: some View {
        Text(AppMetadata.diagnosticsReport())
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

// MARK: - App metadata helper

/// Tiny sidecar that consolidates the four "what version are you on?"
/// questions support always asks. Kept here because no other view
/// needs it — if it gets a third caller we should hoist it.
private enum AppMetadata {

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    /// `UIDevice.current.model` returns the device family ("iPhone",
    /// "iPad") rather than the marketing name. Good enough for a
    /// triage pass; nobody wants us shipping the IOKit incantation
    /// just to pretty-print "iPhone 16 Pro".
    static var deviceFamily: String {
        UIDevice.current.model
    }

    static var systemVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static func diagnosticsReport() -> String {
        """
        App: Headway: Migraine Monitor
        Version: \(shortVersion) (build \(buildNumber))
        OS: \(systemVersion)
        Device: \(deviceFamily)
        """
    }
}

// MARK: - MFMailComposeViewController bridge

/// SwiftUI wrapper around `MFMailComposeViewController`. The composer
/// itself is UIKit; this is the boilerplate that lets us drive it from
/// a `.sheet` and observe completion via a `Result` binding.
private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String

    @Binding var result: Result<MFMailComposeResult, Error>?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(result: $result, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No live updates — the composer is configured once at create.
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var result: Result<MFMailComposeResult, Error>?
        let dismiss: () -> Void

        init(
            result: Binding<Result<MFMailComposeResult, Error>?>,
            dismiss: @escaping () -> Void
        ) {
            self._result = result
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            if let error {
                self.result = .failure(error)
            } else {
                self.result = .success(result)
            }
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview("From Settings") {
    FeedbackFormView(origin: .settings)
}

#Preview("After Not Really") {
    FeedbackFormView(origin: .enjoymentPromptNegative)
}

#endif
