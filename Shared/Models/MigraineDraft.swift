import Foundation

/// User-editable fields of a migraine entry, independent of Core Data.
/// The iOS, macOS and watchOS entry forms all funnel through this so the
/// mapping onto `MigraineEvent` lives in exactly one place.
struct MigraineDraft {
    var startTime: Date
    var endTime: Date?
    var painLevel: Int16
    var location: String
    var notes: String?
    var triggers: Set<MigraineTrigger> = []
    var medications: Set<MigraineMedication> = []

    var hasAura = false
    var hasPhotophobia = false
    var hasPhonophobia = false
    var hasNausea = false
    var hasVomiting = false
    var hasWakeUpHeadache = false
    var hasTinnitus = false
    var hasVertigo = false

    var missedWork = false
    var missedSchool = false
    var missedEvents = false
}

extension MigraineEvent {
    /// Writes every field of `draft` onto the entry. Weather attributes are
    /// untouched; they are owned by the weather lookup.
    func apply(_ draft: MigraineDraft) {
        startTime = draft.startTime
        endTime = draft.endTime
        painLevel = draft.painLevel
        location = draft.location
        notes = draft.notes

        hasAura = draft.hasAura
        hasPhotophobia = draft.hasPhotophobia
        hasPhonophobia = draft.hasPhonophobia
        hasNausea = draft.hasNausea
        hasVomiting = draft.hasVomiting
        hasWakeUpHeadache = draft.hasWakeUpHeadache
        hasTinnitus = draft.hasTinnitus
        hasVertigo = draft.hasVertigo
        missedWork = draft.missedWork
        missedSchool = draft.missedSchool
        missedEvents = draft.missedEvents

        // Facade setters write all underlying booleans atomically (true if in
        // the set, false otherwise), so no separate "reset" pass is needed.
        triggers = draft.triggers
        medications = draft.medications
    }

    /// Explicit zero weather state for a freshly inserted entry.
    func clearWeatherData() {
        hasWeatherData = false
        weatherTemperature = 0
        weatherPressure = 0
        weatherPressureChange24h = 0
        weatherPrecipitation = 0
        weatherCloudCover = 0
        weatherCode = 0
        weatherLatitude = 0
        weatherLongitude = 0
    }
}
