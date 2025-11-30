import SwiftUI

struct SettingsView: View {
    @AppStorage("useICloudSync") private var useICloudSync = true
    @AppStorage("showNotifications") private var showNotifications = true
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            SyncSettingsView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("showNotifications") private var showNotifications = true
    
    var body: some View {
        Form {
            Toggle("Show Notifications", isOn: $showNotifications)
        }
        .padding()
    }
}

struct SyncSettingsView: View {
    @AppStorage("useICloudSync") private var useICloudSync = true
    
    var body: some View {
        Form {
            Toggle("Enable iCloud Sync", isOn: $useICloudSync)
            Text("Sync your data across all your devices using iCloud")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
} 