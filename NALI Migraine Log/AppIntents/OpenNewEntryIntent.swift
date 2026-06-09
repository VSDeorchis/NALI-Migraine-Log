//
//  OpenNewEntryIntent.swift
//  NALI Migraine Log
//
//  Siri / Shortcuts entry point for "Open Headway to log a migraine."
//
//  Why a *second* intent alongside `LogMigraineIntent`?
//
//  `LogMigraineIntent` is the hands-free path: it saves an entry without
//  ever opening the app, which is exactly what you want when you're in
//  pain and just want it recorded. But sometimes the user *does* want the
//  full form — to set triggers, symptoms, an end time, medications — with
//  the real UI. This intent is that path: it foregrounds the app and
//  jumps straight to the New Entry screen, skipping the tab the user
//  happened to leave open.
//
//  Mechanism: App Intents run outside the SwiftUI view tree, so we can't
//  toggle a view's `@State` directly. Instead we publish the request on
//  `AppNavigationCoordinator.shared`, which the app root observes and
//  turns into a presented sheet. `openAppWhenRun = true` brings the app
//  to the foreground first.
//

#if os(iOS)

import AppIntents
import Foundation

@available(iOS 17.0, *)
struct OpenNewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open New Migraine Entry"

    static let description = IntentDescription(
        "Opens Headway to the New Migraine Entry screen so you can record the full details — pain, triggers, symptoms, medications, and end time.",
        categoryName: "Migraine Logging",
        searchKeywords: ["migraine", "headache", "log", "headway", "new", "entry", "open"]
    )

    /// Unlike `LogMigraineIntent`, the whole point here is to land the
    /// user inside the app on the entry form.
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLogger.ui.notice("Opening New Entry screen via Siri intent")
        AppNavigationCoordinator.shared.requestNewEntry()
        return .result()
    }
}

#endif
