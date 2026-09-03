import SwiftUI
import UniformTypeIdentifiers

/// Write-only CSV document for `fileExporter`. Built eagerly from the
/// entries the user chose to export so the sheet never touches Core Data.
struct MigraineCSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    static let writableContentTypes: [UTType] = [.commaSeparatedText]

    let csv: String

    init(migraines: [MigraineEvent]) {
        csv = Self.makeCSV(migraines)
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }

    static func defaultFilename(prefix: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(prefix)_\(formatter.string(from: date)).csv"
    }

    private static func makeCSV(_ migraines: [MigraineEvent]) -> String {
        var csv = "Date,Time,Pain Level,Location,Duration,Triggers,Medications,Symptoms,Notes\n"
        for m in migraines {
            let date = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? ""
            let time = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
            let fields: [String] = [
                date,
                time,
                "\(m.painLevel)",
                m.location ?? "",
                m.completedDurationText ?? "",
                m.orderedTriggers.map(\.displayName).joined(separator: "; "),
                m.orderedMedications.map(\.fullDisplayName).joined(separator: "; "),
                m.symptomNames.joined(separator: "; "),
                m.notes ?? ""
            ]
            csv += fields.map(quote).joined(separator: ",") + "\n"
        }
        return csv
    }

    private static func quote(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension MigraineEvent {
    /// "2h 15m" for finished attacks; nil while an attack is still open.
    var completedDurationText: String? {
        guard let start = startTime, let end = endTime else { return nil }
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return nil }
        let hours = Int(interval / 3600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var symptomNames: [String] {
        var names: [String] = []
        if hasAura { names.append("Aura") }
        if hasPhotophobia { names.append("Photophobia") }
        if hasPhonophobia { names.append("Phonophobia") }
        if hasNausea { names.append("Nausea") }
        if hasVomiting { names.append("Vomiting") }
        if hasWakeUpHeadache { names.append("Wake-up Headache") }
        if hasTinnitus { names.append("Tinnitus") }
        if hasVertigo { names.append("Vertigo") }
        return names
    }

    // Non-optional projections so `Table` columns can sort with `KeyPathComparator`.
    var sortableStartTime: Date { startTime ?? .distantPast }
    var sortableDuration: TimeInterval { endTime == nil ? 0 : (duration ?? 0) }
    var sortableLocation: String { location ?? "" }
    var symptomCount: Int { symptomNames.count }
}
