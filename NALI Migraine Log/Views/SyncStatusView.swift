import SwiftUI
import WatchConnectivity

struct SyncStatusView: View {
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @StateObject private var settings = SettingsManager.shared
    
    var body: some View {
        HStack {
            if settings.useICloudSync {
                Label("Sync Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Label("Sync Disabled", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
        .padding(.horizontal)
    }
}

#Preview {
    SyncStatusView()
} 
