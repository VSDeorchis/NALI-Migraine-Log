import SwiftUI
import CoreLocation
import UniformTypeIdentifiers
import PDFKit

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
        case pdf = "PDF"
    }
    
    var body: some View {
        NavigationView {
            Form {
                dataSyncSection
                weatherTrackingSection
                backfillSection
                appearanceSection
                exportSection
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
    
    // MARK: - Form Sections
    
    private var dataSyncSection: some View {
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
    }
    
    private var weatherTrackingSection: some View {
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
            
            if locationManager.authorizationStatus == .notDetermined {
                iOS26LocationInfoView()
            }
            
            WeatherTrackingInfoView()
        }
    }
    
    private var backfillSection: some View {
        Section(header: Text("Backfill Weather Data")) {
            VStack(alignment: .leading, spacing: 12) {
                backfillHeaderView
                
                if locationManager.authorizationStatus == .notDetermined {
                    iOS26BackfillInfoView()
                } else {
                    Text("Fetches historical weather data for all migraine entries that don't have it. This uses your current location or the location where you logged the migraine.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var backfillHeaderView: some View {
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
    }
    
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.colorScheme) {
                ForEach(SettingsManager.ColorSchemePreference.allCases, id: \.self) { scheme in
                    Text(scheme.rawValue).tag(scheme)
                }
            }
        }
    }
    
    private var exportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                exportHeaderView
                
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                
                ExportPrivacyWarningView()
            }
        } header: {
            Text("Data Export")
        } footer: {
            Text("Export your migraine history to share with healthcare providers. PDF creates a formatted report; CSV works with Excel and Google Sheets.")
        }
    }
    
    private var exportHeaderView: some View {
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
            case .pdf:
                url = try await exportToPDF()
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
    
    private func exportToPDF() async throws -> URL {
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let sortedMigraines = viewModel.migraines.sorted { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }
        
        // Create PDF renderer
        let pageWidth: CGFloat = 612  // US Letter width in points
        let pageHeight: CGFloat = 792 // US Letter height in points
        let margin: CGFloat = 50
        let contentWidth = pageWidth - (margin * 2)
        
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        
        let data = pdfRenderer.pdfData { context in
            var currentY: CGFloat = margin
            var pageNumber = 1
            
            // Helper to start a new page
            func startNewPage() {
                context.beginPage()
                currentY = margin
                pageNumber += 1
            }
            
            // Helper to check if we need a new page
            func checkPageBreak(neededHeight: CGFloat) {
                if currentY + neededHeight > pageHeight - margin {
                    startNewPage()
                }
            }
            
            // Text styles
            let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
            let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let captionFont = UIFont.systemFont(ofSize: 9)
            
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            
            let leftStyle = NSMutableParagraphStyle()
            leftStyle.alignment = .left
            
            // Start first page
            context.beginPage()
            
            // Title
            let title = "Migraine History Report"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: titleStyle
            ]
            title.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: titleAttrs)
            currentY += 40
            
            // Privacy warning
            let warningAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: titleStyle
            ]
            let warning = "⚠️ CONFIDENTIAL HEALTH INFORMATION - Handle with care and delete after use"
            warning.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: warningAttrs)
            currentY += 30
            
            // Export info
            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.gray,
                .paragraphStyle: titleStyle
            ]
            let exportInfo = "Generated: \(dateFormatter.string(from: Date())) • Total Entries: \(sortedMigraines.count)"
            exportInfo.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 15), withAttributes: infoAttrs)
            currentY += 30
            
            // Divider
            UIColor.lightGray.setStroke()
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: margin, y: currentY))
            dividerPath.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
            dividerPath.lineWidth = 0.5
            dividerPath.stroke()
            currentY += 20
            
            // Summary section
            let summaryHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: leftStyle
            ]
            "SUMMARY".draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: summaryHeaderAttrs)
            currentY += 25
            
            // Calculate summary stats
            let totalMigraines = sortedMigraines.count
            let avgPain = totalMigraines > 0 ? Double(sortedMigraines.reduce(0) { $0 + Int($1.painLevel) }) / Double(totalMigraines) : 0
            let withAura = sortedMigraines.filter { $0.hasAura }.count
            let missedWorkCount = sortedMigraines.filter { $0.missedWork }.count
            
            let summaryAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: leftStyle
            ]
            
            let summaryText = """
            • Total migraine episodes recorded: \(totalMigraines)
            • Average pain level: \(String(format: "%.1f", avgPain))/10
            • Episodes with aura: \(withAura) (\(totalMigraines > 0 ? Int(Double(withAura)/Double(totalMigraines)*100) : 0)%)
            • Missed work/school events: \(missedWorkCount)
            """
            summaryText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 80), withAttributes: summaryAttrs)
            currentY += 90
            
            // Divider
            UIColor.lightGray.setStroke()
            let divider2 = UIBezierPath()
            divider2.move(to: CGPoint(x: margin, y: currentY))
            divider2.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
            divider2.lineWidth = 0.5
            divider2.stroke()
            currentY += 20
            
            // Individual entries
            "DETAILED MIGRAINE LOG".draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: summaryHeaderAttrs)
            currentY += 30
            
            for (index, migraine) in sortedMigraines.enumerated() {
                // Estimate height needed for this entry
                let entryHeight: CGFloat = 140
                checkPageBreak(neededHeight: entryHeight)
                
                // Entry header with date and pain level
                let dateStr = migraine.startTime.map { dateFormatter.string(from: $0) } ?? "Unknown date"
                let entryHeader = "#\(index + 1) - \(dateStr)"
                let entryHeaderAttrs: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: leftStyle
                ]
                entryHeader.draw(in: CGRect(x: margin, y: currentY, width: contentWidth - 80, height: 18), withAttributes: entryHeaderAttrs)
                
                // Pain level badge
                let painText = "Pain: \(migraine.painLevel)/10"
                let painColor: UIColor = migraine.painLevel >= 7 ? .systemRed : (migraine.painLevel >= 4 ? .systemOrange : .systemGreen)
                let painAttrs: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: painColor
                ]
                painText.draw(in: CGRect(x: pageWidth - margin - 70, y: currentY, width: 70, height: 18), withAttributes: painAttrs)
                currentY += 22
                
                // Location
                if let location = migraine.location, !location.isEmpty {
                    let locationText = "📍 \(location)"
                    locationText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 15), withAttributes: summaryAttrs)
                    currentY += 18
                }
                
                // Symptoms
                var symptoms: [String] = []
                if migraine.hasAura { symptoms.append("Aura") }
                if migraine.hasPhotophobia { symptoms.append("Light sensitivity") }
                if migraine.hasPhonophobia { symptoms.append("Sound sensitivity") }
                if migraine.hasNausea { symptoms.append("Nausea") }
                if migraine.hasVomiting { symptoms.append("Vomiting") }
                if migraine.hasVertigo { symptoms.append("Vertigo") }
                if migraine.hasTinnitus { symptoms.append("Tinnitus") }
                if migraine.hasWakeUpHeadache { symptoms.append("Wake-up headache") }
                
                if !symptoms.isEmpty {
                    let symptomsText = "Symptoms: \(symptoms.joined(separator: ", "))"
                    symptomsText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: summaryAttrs)
                    currentY += symptoms.count > 4 ? 35 : 20
                }
                
                // Triggers
                var triggers: [String] = []
                if migraine.isTriggerStress { triggers.append("Stress") }
                if migraine.isTriggerLackOfSleep { triggers.append("Lack of sleep") }
                if migraine.isTriggerDehydration { triggers.append("Dehydration") }
                if migraine.isTriggerWeather { triggers.append("Weather") }
                if migraine.isTriggerHormones { triggers.append("Hormones") }
                if migraine.isTriggerAlcohol { triggers.append("Alcohol") }
                if migraine.isTriggerCaffeine { triggers.append("Caffeine") }
                if migraine.isTriggerFood { triggers.append("Food") }
                if migraine.isTriggerExercise { triggers.append("Exercise") }
                if migraine.isTriggerScreenTime { triggers.append("Screen time") }
                if migraine.isTriggerOther { triggers.append("Other") }
                
                if !triggers.isEmpty {
                    let triggersText = "Triggers: \(triggers.joined(separator: ", "))"
                    triggersText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: summaryAttrs)
                    currentY += triggers.count > 4 ? 35 : 20
                }
                
                // Medications
                var meds: [String] = []
                if migraine.tookIbuprofin { meds.append("Ibuprofen") }
                if migraine.tookExcedrin { meds.append("Excedrin") }
                if migraine.tookTylenol { meds.append("Tylenol") }
                if migraine.tookSumatriptan { meds.append("Sumatriptan") }
                if migraine.tookRizatriptan { meds.append("Rizatriptan") }
                if migraine.tookNaproxen { meds.append("Naproxen") }
                if migraine.tookFrovatriptan { meds.append("Frovatriptan") }
                if migraine.tookNaratriptan { meds.append("Naratriptan") }
                if migraine.tookNurtec { meds.append("Nurtec") }
                if migraine.tookUbrelvy { meds.append("Ubrelvy") }
                if migraine.tookReyvow { meds.append("Reyvow") }
                if migraine.tookTrudhesa { meds.append("Trudhesa") }
                if migraine.tookElyxyb { meds.append("Elyxyb") }
                if migraine.tookOther { meds.append("Other") }
                
                if !meds.isEmpty {
                    let medsText = "Medications: \(meds.joined(separator: ", "))"
                    medsText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 30), withAttributes: summaryAttrs)
                    currentY += meds.count > 4 ? 35 : 20
                }
                
                // Weather data
                if migraine.hasWeatherData {
                    let tempF = migraine.weatherTemperature * 9/5 + 32
                    let pressureChange = migraine.weatherPressureChange24h
                    let changeIndicator = pressureChange > 2 ? "↑" : (pressureChange < -2 ? "↓" : "→")
                    let weatherText = "Weather: \(String(format: "%.0f", tempF))°F, \(String(format: "%.1f", migraine.weatherPressure)) hPa (\(changeIndicator)\(String(format: "%.1f", abs(pressureChange))) hPa/24h)"
                    weatherText.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 15), withAttributes: summaryAttrs)
                    currentY += 20
                }
                
                // Notes
                if let notes = migraine.notes, !notes.isEmpty {
                    let notesText = "Notes: \(notes)"
                    let notesRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 40)
                    notesText.draw(in: notesRect, withAttributes: summaryAttrs)
                    currentY += 45
                }
                
                // Entry divider
                currentY += 5
                UIColor(white: 0.9, alpha: 1).setStroke()
                let entryDivider = UIBezierPath()
                entryDivider.move(to: CGPoint(x: margin + 20, y: currentY))
                entryDivider.addLine(to: CGPoint(x: pageWidth - margin - 20, y: currentY))
                entryDivider.lineWidth = 0.3
                entryDivider.stroke()
                currentY += 15
            }
            
            // Footer on last page
            checkPageBreak(neededHeight: 50)
            currentY = pageHeight - margin - 30
            
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: captionFont,
                .foregroundColor: UIColor.gray,
                .paragraphStyle: titleStyle
            ]
            let footer = "Generated by Headway Migraine Log • This document contains sensitive health information"
            footer.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 20), withAttributes: footerAttrs)
        }
        
        let fileName = "Headway_Migraine_Report_\(fileDateFormatter.string(from: Date())).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)
        
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

// MARK: - Helper Views

struct iOS26LocationInfoView: View {
    var body: some View {
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
                
                LocationStepRow(step: 1, text: "Save a new migraine entry")
                LocationStepRow(step: 2, text: "iOS asks 'Allow Headway to use your location?'")
                LocationStepRow(step: 3, text: "Tap 'Allow Once' - weather data is automatically fetched")
                LocationStepRow(step: 4, text: "Done! Repeat for each entry to track weather patterns")
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
                Text("This is Apple's new privacy-first approach in iOS 26. You stay in control - approve location access only when you need it.")
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
}

struct LocationStepRow: View {
    let step: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "\(step).circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WeatherTrackingInfoView: View {
    var body: some View {
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
}

struct iOS26BackfillInfoView: View {
    var body: some View {
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
                
                BackfillStepRow(step: "1", text: "Tap any past migraine entry to open details")
                BackfillStepRow(step: "2", text: "Scroll to Weather Data and tap 'Fetch Weather'")
                BackfillStepRow(step: "3", text: "When iOS asks, tap 'Allow Once'")
                BackfillStepRow(step: "4", text: "Weather data is added! Repeat for other entries")
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
    }
}

struct BackfillStepRow: View {
    let step: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(step).")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ExportPrivacyWarningView: View {
    var body: some View {
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
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return SettingsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 