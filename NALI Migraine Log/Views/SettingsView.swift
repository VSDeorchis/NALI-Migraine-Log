import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

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
    
    // Export states
    @State private var showingExportWarning = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var exportFormat: ExportFormat = .csv
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
    }
    
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
                
                // MARK: - Export Data Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Export Migraine Data")
                                    .font(.body)
                                Text("\(viewModel.migraines.count) entries available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Button("Export") {
                                    showingExportWarning = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.migraines.isEmpty)
                            }
                        }
                        
                        Picker("Format", selection: $exportFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        // Privacy warning banner
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14))
                                Text("Privacy Notice")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                            
                            Text("Exported data will be unencrypted and may contain sensitive health information including migraine dates, symptoms, medications, and location data.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color(.systemOrange).opacity(0.1))
                        .cornerRadius(8)
                    }
                } header: {
                    Text("Data Export")
                } footer: {
                    Text("Export your migraine history to share with healthcare providers or for personal backup. CSV format works with Excel and Google Sheets.")
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
            .alert("Export Health Data", isPresented: $showingExportWarning) {
                Button("Cancel", role: .cancel) { }
                Button("I Understand, Export") {
                    Task {
                        await performExport()
                    }
                }
            } message: {
                Text("⚠️ IMPORTANT: Your exported data will NOT be encrypted.\n\nThis file will contain sensitive health information including:\n• Migraine dates and times\n• Pain levels and symptoms\n• Medications taken\n• Personal notes\n• Location/weather data\n\nOnly share this file with trusted healthcare providers. Delete the file after use to protect your privacy.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
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
    
    // MARK: - Export Helpers
    
    private func performExport() async {
        await MainActor.run {
            isExporting = true
        }
        
        do {
            let url: URL
            switch exportFormat {
            case .csv:
                url = try await exportToCSV()
            case .json:
                url = try await exportToJSON()
            }
            
            await MainActor.run {
                isExporting = false
                exportURL = url
                showingExportSheet = true
            }
        } catch {
            await MainActor.run {
                isExporting = false
                errorMessage = "Export failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func exportToCSV() async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        var csvContent = "Date,End Time,Pain Level,Location,Duration (hours),"
        csvContent += "Aura,Light Sensitivity,Sound Sensitivity,Nausea,Vomiting,Wake-up Headache,Tinnitus,Vertigo,"
        csvContent += "Stress,Lack of Sleep,Dehydration,Weather,Hormones,Alcohol,Caffeine,Food,Exercise,Screen Time,Other Trigger,"
        csvContent += "Ibuprofen,Excedrin,Tylenol,Sumatriptan,Rizatriptan,Naproxen,Frovatriptan,Naratriptan,Nurtec,Ubrelvy,Reyvow,Trudhesa,Elyxyb,Other Med,"
        csvContent += "Missed Work,Missed School,Missed Events,"
        csvContent += "Temperature (°F),Pressure (hPa),Pressure Change 24h,Weather Condition,"
        csvContent += "Notes\n"
        
        for migraine in viewModel.migraines.sorted(by: { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }) {
            var row: [String] = []
            
            // Date and time
            row.append(migraine.startTime.map { dateFormatter.string(from: $0) } ?? "")
            row.append(migraine.endTime.map { dateFormatter.string(from: $0) } ?? "")
            row.append("\(migraine.painLevel)")
            row.append(escapeCSV(migraine.location ?? ""))
            
            // Duration
            if let start = migraine.startTime, let end = migraine.endTime {
                let hours = end.timeIntervalSince(start) / 3600
                row.append(String(format: "%.1f", hours))
            } else {
                row.append("")
            }
            
            // Symptoms
            row.append(migraine.hasAura ? "Yes" : "No")
            row.append(migraine.hasPhotophobia ? "Yes" : "No")
            row.append(migraine.hasPhonophobia ? "Yes" : "No")
            row.append(migraine.hasNausea ? "Yes" : "No")
            row.append(migraine.hasVomiting ? "Yes" : "No")
            row.append(migraine.hasWakeUpHeadache ? "Yes" : "No")
            row.append(migraine.hasTinnitus ? "Yes" : "No")
            row.append(migraine.hasVertigo ? "Yes" : "No")
            
            // Triggers
            row.append(migraine.isTriggerStress ? "Yes" : "No")
            row.append(migraine.isTriggerLackOfSleep ? "Yes" : "No")
            row.append(migraine.isTriggerDehydration ? "Yes" : "No")
            row.append(migraine.isTriggerWeather ? "Yes" : "No")
            row.append(migraine.isTriggerHormones ? "Yes" : "No")
            row.append(migraine.isTriggerAlcohol ? "Yes" : "No")
            row.append(migraine.isTriggerCaffeine ? "Yes" : "No")
            row.append(migraine.isTriggerFood ? "Yes" : "No")
            row.append(migraine.isTriggerExercise ? "Yes" : "No")
            row.append(migraine.isTriggerScreenTime ? "Yes" : "No")
            row.append(migraine.isTriggerOther ? "Yes" : "No")
            
            // Medications
            row.append(migraine.tookIbuprofin ? "Yes" : "No")
            row.append(migraine.tookExcedrin ? "Yes" : "No")
            row.append(migraine.tookTylenol ? "Yes" : "No")
            row.append(migraine.tookSumatriptan ? "Yes" : "No")
            row.append(migraine.tookRizatriptan ? "Yes" : "No")
            row.append(migraine.tookNaproxen ? "Yes" : "No")
            row.append(migraine.tookFrovatriptan ? "Yes" : "No")
            row.append(migraine.tookNaratriptan ? "Yes" : "No")
            row.append(migraine.tookNurtec ? "Yes" : "No")
            row.append(migraine.tookUbrelvy ? "Yes" : "No")
            row.append(migraine.tookReyvow ? "Yes" : "No")
            row.append(migraine.tookTrudhesa ? "Yes" : "No")
            row.append(migraine.tookElyxyb ? "Yes" : "No")
            row.append(migraine.tookOther ? "Yes" : "No")
            
            // Impact
            row.append(migraine.missedWork ? "Yes" : "No")
            row.append(migraine.missedSchool ? "Yes" : "No")
            row.append(migraine.missedEvents ? "Yes" : "No")
            
            // Weather
            if migraine.hasWeatherData {
                row.append(String(format: "%.1f", migraine.weatherTemperature))
                row.append(String(format: "%.1f", migraine.weatherPressure))
                row.append(String(format: "%.1f", migraine.weatherPressureChange24h))
                row.append(WeatherService.weatherCondition(for: Int(migraine.weatherCode)))
            } else {
                row.append("")
                row.append("")
                row.append("")
                row.append("")
            }
            
            // Notes
            row.append(escapeCSV(migraine.notes ?? ""))
            
            csvContent += row.joined(separator: ",") + "\n"
        }
        
        let fileName = "Headway_Migraine_Export_\(fileDateFormatter.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    private func exportToJSON() async throws -> URL {
        let dateFormatter = ISO8601DateFormatter()
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        var exportData: [[String: Any]] = []
        
        for migraine in viewModel.migraines.sorted(by: { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }) {
            var entry: [String: Any] = [:]
            
            entry["id"] = migraine.id?.uuidString ?? ""
            entry["startTime"] = migraine.startTime.map { dateFormatter.string(from: $0) } ?? ""
            entry["endTime"] = migraine.endTime.map { dateFormatter.string(from: $0) } ?? NSNull()
            entry["painLevel"] = migraine.painLevel
            entry["location"] = migraine.location ?? ""
            
            // Symptoms
            entry["symptoms"] = [
                "aura": migraine.hasAura,
                "lightSensitivity": migraine.hasPhotophobia,
                "soundSensitivity": migraine.hasPhonophobia,
                "nausea": migraine.hasNausea,
                "vomiting": migraine.hasVomiting,
                "wakeUpHeadache": migraine.hasWakeUpHeadache,
                "tinnitus": migraine.hasTinnitus,
                "vertigo": migraine.hasVertigo
            ]
            
            // Triggers
            entry["triggers"] = [
                "stress": migraine.isTriggerStress,
                "lackOfSleep": migraine.isTriggerLackOfSleep,
                "dehydration": migraine.isTriggerDehydration,
                "weather": migraine.isTriggerWeather,
                "hormones": migraine.isTriggerHormones,
                "alcohol": migraine.isTriggerAlcohol,
                "caffeine": migraine.isTriggerCaffeine,
                "food": migraine.isTriggerFood,
                "exercise": migraine.isTriggerExercise,
                "screenTime": migraine.isTriggerScreenTime,
                "other": migraine.isTriggerOther
            ]
            
            // Medications
            entry["medications"] = [
                "ibuprofen": migraine.tookIbuprofin,
                "excedrin": migraine.tookExcedrin,
                "tylenol": migraine.tookTylenol,
                "sumatriptan": migraine.tookSumatriptan,
                "rizatriptan": migraine.tookRizatriptan,
                "naproxen": migraine.tookNaproxen,
                "frovatriptan": migraine.tookFrovatriptan,
                "naratriptan": migraine.tookNaratriptan,
                "nurtec": migraine.tookNurtec,
                "ubrelvy": migraine.tookUbrelvy,
                "reyvow": migraine.tookReyvow,
                "trudhesa": migraine.tookTrudhesa,
                "elyxyb": migraine.tookElyxyb,
                "other": migraine.tookOther
            ]
            
            // Impact
            entry["impact"] = [
                "missedWork": migraine.missedWork,
                "missedSchool": migraine.missedSchool,
                "missedEvents": migraine.missedEvents
            ]
            
            // Weather
            if migraine.hasWeatherData {
                entry["weather"] = [
                    "temperature": migraine.weatherTemperature,
                    "pressure": migraine.weatherPressure,
                    "pressureChange24h": migraine.weatherPressureChange24h,
                    "condition": WeatherService.weatherCondition(for: Int(migraine.weatherCode)),
                    "weatherCode": migraine.weatherCode
                ]
            }
            
            entry["notes"] = migraine.notes ?? ""
            
            exportData.append(entry)
        }
        
        let wrapper: [String: Any] = [
            "exportDate": dateFormatter.string(from: Date()),
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            "totalEntries": exportData.count,
            "privacyNotice": "This file contains unencrypted health data. Handle with care and delete after use.",
            "migraines": exportData
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])
        
        let fileName = "Headway_Migraine_Export_\(fileDateFormatter.string(from: Date())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try jsonData.write(to: tempURL)
        
        return tempURL
    }
    
    private func escapeCSV(_ string: String) -> String {
        var result = string
        // Replace newlines with spaces
        result = result.replacingOccurrences(of: "\n", with: " ")
        result = result.replacingOccurrences(of: "\r", with: " ")
        // If contains comma, quote, or special chars, wrap in quotes
        if result.contains(",") || result.contains("\"") || result.contains("\n") {
            result = result.replacingOccurrences(of: "\"", with: "\"\"")
            result = "\"\(result)\""
        }
        return result
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return SettingsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 