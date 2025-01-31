import Foundation

struct MigraineEvent: Identifiable, Codable {
    let id: UUID
    var startTime: Date
    var endTime: Date?
    var painLevel: Int // 1-10 scale
    var location: PainLocation
    var triggers: Set<Trigger>
    var hasPhotophobia: Bool
    var hasPhonophobia: Bool
    var hasNausea: Bool
    var hasVomiting: Bool
    var hasAura: Bool
    var hasWakeUpHeadache: Bool
    var hasTinnitus: Bool
    var hasVertigo: Bool
    var missedWork: Bool
    var missedSchool: Bool
    var missedEvents: Bool
    var medications: Set<Medication>
    var notes: String?
    
    init(id: UUID = UUID(), 
         startTime: Date = Date(),
         endTime: Date? = nil,
         painLevel: Int = 5,
         location: PainLocation = .frontal,
         triggers: Set<Trigger> = [],
         hasPhotophobia: Bool = false,
         hasPhonophobia: Bool = false,
         hasNausea: Bool = false,
         hasVomiting: Bool = false,
         hasAura: Bool = false,
         hasWakeUpHeadache: Bool = false,
         hasTinnitus: Bool = false,
         hasVertigo: Bool = false,
         missedWork: Bool = false,
         missedSchool: Bool = false,
         missedEvents: Bool = false,
         medications: Set<Medication> = [],
         notes: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.painLevel = max(1, min(10, painLevel)) // Ensure 1-10 range
        self.location = location
        self.triggers = triggers
        self.hasPhotophobia = hasPhotophobia
        self.hasPhonophobia = hasPhonophobia
        self.hasNausea = hasNausea
        self.hasVomiting = hasVomiting
        self.hasAura = hasAura
        self.hasWakeUpHeadache = hasWakeUpHeadache
        self.hasTinnitus = hasTinnitus
        self.hasVertigo = hasVertigo
        self.missedWork = missedWork
        self.missedSchool = missedSchool
        self.missedEvents = missedEvents
        self.medications = medications
        self.notes = notes
    }
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

enum PainLocation: String, Codable, CaseIterable {
    case left = "Left side"
    case right = "Right side"
    case both = "Both sides"
    case frontal = "Frontal"
    case occipital = "Back of head"
    case other = "Other"
}

enum Trigger: String, Codable, CaseIterable {
    case stress = "Stress"
    case lackOfSleep = "Lack of Sleep"
    case food = "Food"
    case alcohol = "Alcohol"
    case caffeine = "Caffeine"
    case weather = "Weather Changes"
    case menstruation = "Menstruation"
    case exercise = "Exercise"
    case screenTime = "Screen Time"
    case dehydration = "Dehydration"
    case exertion = "Exertion"
    case infection = "Infection/Illness"
}

enum Medication: String, Codable, CaseIterable {
    case nsaid = "NSAID"
    case tylenol = "Tylenol"
    case nurtec = "Nurtec (rimegepant)"
    case ubrelvy = "Ubrelvy (ubrogepant)"
    case zavzpret = "Zavzpret (zavegepant)"
    case trudhesa = "Trudhesa (dihydroergotamine)"
    case sumatriptan = "Sumatriptan"
    case rizatriptan = "Rizatriptan"
    case elatriptan = "Elatriptan"
    case naratriptan = "Naratriptan"
    case frovatriptan = "Frovatriptan"
    case steroid = "Steroid"
} 