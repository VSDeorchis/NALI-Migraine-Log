//
//  WatchSiriIntents.swift
//  NALI Migraine Log Watch App Watch App
//
//  Siri / Shortcuts entry points for the Apple Watch app.
//
//  Logging speed is the biggest UX driver for a migraine tracker — the
//  user is in pain, and the Watch is the device most likely to already
//  be on their wrist. These App Intents let them log a migraine, or jump
//  straight to the New Entry screen, by voice:
//
//      "Hey Siri, log a migraine in Headway."
//      "Hey Siri, log a migraine in Headway with pain 7."
//      "Hey Siri, open a new migraine entry in Headway."
//
//  Design notes:
//
//  • watchOS-only (`#if os(watchOS)`). The iOS target ships its own
//    richer `LogMigraineIntent` / `OpenNewEntryIntent`; these are the
//    Watch-target equivalents, registered through this target's own
//    `AppShortcutsProvider`.
//
//  • `LogMigraineIntent` is deliberately hands-free: pain level (default
//    5) and an optional note are the only parameters, so a bare phrase
//    logs an entry with zero follow-up prompts. Triggers / symptoms /
//    end time are left to be filled in on the phone — answering several
//    Siri prompts on the wrist defeats the speed-of-logging goal.
//
//  • Both intents go through the shared `MigraineViewModel.addMigraine`
//    so a Siri-logged entry behaves exactly like a tap-logged one
//    (engagement counter, Apple Health write, WatchConnectivity sync).
//

#if os(watchOS)

import AppIntents
import CoreData
import Foundation

// MARK: - Log Migraine (hands-free)

@available(watchOS 9.0, *)
struct LogMigraineIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Migraine"

    static let description = IntentDescription(
        "Quickly log a migraine starting now from your wrist. You can optionally provide a pain level from 1 to 10. Other details can be added later by editing the entry.",
        categoryName: "Migraine Logging",
        searchKeywords: ["migraine", "headache", "pain", "log", "headway", "track"]
    )

    /// Hands-free by design — don't foreground the app.
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Pain Level",
        description: "Pain intensity from 1 (barely noticeable) to 10 (worst imaginable).",
        default: 5,
        inclusiveRange: (1, 10)
    )
    var painLevel: Int

    @Parameter(
        title: "Notes",
        description: "Optional short note about how the migraine started or what you were doing."
    )
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a migraine with pain level \(\.$painLevel)") {
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext
        let viewModel = MigraineViewModel(context: context)

        // Reuse the exact in-app save path so the Siri entry gets the
        // same side-effects (review counter, Health write, sync) as a
        // tap-logged one. "Whole Head" matches the iOS Siri default.
        let saved = await viewModel.addMigraine(
            startTime: Date(),
            endTime: nil,
            painLevel: Int16(painLevel),
            location: "Whole Head",
            triggers: [],
            hasAura: false,
            hasPhotophobia: false,
            hasPhonophobia: false,
            hasNausea: false,
            hasVomiting: false,
            hasWakeUpHeadache: false,
            hasTinnitus: false,
            hasVertigo: false,
            missedWork: false,
            missedSchool: false,
            missedEvents: false,
            medications: [],
            notes: notes
        )

        if saved == nil {
            AppLogger.coreData.error("Watch Siri intent failed to save migraine")
            throw LogMigraineError.saveFailed
        }

        AppLogger.coreData.notice("Logged migraine via Watch Siri intent: pain=\(self.painLevel, privacy: .public)")

        let painPhrase = Self.painLevelPhrase(painLevel)
        return .result(dialog: "Logged your migraine, pain level \(painPhrase). Open Headway to add details when you're ready.")
    }

    /// Friendlier spoken description than the bare integer.
    static func painLevelPhrase(_ level: Int) -> String {
        let names = ["", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten"]
        guard level >= 1, level <= 10 else { return "\(level)" }
        return "\(names[level]) out of ten"
    }
}

enum LogMigraineError: Error, CustomLocalizedStringResourceConvertible {
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .saveFailed:
            return "Sorry, I couldn't save your migraine. Please try again in the app."
        }
    }
}

// MARK: - Open New Entry

@available(watchOS 9.0, *)
struct OpenNewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open New Migraine Entry"

    static let description = IntentDescription(
        "Opens Headway on your watch to the New Migraine Entry screen so you can record the full details.",
        categoryName: "Migraine Logging",
        searchKeywords: ["migraine", "headache", "log", "headway", "new", "entry", "open"]
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLogger.ui.notice("Opening New Entry screen via Watch Siri intent")
        WatchNavigationCoordinator.shared.requestNewEntry()
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Registers the Watch intents as zero-config Siri / Shortcuts actions.
/// Phrases include `\(.applicationName)` so Siri requires the "Headway"
/// qualifier and doesn't collide with other migraine trackers.
@available(watchOS 9.0, *)
struct HeadwayWatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMigraineIntent(),
            phrases: [
                "Log a migraine in \(.applicationName)",
                "Log a headache in \(.applicationName)",
                "Record a migraine in \(.applicationName)",
                "Track a migraine in \(.applicationName)",
                "Start a migraine in \(.applicationName)",
            ],
            shortTitle: "Log Migraine",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: OpenNewEntryIntent(),
            phrases: [
                "Open a new migraine entry in \(.applicationName)",
                "Open \(.applicationName) to log a migraine",
                "New migraine entry in \(.applicationName)",
                "Add a migraine in \(.applicationName)",
            ],
            shortTitle: "New Migraine Entry",
            systemImageName: "square.and.pencil"
        )
    }
}

#endif
