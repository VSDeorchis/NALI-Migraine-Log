import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            UnitsSettingsView()
                .tabItem {
                    Label("Units", systemImage: "ruler")
                }
            
            SyncSettingsView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            
            DataSettingsView()
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .frame(minWidth: 450, minHeight: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("defaultPainLocation") private var defaultPainLocation = "Frontal"
    
    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]
    
    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show Notifications", isOn: $showNotifications)
                    .toggleStyle(.switch)
            }
            
            Section("Defaults") {
                Picker("Default Pain Location", selection: $defaultPainLocation) {
                    ForEach(locations, id: \.self) { loc in
                        Text(loc).tag(loc)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Units Settings

struct UnitsSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section("Temperature") {
                Picker("Temperature Unit", selection: $settings.temperatureUnit) {
                    ForEach(SettingsManager.TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text("Used for weather data display in migraine entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Pressure") {
                Picker("Pressure Unit", selection: $settings.pressureUnit) {
                    ForEach(SettingsManager.PressureUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text("Used for barometric pressure display and change indicators")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sync Settings

struct SyncSettingsView: View {
    @AppStorage("useICloudSync") private var useICloudSync = true
    
    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Enable iCloud Sync", isOn: $useICloudSync)
                    .toggleStyle(.switch)
                Text("Sync your migraine data across all your devices using iCloud.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Data Settings

struct DataSettingsView: View {
    @State private var showingExportSuccess = false
    @State private var exportMessage = ""
    
    var body: some View {
        Form {
            Section("Export") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export All Data as CSV")
                            .font(.body)
                        Text("Export your complete migraine history to a CSV file for use in spreadsheets or sharing with your physician.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Export…") {
                        exportAllData()
                    }
                }
            }
            
            Section("Info") {
                let migraineCount = countMigraines()
                HStack {
                    Text("Total Entries")
                    Spacer()
                    Text("\(migraineCount)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Data Storage")
                    Spacer()
                    Text("Core Data + iCloud")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage)
        }
    }
    
    private func countMigraines() -> Int {
        let context = PersistenceController.shared.container.viewContext
        let vm = MigraineViewModel(context: context)
        vm.fetchMigraines()
        return vm.migraines.count
    }
    
    private func exportAllData() {
        let context = PersistenceController.shared.container.viewContext
        let vm = MigraineViewModel(context: context)
        vm.fetchMigraines()
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "Headway_Full_Export_\(dateStamp()).csv"
        panel.title = "Export All Migraine Data"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var csv = "Date,Time,End Time,Pain Level,Location,Duration (min),Triggers,Medications,Symptoms,Missed Work,Missed School,Missed Events,Notes\n"
            
            for m in vm.migraines {
                let date = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? ""
                let time = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
                let endTime = m.endTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
                let pain = "\(m.painLevel)"
                let location = m.location ?? ""
                var durationMin = ""
                if let s = m.startTime, let e = m.endTime {
                    durationMin = "\(Int(e.timeIntervalSince(s) / 60))"
                }
                let triggers = m.selectedTriggerNames.joined(separator: "; ")
                let medications = m.selectedMedicationNames.joined(separator: "; ")
                var symptoms: [String] = []
                if m.hasAura { symptoms.append("Aura") }
                if m.hasPhotophobia { symptoms.append("Photophobia") }
                if m.hasPhonophobia { symptoms.append("Phonophobia") }
                if m.hasNausea { symptoms.append("Nausea") }
                if m.hasVomiting { symptoms.append("Vomiting") }
                if m.hasWakeUpHeadache { symptoms.append("Wake-up Headache") }
                if m.hasTinnitus { symptoms.append("Tinnitus") }
                if m.hasVertigo { symptoms.append("Vertigo") }
                let notes = (m.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                
                csv += "\"\(date)\",\"\(time)\",\"\(endTime)\",\(pain),\"\(location)\",\(durationMin),\"\(triggers)\",\"\(medications)\",\"\(symptoms.joined(separator: "; "))\",\(m.missedWork),\(m.missedSchool),\(m.missedEvents),\"\(notes)\"\n"
            }
            
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                exportMessage = "Successfully exported \(vm.migraines.count) entries."
                showingExportSuccess = true
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
                showingExportSuccess = true
            }
        }
    }
    
    private func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
