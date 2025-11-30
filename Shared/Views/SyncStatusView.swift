import SwiftUI

enum SyncStatus: String {
    case notConfigured = "Not Configured"
    case syncing = "Syncing..."
    case synced = "Synced"
    case error = "Sync Error"
    case offline = "Offline"
    
    var icon: String {
        switch self {
        case .notConfigured: return "xmark.circle"
        case .syncing: return "arrow.2.circlepath"
        case .synced: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        case .offline: return "wifi.slash"
        }
    }
    
    var color: Color {
        switch self {
        case .notConfigured: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        case .offline: return .orange
        }
    }
}

struct SyncStatusView: View {
    @ObservedObject var connectivityManager: WatchConnectivityManager
    @State private var showingError = false
    
    var body: some View {
        HStack {
            Image(systemName: connectivityManager.syncStatus.icon)
                .foregroundColor(connectivityManager.syncStatus.color)
            if connectivityManager.syncStatus == .syncing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
            }
            Text(connectivityManager.syncStatus.rawValue)
                .font(.caption)
                .foregroundColor(connectivityManager.syncStatus.color)
            
            Spacer()
            
            Button {
                Task {
                    await connectivityManager.manualSync()
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(connectivityManager.syncStatus == .syncing ? .gray : .blue)
            }
            .disabled(connectivityManager.syncStatus == .syncing)
            
            if let lastSync = connectivityManager.lastSyncTime {
                Text("Last: \(lastSync.formatted(.relative(presentation: .numeric)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .alert("Sync Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            if case .error = connectivityManager.syncStatus {
                Text("Failed to sync with \(UIDevice.current.model == "iPhone" ? "Watch" : "iPhone"). Please ensure both devices are nearby and try again.")
            }
        }
    }
} 