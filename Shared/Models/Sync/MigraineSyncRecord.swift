import Foundation
import CoreData

/// Wire format for a single migraine entry exchanged between the iPhone and
/// Watch apps over WatchConnectivity.
///
/// Design goals:
/// - **Typed & versioned.** Encoded with `JSONEncoder` inside a
///   `WatchSyncEnvelope`; unknown or malformed payloads are rejected as a
///   whole instead of being partially applied.
/// - **Compact.** Single-letter coding keys and "only the flags that are on"
///   arrays keep a record around 150 bytes so a snapshot of recent history
///   fits comfortably under WatchConnectivity's payload ceiling.
/// - **Minimal.** Weather, coordinates and other phone-only enrichment are
///   never transmitted. `notes` is optional so the phone can omit it when
///   pushing history to the Watch.
struct MigraineSyncRecord: Codable, Hashable, Sendable {
    enum Symptom: String, CaseIterable, Sendable {
        case aura, photophobia, phonophobia, nausea, vomiting
        case wakeUpHeadache, tinnitus, vertigo
        case missedWork, missedSchool, missedEvents
    }

    static let maxLocationLength = 100
    static let maxNotesLength = 2_000
    static let painLevelRange: ClosedRange<Int> = 0...10

    var id: UUID
    var startTime: Date
    var endTime: Date?
    var painLevel: Int
    var location: String?
    var notes: String?
    var symptoms: [String]
    var triggers: [String]
    var medications: [String]
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "i"
        case startTime = "s"
        case endTime = "e"
        case painLevel = "p"
        case location = "l"
        case notes = "n"
        case symptoms = "y"
        case triggers = "t"
        case medications = "m"
        case modifiedAt = "u"
    }

    /// Returns a sanitized copy, or `nil` when required fields are outside
    /// acceptable bounds (the record is then dropped by the receiver).
    func validated(now: Date = Date()) -> MigraineSyncRecord? {
        guard Self.painLevelRange.contains(painLevel) else { return nil }
        // Reject obviously bogus timestamps (before the app existed, or more
        // than a day in the future to allow for clock skew).
        let earliest = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
        guard startTime >= earliest, startTime <= now.addingTimeInterval(86_400) else { return nil }

        var copy = self
        if let endTime, endTime < startTime {
            copy.endTime = nil
        }
        copy.location = location.map { String($0.prefix(Self.maxLocationLength)) }
        copy.notes = notes.map { String($0.prefix(Self.maxNotesLength)) }
        copy.symptoms = symptoms.filter { Symptom(rawValue: $0) != nil }
        copy.triggers = triggers.filter { MigraineTrigger(rawValue: $0) != nil }
        copy.medications = medications.filter { MigraineMedication(rawValue: $0) != nil }
        return copy
    }
}

/// Top-level WatchConnectivity payload. Carried as `Data` under
/// `WatchSyncEnvelope.payloadKey` in the application context (snapshots) or a
/// user-info transfer (deltas).
struct WatchSyncEnvelope: Codable, Sendable {
    static let currentVersion = 2
    static let payloadKey = "syncV2"
    static let batchIDKey = "syncBatchID"

    enum Kind: String, Codable, Sendable {
        /// Recent history pushed by the phone. Receivers upsert every record
        /// unless they hold an un-acknowledged local edit for the same id.
        case snapshot
        /// Records the sender itself created or edited. Receivers always apply.
        case delta
    }

    var version: Int = WatchSyncEnvelope.currentVersion
    var kind: Kind
    var sentAt: Date
    var records: [MigraineSyncRecord]
    var deletedIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case kind = "k"
        case sentAt = "a"
        case records = "r"
        case deletedIDs = "d"
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Decodes and validates an envelope. Returns `nil` for foreign or
    /// incompatible payloads; individual invalid records are dropped.
    static func decode(from payload: [String: Any]) -> WatchSyncEnvelope? {
        guard let data = payload[payloadKey] as? Data,
              var envelope = try? decoder.decode(WatchSyncEnvelope.self, from: data),
              envelope.version == currentVersion else {
            return nil
        }
        let now = Date()
        envelope.records = envelope.records.compactMap { $0.validated(now: now) }
        return envelope
    }
}

// MARK: - MigraineEvent bridging

extension MigraineSyncRecord {
    /// Builds a record from a managed object. Returns `nil` when the entry has
    /// no `id` (it cannot be reconciled on the other device).
    ///
    /// - Parameter includeNotes: free-text notes are only sent for
    ///   Watch-authored deltas; phone-pushed history omits them.
    init?(event: MigraineEvent, includeNotes: Bool, modifiedAt: Date = Date()) {
        guard let id = event.id else { return nil }
        self.id = id
        self.startTime = event.startTime ?? modifiedAt
        self.endTime = event.endTime
        self.painLevel = Int(event.painLevel)
        self.location = event.location
        self.notes = includeNotes ? event.notes : nil
        self.modifiedAt = modifiedAt

        var symptoms: [String] = []
        if event.hasAura { symptoms.append(Symptom.aura.rawValue) }
        if event.hasPhotophobia { symptoms.append(Symptom.photophobia.rawValue) }
        if event.hasPhonophobia { symptoms.append(Symptom.phonophobia.rawValue) }
        if event.hasNausea { symptoms.append(Symptom.nausea.rawValue) }
        if event.hasVomiting { symptoms.append(Symptom.vomiting.rawValue) }
        if event.hasWakeUpHeadache { symptoms.append(Symptom.wakeUpHeadache.rawValue) }
        if event.hasTinnitus { symptoms.append(Symptom.tinnitus.rawValue) }
        if event.hasVertigo { symptoms.append(Symptom.vertigo.rawValue) }
        if event.missedWork { symptoms.append(Symptom.missedWork.rawValue) }
        if event.missedSchool { symptoms.append(Symptom.missedSchool.rawValue) }
        if event.missedEvents { symptoms.append(Symptom.missedEvents.rawValue) }
        self.symptoms = symptoms

        self.triggers = event.orderedTriggers.map(\.rawValue)
        self.medications = event.orderedMedications.map(\.rawValue)
    }

    /// Writes every transmitted field onto `event`. Fields the record does
    /// not carry (weather, coordinates) are left untouched. `notes` is only
    /// overwritten when the record actually carries notes, so a phone-pushed
    /// snapshot never erases text typed on the receiving device.
    func apply(to event: MigraineEvent) {
        event.id = id
        event.startTime = startTime
        event.endTime = endTime
        event.painLevel = Int16(clamping: painLevel)
        event.location = location
        if let notes {
            event.notes = notes
        }

        let symptomSet = Set(symptoms.compactMap(Symptom.init(rawValue:)))
        event.hasAura = symptomSet.contains(.aura)
        event.hasPhotophobia = symptomSet.contains(.photophobia)
        event.hasPhonophobia = symptomSet.contains(.phonophobia)
        event.hasNausea = symptomSet.contains(.nausea)
        event.hasVomiting = symptomSet.contains(.vomiting)
        event.hasWakeUpHeadache = symptomSet.contains(.wakeUpHeadache)
        event.hasTinnitus = symptomSet.contains(.tinnitus)
        event.hasVertigo = symptomSet.contains(.vertigo)
        event.missedWork = symptomSet.contains(.missedWork)
        event.missedSchool = symptomSet.contains(.missedSchool)
        event.missedEvents = symptomSet.contains(.missedEvents)

        event.triggers = Set(triggers.compactMap(MigraineTrigger.init(rawValue:)))
        event.medications = Set(medications.compactMap(MigraineMedication.init(rawValue:)))
    }
}
