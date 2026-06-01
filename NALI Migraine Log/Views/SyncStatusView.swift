import SwiftUI

struct SyncStatusView: View {
    @ObservedObject private var persistence = PersistenceController.shared
    @StateObject private var settings = SettingsManager.shared

    var body: some View {
        HStack {
            if !settings.useICloudSync {
                Label("Sync Disabled", systemImage: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            } else {
                switch persistence.syncStatus {
                case .syncing:
                    Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                case .error(let message):
                    // Surfaces real CloudKit problems (not signed into iCloud,
                    // storage full, offline, etc.) instead of a misleading green tick.
                    Label(message, systemImage: "exclamationmark.icloud.fill")
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.leading)
                case .enabled, .pendingChanges, .disabled, .notConfigured:
                    Label("Sync Enabled", systemImage: "checkmark.icloud.fill")
                        .foregroundColor(.green)
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
