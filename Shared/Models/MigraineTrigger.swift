import Foundation
import CoreData

/// Strongly-typed representation of a migraine trigger.
///
/// This is a *Swift-only facade* over the existing boolean attributes on
/// `MigraineEvent` (`isTriggerStress`, `isTriggerLackOfSleep`, ...).
/// On-disk storage and CloudKit schema are unchanged — every read/write still
/// goes through the same booleans, so existing data and sync paths are
/// completely unaffected.
public enum MigraineTrigger: String, CaseIterable, Identifiable, Hashable, Sendable {
    case stress
    case lackOfSleep
    case dehydration
    case weather
    case menstrual          // persisted on disk as `isTriggerHormones`
    case alcohol
    case caffeine
    case food
    case exercise
    case screenTime
    case other

    public var id: String { rawValue }

    /// Canonical user-facing display name. Single source of truth for UI labels.
    public var displayName: String {
        switch self {
        case .stress:       return "Stress"
        case .lackOfSleep:  return "Lack of Sleep"
        case .dehydration:  return "Dehydration"
        case .weather:      return "Weather"
        case .menstrual:    return "Menstrual"
        case .alcohol:      return "Alcohol"
        case .caffeine:     return "Caffeine"
        case .food:         return "Food"
        case .exercise:     return "Exercise"
        case .screenTime:   return "Screen Time"
        case .other:        return "Other"
        }
    }

    /// Lowercase keywords used by the search bar. Includes legacy synonyms
    /// (e.g. "hormones" still matches the menstrual case).
    public var searchKeywords: [String] {
        switch self {
        case .stress:       return ["stress"]
        case .lackOfSleep:  return ["lack of sleep", "sleep"]
        case .dehydration:  return ["dehydration"]
        case .weather:      return ["weather"]
        case .menstrual:    return ["menstrual", "hormones"]
        case .alcohol:      return ["alcohol"]
        case .caffeine:     return ["caffeine"]
        case .food:         return ["food"]
        case .exercise:     return ["exercise"]
        case .screenTime:   return ["screen time", "screen"]
        case .other:        return ["other"]
        }
    }

    /// Best-effort match from a legacy display string. Tolerates case,
    /// surrounding whitespace, and the historical "Hormones" label.
    public init?(displayName: String) {
        let normalized = displayName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        for trigger in MigraineTrigger.allCases
        where trigger.displayName.lowercased() == normalized {
            self = trigger
            return
        }
        switch normalized {
        case "hormones":            self = .menstrual
        case "lack-of-sleep",
             "lack_of_sleep":       self = .lackOfSleep
        case "screen-time",
             "screen_time":         self = .screenTime
        default: return nil
        }
    }
}

// MARK: - MigraineEvent facade

extension MigraineEvent {
    /// All triggers currently flagged on this entry, exposed as a strongly-typed
    /// `Set`. Reads and writes are translated to/from the underlying boolean
    /// `@NSManaged` attributes — storage on disk is unchanged.
    public var triggers: Set<MigraineTrigger> {
        get {
            var result: Set<MigraineTrigger> = []
            if isTriggerStress       { result.insert(.stress) }
            if isTriggerLackOfSleep  { result.insert(.lackOfSleep) }
            if isTriggerDehydration  { result.insert(.dehydration) }
            if isTriggerWeather      { result.insert(.weather) }
            if isTriggerHormones     { result.insert(.menstrual) }
            if isTriggerAlcohol      { result.insert(.alcohol) }
            if isTriggerCaffeine     { result.insert(.caffeine) }
            if isTriggerFood         { result.insert(.food) }
            if isTriggerExercise     { result.insert(.exercise) }
            if isTriggerScreenTime   { result.insert(.screenTime) }
            if isTriggerOther        { result.insert(.other) }
            return result
        }
        set {
            isTriggerStress       = newValue.contains(.stress)
            isTriggerLackOfSleep  = newValue.contains(.lackOfSleep)
            isTriggerDehydration  = newValue.contains(.dehydration)
            isTriggerWeather      = newValue.contains(.weather)
            isTriggerHormones     = newValue.contains(.menstrual)
            isTriggerAlcohol      = newValue.contains(.alcohol)
            isTriggerCaffeine     = newValue.contains(.caffeine)
            isTriggerFood         = newValue.contains(.food)
            isTriggerExercise     = newValue.contains(.exercise)
            isTriggerScreenTime   = newValue.contains(.screenTime)
            isTriggerOther        = newValue.contains(.other)
        }
    }

    /// Returns the active triggers in canonical declaration order — useful for
    /// stable display in lists, CSV exports, etc.
    public var orderedTriggers: [MigraineTrigger] {
        let active = triggers
        return MigraineTrigger.allCases.filter { active.contains($0) }
    }
}
