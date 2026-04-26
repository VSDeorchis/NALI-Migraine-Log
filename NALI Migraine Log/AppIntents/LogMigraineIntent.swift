//
//  LogMigraineIntent.swift
//  NALI Migraine Log
//
//  Siri / Shortcuts entry point for "Log a migraine in Headway."
//
//  Why an App Intent at all?
//
//  Speed-of-logging is the single biggest UX driver for migraine apps —
//  the user is in pain, and the harder it is to record an entry, the
//  more entries they skip. Siri lets the user log a migraine without
//  even unlocking their phone:
//
//      "Hey Siri, log a migraine in Headway."
//      "Hey Siri, log a migraine in Headway with pain 7."
//
//  We also register an App Shortcut so the action shows up in the
//  Shortcuts app and Siri Suggestions without the user having to set
//  anything up.
//
//  Design notes:
//
//  • iOS-only (`#if os(iOS)`). AppIntents *technically* exists on macOS
//    13+ and watchOS 9+, but our voice/Spotlight UX targets iPhone, and
//    we don't want to debug platform-specific perform() bodies. The
//    macOS app already exposes the equivalent action through the
//    "Log Migraine" command in the menu bar.
//
//  • Pain level defaults to 5 with `inclusiveRange: 1...10` so a
//    parameter-less invocation ("Hey Siri, log a migraine in Headway")
//    works without any follow-up question, while saying a number
//    ("…with pain 7") fills it in.
//
//  • We do not request a location, end-time, triggers, or symptoms
//    here — those need a richer UI to capture, and forcing the user to
//    answer five Siri prompts in a row defeats the speed-of-logging
//    goal. The user can edit the entry later in the app to add detail.
//
//  • We mirror the same side-effects the in-app `addMigraine` path
//    triggers: bumping the review-prompt engagement counter and
//    fanning out to Apple Health if the user has opted in. This way
//    Siri-logged entries count toward review eligibility and show up
//    in Health alongside in-app entries.
//

#if os(iOS)

import AppIntents
import CoreData
import Foundation

@available(iOS 17.0, *)
struct LogMigraineIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Migraine"

    static let description = IntentDescription(
        "Quickly log a migraine starting now. You can optionally provide a pain level from 1 to 10. Other details (triggers, medications, end time, symptoms) can be added later by editing the entry in the app.",
        categoryName: "Migraine Logging",
        searchKeywords: ["migraine", "headache", "pain", "log", "headway", "track"]
    )

    /// We don't open the app — the whole point is that this works
    /// hands-free from the lock screen / AirPods. The Siri response
    /// dialog tells the user the entry was saved.
    static let openAppWhenRun: Bool = false

    /// Pain level (1–10). Default of 5 means parameter-less invocations
    /// "just work" — Siri only prompts the user if they explicitly
    /// asked to fill it in via shortcut configuration.
    @Parameter(
        title: "Pain Level",
        description: "Pain intensity from 1 (barely noticeable) to 10 (worst imaginable).",
        default: 5,
        inclusiveRange: (1, 10)
    )
    var painLevel: Int

    /// Optional free-text note. Skipped automatically when not provided.
    @Parameter(
        title: "Notes",
        description: "Optional short note about how the migraine started or what you were doing."
    )
    var notes: String?

    /// Run on the main actor because Core Data's view context (and
    /// our HealthKit / ReviewPromptCoordinator side-effects) are all
    /// MainActor-isolated. App Intents short-running operations on
    /// the main thread are the recommended pattern.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext

        let migraine = MigraineEvent(context: context)
        migraine.id = UUID()
        migraine.startTime = Date()
        migraine.endTime = nil
        migraine.painLevel = Int16(painLevel)
        migraine.location = "Whole Head"
        migraine.notes = notes

        // Match the field initialization the in-app `addMigraine` does
        // so we don't ship a half-formed object into Core Data + CloudKit.
        // All the booleans default to `false`; the weather struct gets
        // zeroed so the standard backfill path can pick this entry up
        // later when location is available.
        migraine.hasAura = false
        migraine.hasPhotophobia = false
        migraine.hasPhonophobia = false
        migraine.hasNausea = false
        migraine.hasVomiting = false
        migraine.hasWakeUpHeadache = false
        migraine.hasTinnitus = false
        migraine.hasVertigo = false
        migraine.missedWork = false
        migraine.missedSchool = false
        migraine.missedEvents = false
        migraine.triggers = []
        migraine.medications = []
        migraine.hasWeatherData = false
        migraine.weatherTemperature = 0
        migraine.weatherPressure = 0
        migraine.weatherPressureChange24h = 0
        migraine.weatherPrecipitation = 0
        migraine.weatherCloudCover = 0
        migraine.weatherCode = 0
        migraine.weatherLatitude = 0
        migraine.weatherLongitude = 0

        do {
            try context.save()
            AppLogger.coreData.notice("Logged migraine via Siri intent: pain=\(self.painLevel, privacy: .public)")
        } catch {
            AppLogger.coreData.error("Siri intent save failed: \(error.localizedDescription, privacy: .public)")
            // Surface the error so Siri/Shortcuts shows it to the user
            // rather than silently swallowing it.
            throw error
        }

        // Same engagement bookkeeping the in-app path does — Siri-logged
        // entries should also count toward review eligibility, otherwise
        // a Siri-heavy user would never see the prompt.
        ReviewPromptCoordinator.recordEntryLogged()

        // Fan out to Apple Health if the user has opted in. Doesn't block
        // the dialog return — but we do `await` here because we want the
        // sample written before the user opens Health to verify, and
        // because we're already on the main actor with cheap dispatch.
        await HealthKitManager.shared.writeMigraineToHealth(migraine)

        let painPhrase = painLevelPhrase(painLevel)
        return .result(dialog: "Logged your migraine, pain level \(painPhrase). Open Headway to add details when you're ready.")
    }

    /// Friendlier spoken description than the bare integer. "Logged
    /// your migraine, pain level seven out of ten" is more natural
    /// than "Logged your migraine, pain level 7."
    private func painLevelPhrase(_ level: Int) -> String {
        let names = ["", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten"]
        guard level >= 1, level <= 10 else { return "\(level)" }
        return "\(names[level]) out of ten"
    }
}

// MARK: - App Shortcuts Provider

/// Registers `LogMigraineIntent` as a zero-config Siri / Spotlight
/// shortcut. The user doesn't need to set anything up — once the app
/// launches once, these phrases work immediately.
///
/// The phrases all include `\(.applicationName)` so Siri requires the
/// "Headway" qualifier — without it, generic "log a migraine" would
/// collide with every other migraine-tracker installed.
@available(iOS 17.0, *)
struct HeadwayAppShortcuts: AppShortcutsProvider {
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
    }
}

#endif
