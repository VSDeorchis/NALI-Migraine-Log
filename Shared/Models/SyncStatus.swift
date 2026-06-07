import Foundation

public enum SyncStatus: Equatable {
    case enabled
    case disabled
    case notConfigured
    case pendingChanges(Int)
    case syncing(Double)
    case error(String)
    /// Sync can't run because the device isn't signed into iCloud. This is a
    /// normal, expected state (not a failure) — surfaced calmly so the user
    /// knows how to enable sync rather than being alarmed by an error.
    case signInRequired(String)
    
    var isActive: Bool {
        switch self {
        case .enabled, .pendingChanges, .syncing:
            return true
        case .notConfigured, .disabled, .error, .signInRequired:
            return false
        }
    }
    
    var description: String {
        switch self {
        case .notConfigured:
            return "Not Configured"
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        case .pendingChanges(let count):
            return "Pending Changes (\(count))"
        case .syncing(let progress):
            let percentage = Int(progress * 100)
            return "Syncing \(percentage)%"
        case .error(let message):
            return "Error: \(message)"
        case .signInRequired(let message):
            return message
        }
    }
} 