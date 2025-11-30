import SwiftUI
import CoreLocation

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingMigrationAlert = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingLocationAlert = false
    @State private var isBackfilling = false
    @State private var backfillProgress = 0
    @State private var backfillTotal = 0
    @State private var showingBackfillAlert = false
    @State private var backfillResult = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Data Sync")) {
                    Toggle("Enable iCloud Sync", isOn: $settings.useICloudSync)
                        .onChange(of: settings.useICloudSync) { newValue in
                            if newValue {
                                showingMigrationAlert = true
                            }
                        }
                    
                    Text("When enabled, your data will sync across all your devices using iCloud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Weather Tracking")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location Services")
                                .font(.body)
                            Text(locationStatusText)
                                .font(.caption)
                                .foregroundColor(locationStatusColor)
                        }
                        Spacer()
                        Button(locationButtonText) {
                            handleLocationPermission()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .disabled(locationManager.authorizationStatus == .notDetermined || 
                                 locationManager.authorizationStatus == .authorizedWhenInUse || 
                                 locationManager.authorizationStatus == .authorizedAlways)
                    }
                    
                    // Show information if notDetermined (iOS 26 "When I Share" mode - this is the new standard)
                    if locationManager.authorizationStatus == .notDetermined {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 14))
                                Text("Weather Tracking Enabled")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                            
                            Text("iOS 26 uses 'When I Share' as the standard location permission. Weather tracking works perfectly - you'll see a quick permission prompt when saving new entries.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("How it works:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "1.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("Save a new migraine entry")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "2.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("iOS asks 'Allow Headway to use your location?'")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "3.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("Tap 'Allow Once' - weather data is automatically fetched")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "4.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("Done! Repeat for each entry to track weather patterns")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.raised.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                    Text("Privacy First")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                Text("This is Apple's new privacy-first approach in iOS 26. You stay in control - approve location access only when you need it. Your weather data is still tracked accurately for migraine correlation analysis.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGreen).opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud.sun.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                            Text("How Weather Tracking Works")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Text("Your location is used to fetch historical weather data (temperature, barometric pressure, precipitation) for each migraine entry. This helps identify weather-related triggers like pressure changes, which are a common migraine cause.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("Your location data is only used to fetch weather and is never shared with third parties.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                
                Section(header: Text("Backfill Weather Data")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add Weather to Past Entries")
                                    .font(.body)
                                if isBackfilling {
                                    Text("Processing \(backfillProgress) of \(backfillTotal)...")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                } else {
                                    let count = viewModel.migraines.filter { !$0.hasWeatherData }.count
                                    if count > 0 {
                                        Text("\(count) entries without weather data")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("All entries have weather data")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            Spacer()
                            Button(action: {
                                Task {
                                    await performBackfill()
                                }
                            }) {
                                if isBackfilling {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Start")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isBackfilling || 
                                     viewModel.migraines.filter { !$0.hasWeatherData }.isEmpty ||
                                     locationManager.authorizationStatus == .notDetermined)
                        }
                        
                        // Information for iOS 26 "When I Share" mode
                        if locationManager.authorizationStatus == .notDetermined {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "hand.tap.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                    Text("Add Weather to Past Entries")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                
                                Text("With iOS 26's privacy-first approach, you can add weather data to past entries one at a time. This gives you full control over which entries get weather data.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("How to add weather to a past entry:")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("1.")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .frame(width: 20, alignment: .leading)
                                        Text("Tap any past migraine entry to open details")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("2.")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .frame(width: 20, alignment: .leading)
                                        Text("Scroll to Weather Data and tap 'Fetch Weather'")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("3.")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .frame(width: 20, alignment: .leading)
                                        Text("When iOS asks, tap 'Allow Once'")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("4.")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .frame(width: 20, alignment: .leading)
                                        Text("Weather data is added! Repeat for other entries")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .foregroundColor(.purple)
                                            .font(.system(size: 12))
                                        Text("Pro Tip")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                    }
                                    Text("Focus on entries where you remember severe symptoms or unusual circumstances. Weather correlation analysis works best with quality data from significant migraine events.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .background(Color(.systemBlue).opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Text("Fetches historical weather data for all migraine entries that don't have it. This uses your current location or the location where you logged the migraine.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Appearance") {
                    Picker("Theme", selection: $settings.colorScheme) {
                        ForEach(SettingsManager.ColorSchemePreference.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue).tag(scheme)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Data Migration", isPresented: $showingMigrationAlert) {
                Button("Cancel") {
                    settings.useICloudSync = false
                }
                Button("Migrate") {
                    Task {
                        await performMigration()
                    }
                }
            } message: {
                Text("Your data needs to be migrated to enable iCloud sync. This may take a few moments.")
            }
            .alert("Migration Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Location Services", isPresented: $showingLocationAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Location access is currently disabled. To enable weather tracking, please allow location access in Settings.")
            }
            .alert("Backfill Complete", isPresented: $showingBackfillAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backfillResult)
            }
            .onAppear {
                // Refresh location status when view appears
                print("⚙️ SettingsView appeared")
                print("⚙️ Current location status: \(locationManager.authorizationStatus.rawValue)")
                locationManager.refreshAuthorizationStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Refresh status when returning from Settings app
                print("⚙️ App entering foreground, refreshing location status")
                locationManager.refreshAuthorizationStatus()
            }
        }
    }
    
    // MARK: - Backfill Helper
    
    private func performBackfill() async {
        await MainActor.run {
            isBackfilling = true
            backfillProgress = 0
            backfillTotal = 0
        }
        
        let result = await viewModel.backfillWeatherData { current, total in
            Task { @MainActor in
                self.backfillProgress = current
                self.backfillTotal = total
            }
        }
        
        await MainActor.run {
            isBackfilling = false
            
            if result.success > 0 || result.failed > 0 {
                backfillResult = "Successfully fetched weather data for \(result.success) entries. \(result.failed) failed."
            } else {
                backfillResult = "No entries needed weather data."
            }
            showingBackfillAlert = true
        }
    }
    
    // MARK: - Location Helpers
    
    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Enabled"
        case .denied, .restricted:
            return "Disabled"
        case .notDetermined:
            // In iOS 25+, this likely means "When I Share" is set
            return "When Shared"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            // In iOS 25+, "When I Share" is acceptable for weather tracking
            return .blue
        @unknown default:
            return .gray
        }
    }
    
    private var locationButtonText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Enabled"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            // In iOS 25+, .notDetermined means "When I Share" which is functional
            return "Enabled"
        @unknown default:
            return "Settings"
        }
    }
    
    private func handleLocationPermission() {
        print("⚙️ handleLocationPermission called")
        print("⚙️ Current status: \(locationManager.authorizationStatus.rawValue)")
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Request permission - this will show the iOS dialog with all options
            print("⚙️ Status is notDetermined, requesting permission")
            locationManager.requestPermission()
        case .denied, .restricted:
            // Show alert to open Settings
            print("⚙️ Status is denied/restricted, showing alert")
            showingLocationAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, could show info
            print("⚙️ Status is already authorized")
            break
        @unknown default:
            print("⚙️ Unknown status")
            break
        }
    }
    
    private func performMigration() async {
        do {
            try await viewModel.migrateToDifferentStore()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
                settings.useICloudSync = false
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return SettingsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 