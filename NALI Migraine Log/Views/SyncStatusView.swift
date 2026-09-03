import SwiftUI

struct SyncStatusView: View {
    @ObservedObject private var persistence = PersistenceController.shared
    private let settings = SettingsManager.shared

    var body: some View {
        HStack {
            if !settings.useICloudSync {
                Label("Sync Disabled", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                switch persistence.syncStatus {
                case .syncing:
                    Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                case .error(let message):
                    // Surfaces real CloudKit problems (storage full, offline,
                    // server errors, etc.) instead of a misleading green tick.
                    Label(message, systemImage: "exclamationmark.icloud.fill")
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                case .signInRequired(let message):
                    // Not signed into iCloud — a normal state, not a failure.
                    // Styled calmly (secondary, no warning color) so the user
                    // gets a gentle prompt rather than an alarming error.
                    Label(message, systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                case .enabled, .pendingChanges, .disabled, .notConfigured:
                    Label("Sync Enabled", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal)
    }
}

#Preview {
    SyncStatusView()
}
