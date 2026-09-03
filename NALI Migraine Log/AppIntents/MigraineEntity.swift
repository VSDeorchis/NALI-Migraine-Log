//
//  MigraineEntity.swift
//  NALI Migraine Log
//
//  App Intents representation of a logged migraine so Shortcuts and Siri
//  can reference existing entries ("get my migraines from the last week"
//  → count them, build a summary, hand them to another action).
//
//  Privacy: entries are deliberately *not* conformed to `IndexedEntity`
//  and are never donated to Core Spotlight. Health data must not surface
//  in system-wide search or on the lock screen without the user opening
//  the app, so the entity is only reachable through explicit Shortcuts
//  actions the user builds themselves. Notes, location, and medications
//  are omitted from the entity for the same reason.
//
//  iOS 27 (WWDC26) follow-ups, gated on the Xcode 27 SDK:
//    • Adopt the announced entity/intent *schemas* so Siri can resolve
//      "how many migraines did I have last month" without phrase lists.
//    • Mark `MigraineEntity` as a `SyncableEntity` once the CloudKit
//      record identity is exposed on the entity.
//    • Add View Annotations to `MigraineRowView` so on-screen awareness
//      maps rows back to this entity.
//

#if os(iOS)

import AppIntents
import CoreData
import Foundation

@available(iOS 17.0, *)
struct MigraineEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Migraine",
        numericFormat: "\(placeholder: .int) migraines"
    )

    static let defaultQuery = MigraineEntityQuery()

    var id: UUID

    @Property(title: "Start Time")
    var startTime: Date

    @Property(title: "End Time")
    var endTime: Date?

    @Property(title: "Pain Level")
    var painLevel: Int

    @Property(title: "Duration (minutes)")
    var durationMinutes: Int?

    @Property(title: "Triggers")
    var triggers: [MigraineTrigger]

    @Property(title: "Is Ongoing")
    var isOngoing: Bool

    var displayRepresentation: DisplayRepresentation {
        let when = startTime.formatted(date: .abbreviated, time: .shortened)
        var detail = "Pain \(painLevel)/10"
        if let durationMinutes {
            detail += " · \(Self.durationPhrase(minutes: durationMinutes))"
        } else {
            detail += " · Ongoing"
        }
        return DisplayRepresentation(
            title: "\(when)",
            subtitle: "\(detail)",
            image: .init(systemName: "brain.head.profile")
        )
    }

    init?(event: MigraineEvent) {
        guard let id = event.id, let start = event.startTime else { return nil }
        self.id = id
        self.startTime = start
        self.endTime = event.endTime
        self.painLevel = Int(event.painLevel)
        self.isOngoing = event.endTime == nil
        if let end = event.endTime {
            self.durationMinutes = max(0, Int(end.timeIntervalSince(start) / 60))
        } else {
            self.durationMinutes = nil
        }
        self.triggers = event.triggers.sorted { $0.displayName < $1.displayName }
    }

    static func durationPhrase(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }
}

@available(iOS 17.0, *)
struct MigraineEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MigraineEntity] {
        guard !identifiers.isEmpty else { return [] }
        let request = MigraineEvent.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", identifiers)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        return try Self.fetch(request)
    }

    @MainActor
    func suggestedEntities() async throws -> [MigraineEntity] {
        try await Self.recent(limit: 10)
    }

    @MainActor
    static func recent(since: Date? = nil, limit: Int = 200) async throws -> [MigraineEntity] {
        let request = MigraineEvent.fetchRequest()
        if let since {
            request.predicate = NSPredicate(format: "startTime >= %@", since as NSDate)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        request.fetchLimit = limit
        return try fetch(request)
    }

    @MainActor
    private static func fetch(_ request: NSFetchRequest<MigraineEvent>) throws -> [MigraineEntity] {
        let context = PersistenceController.shared.container.viewContext
        return try context.fetch(request).compactMap(MigraineEntity.init(event:))
    }
}

// MARK: - Recent migraines intent

/// "Get my migraines from the last N days" — returns entities that other
/// Shortcuts actions can count, filter, or format. Days is capped so a
/// misconfigured shortcut can't pull the entire history into Siri.
@available(iOS 17.0, *)
struct GetRecentMigrainesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recent Migraines"

    static let description = IntentDescription(
        "Returns the migraines logged in Headway over the last several days, most recent first. Use it with Count or Repeat actions in Shortcuts.",
        categoryName: "Migraine Logging",
        searchKeywords: ["migraine", "headache", "history", "recent", "count", "headway"]
    )

    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Days",
        description: "How many days back to look (1–365).",
        default: 30,
        inclusiveRange: (1, 365)
    )
    var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get migraines from the last \(\.$days) days")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[MigraineEntity]> & ProvidesDialog {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let entities = try await MigraineEntityQuery.recent(since: since)
        let dialog: IntentDialog
        switch entities.count {
        case 0:
            dialog = "No migraines logged in the last \(days) days."
        case 1:
            dialog = "One migraine logged in the last \(days) days."
        default:
            dialog = "\(entities.count) migraines logged in the last \(days) days."
        }
        return .result(value: entities, dialog: dialog)
    }
}

#endif
