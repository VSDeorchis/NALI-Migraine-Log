import Foundation

/// Keeps an in-progress entry on disk so an accidental dismiss or a
/// failed save never loses what the user typed. One draft per device;
/// stored in Application Support with the same at-rest protection as the
/// Core Data store and excluded from backups.
enum MigraineDraftStore {
    private static let fileName = "pending-migraine-draft.json"

    private static var writeOptions: Data.WritingOptions {
        #if os(macOS)
        return [.atomic]
        #else
        return [.atomic, .completeFileProtection]
        #endif
    }

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> MigraineDraft? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(MigraineDraft.self, from: data)
        } catch {
            AppLogger.coreData.error("Discarding unreadable entry draft: \(error.localizedDescription, privacy: .private)")
            clear()
            return nil
        }
    }

    static func save(_ draft: MigraineDraft) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(draft).write(to: url, options: writeOptions)
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
        } catch {
            AppLogger.coreData.error("Failed to store entry draft: \(error.localizedDescription, privacy: .private)")
        }
    }

    static func clear() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppLogger.coreData.error("Failed to remove entry draft: \(error.localizedDescription, privacy: .private)")
        }
    }
}
