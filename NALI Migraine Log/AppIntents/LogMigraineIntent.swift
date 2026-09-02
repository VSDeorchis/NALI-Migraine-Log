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

    /// Optional start time. Defaults to "now" when omitted, which is the
    /// common case for a just-now voice log. Power users can set it in
    /// the Shortcuts app to back-date a completed migraine (paired with
    /// `endTime`).
    @Parameter(
        title: "Start Time",
        description: "When the migraine began. Defaults to now if left empty."
    )
    var startTime: Date?

    /// Optional end time. Left empty for an ongoing migraine (the common
    /// case for a just-now voice log). For a completed migraine, set both
    /// `startTime` and `endTime` in the past. Ignored if it isn't after
    /// the effective start time.
    @Parameter(
        title: "End Time",
        description: "When the migraine ended, if it's already over. Leave empty if it's still ongoing."
    )
    var endTime: Date?

    /// Optional triggers. Not prompted for a bare "log a migraine"
    /// invocation — only filled in when the user configures the shortcut
    /// to include them.
    @Parameter(
        title: "Triggers",
        description: "Any suspected triggers for this migraine."
    )
    var triggers: [MigraineTrigger]?

    /// Optional symptoms, same opt-in behavior as triggers.
    @Parameter(
        title: "Symptoms",
        description: "Symptoms you experienced with this migraine."
    )
    var symptoms: [MigraineSymptomOption]?

    /// Shown in the Shortcuts editor. Pain level is the headline; the
    /// optional details live behind the "Show More" disclosure so the
    /// bare voice phrase stays a one-tap, zero-prompt action.
    static var parameterSummary: some ParameterSummary {
        Summary("Log a migraine with pain level \(\.$painLevel)") {
            \.$startTime
            \.$endTime
            \.$triggers
            \.$symptoms
            \.$notes
        }
    }

    /// Run on the main actor because Core Data's view context (and
    /// our HealthKit / ReviewPromptCoordinator side-effects) are all
    /// MainActor-isolated. App Intents short-running operations on
    /// the main thread are the recommended pattern.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext

        let migraine = MigraineEvent(context: context)
        migraine.id = UUID()
        // Default to "now" for a hands-free quick log; honor an explicit
        // start time when the user back-dates a completed migraine via
        // the Shortcuts app.
        let start = startTime ?? Date()
        migraine.startTime = start
        // Only honor an end time that's genuinely after the (effective)
        // start. A reversed range would later crash the Apple Health
        // export (the end-before-start bug fixed in an earlier release),
        // so we defensively drop a bad value and treat the entry as
        // ongoing.
        if let endTime, endTime > start {
            migraine.endTime = endTime
        } else {
            migraine.endTime = nil
        }
        migraine.painLevel = Int16(painLevel)
        migraine.location = "Whole Head"
        migraine.notes = notes

        // Map the optional symptom multi-select onto the underlying
        // booleans. Anything not chosen stays `false`, matching the
        // in-app `addMigraine` default. The weather struct gets zeroed
        // so the standard backfill path can pick this entry up later
        // when location is available.
        let symptomSet = Set(symptoms ?? [])
        migraine.hasAura = symptomSet.contains(.aura)
        migraine.hasPhotophobia = symptomSet.contains(.photophobia)
        migraine.hasPhonophobia = symptomSet.contains(.phonophobia)
        migraine.hasNausea = symptomSet.contains(.nausea)
        migraine.hasVomiting = symptomSet.contains(.vomiting)
        migraine.hasWakeUpHeadache = symptomSet.contains(.wakeUpHeadache)
        migraine.hasTinnitus = symptomSet.contains(.tinnitus)
        migraine.hasVertigo = symptomSet.contains(.vertigo)
        migraine.missedWork = false
        migraine.missedSchool = false
        migraine.missedEvents = false
        migraine.triggers = Set(triggers ?? [])
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
            if let id = migraine.id {
                WatchConnectivityManager.shared.recordChange(of: id)
            }
        } catch {
            context.rollback()
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

// MARK: - App Intents value types

/// Symptom options exposed to Siri / Shortcuts as a multi-select.
///
/// These mirror the `has*` booleans on `MigraineEvent`. We use a
/// dedicated `AppEnum` rather than the raw booleans so the Shortcuts
/// editor shows a friendly checklist with the same labels the in-app
/// form uses.
@available(iOS 17.0, *)
enum MigraineSymptomOption: String, AppEnum {
    case aura
    case photophobia
    case phonophobia
    case nausea
    case vomiting
    case wakeUpHeadache
    case tinnitus
    case vertigo

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Symptom")
    }

    static var caseDisplayRepresentations: [MigraineSymptomOption: DisplayRepresentation] {
        [
            .aura: "Aura",
            .photophobia: "Light Sensitivity",
            .phonophobia: "Sound Sensitivity",
            .nausea: "Nausea",
            .vomiting: "Vomiting",
            .wakeUpHeadache: "Wake-up Headache",
            .tinnitus: "Tinnitus",
            .vertigo: "Vertigo",
        ]
    }
}

/// Make the shared `MigraineTrigger` selectable in Siri / Shortcuts.
/// Retroactive `AppEnum` conformance lives here (iOS-only) so the shared
/// model stays free of any AppIntents dependency on watchOS / macOS.
@available(iOS 17.0, *)
extension MigraineTrigger: AppEnum {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Migraine Trigger")
    }

    public static var caseDisplayRepresentations: [MigraineTrigger: DisplayRepresentation] {
        [
            .stress: "Stress",
            .lackOfSleep: "Lack of Sleep",
            .dehydration: "Dehydration",
            .weather: "Weather",
            .menstrual: "Menstrual",
            .alcohol: "Alcohol",
            .caffeine: "Caffeine",
            .food: "Food",
            .exercise: "Exercise",
            .screenTime: "Screen Time",
            .other: "Other",
        ]
    }
}

#endif
