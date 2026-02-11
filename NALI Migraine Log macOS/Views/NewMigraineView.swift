import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

struct NewMigraineView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var startTime = Date()
    @State private var endTime: Date?
    @State private var painLevel: Int16 = 5
    @State private var location = "Frontal"
    @State private var hasAura = false
    @State private var hasPhotophobia = false
    @State private var hasPhonophobia = false
    @State private var hasNausea = false
    @State private var hasVomiting = false
    @State private var hasWakeUpHeadache = false
    @State private var hasTinnitus = false
    @State private var hasVertigo = false
    @State private var missedWork = false
    @State private var missedSchool = false
    @State private var missedEvents = false
    @State private var notes = ""
    @State private var selectedTriggers: Set<String> = []
    @State private var selectedMedications: Set<String> = []
    @ObservedObject private var healthKit = HealthKitManager.shared
    @State private var healthSnapshot: HealthKitSnapshot?
    @State private var isLoadingHealth = false
    
    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]
    private let triggers = ["Stress", "Sleep Changes", "Weather", "Food", "Caffeine", "Alcohol", "Exercise", "Screen Time", "Menstrual", "Other"]
    private let medications = ["Sumatriptan", "Rizatriptan", "Frovatriptan", "Naratriptan", "Ubrelvy", "Nurtec", "Symbravo", "Tylenol", "Advil", "Excedrin", "Other"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern header
            HStack {
                Text("New Migraine")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            Form {
                // Health Context Section (live HealthKit data)
                if healthKit.isAvailable {
                    healthContextSection
                }
                
                Section("Time") {
                    DatePicker("Start Time", selection: $startTime, in: ...Date())
                        .datePickerStyle(.field)
                    Toggle("Migraine Ended", isOn: Binding(
                        get: { endTime != nil },
                        set: { if $0 { endTime = Date() } else { endTime = nil } }
                    ))
                    .toggleStyle(.switch)
                    
                    if endTime != nil {
                        DatePicker("End Time", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = $0 }
                        ), in: startTime...Date())
                        .datePickerStyle(.field)
                    }
                }
                
                Section("Pain Details") {
                    Slider(value: Binding(
                        get: { Double(painLevel) },
                        set: { painLevel = Int16($0) }
                    ), in: 1...10, step: 1) {
                        Text("Pain Level: \(painLevel)")
                    }
                    
                    Picker("Location", selection: $location) {
                        ForEach(locations, id: \.self) { location in
                            Text(location).tag(location)
                        }
                    }
                }
                
                Section("Symptoms") {
                    ForEach([
                        ("Aura", $hasAura),
                        ("Light Sensitivity", $hasPhotophobia),
                        ("Sound Sensitivity", $hasPhonophobia),
                        ("Nausea", $hasNausea),
                        ("Vomiting", $hasVomiting),
                        ("Wake up Headache", $hasWakeUpHeadache),
                        ("Tinnitus", $hasTinnitus),
                        ("Vertigo", $hasVertigo)
                    ], id: \.0) { title, binding in
                        Toggle(title, isOn: binding)
                            .toggleStyle(.switch)
                    }
                }
                
                Section("Triggers") {
                    ForEach(triggers, id: \.self) { trigger in
                        Toggle(trigger, isOn: Binding(
                            get: { selectedTriggers.contains(trigger) },
                            set: { isSelected in
                                if isSelected {
                                    selectedTriggers.insert(trigger)
                                } else {
                                    selectedTriggers.remove(trigger)
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                }
                
                Section("Medications") {
                    ForEach(medications, id: \.self) { medication in
                        Toggle(medication, isOn: Binding(
                            get: { selectedMedications.contains(medication) },
                            set: { isSelected in
                                if isSelected {
                                    selectedMedications.insert(medication)
                                } else {
                                    selectedMedications.remove(medication)
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                }
                
                Section("Impact") {
                    Toggle("Missed Work", isOn: $missedWork)
                        .toggleStyle(.switch)
                    Toggle("Missed School", isOn: $missedSchool)
                        .toggleStyle(.switch)
                    Toggle("Missed Events", isOn: $missedEvents)
                        .toggleStyle(.switch)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                }
            }
            .formStyle(.grouped)
            
            // Modern footer with buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    viewModel.addMigraine(
                        startTime: startTime,
                        endTime: endTime,
                        painLevel: painLevel,
                        location: location,
                        notes: notes.isEmpty ? nil : notes,
                        triggers: Array(selectedTriggers),
                        medications: Array(selectedMedications),
                        hasAura: hasAura,
                        hasPhotophobia: hasPhotophobia,
                        hasPhonophobia: hasPhonophobia,
                        hasNausea: hasNausea,
                        hasVomiting: hasVomiting,
                        hasWakeUpHeadache: hasWakeUpHeadache,
                        hasTinnitus: hasTinnitus,
                        hasVertigo: hasVertigo,
                        missedWork: missedWork,
                        missedSchool: missedSchool,
                        missedEvents: missedEvents
                    )
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 600, idealHeight: 800)
        .background(Color(.windowBackgroundColor))
        .task {
            await loadHealthData()
        }
    }
    
    // MARK: - Health Context
    
    private func loadHealthData() async {
        guard healthKit.isAvailable else { return }
        isLoadingHealth = true
        if !healthKit.isAuthorized {
            await healthKit.requestAuthorization()
        }
        if healthKit.isAuthorized {
            healthSnapshot = await healthKit.fetchSnapshot()
        }
        isLoadingHealth = false
    }
    
    private var healthContextSection: some View {
        Section {
            if isLoadingHealth {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading health data...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if !healthKit.isAuthorized {
                HStack(spacing: 10) {
                    Image(systemName: "heart.slash")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HealthKit Not Authorized")
                            .font(.subheadline.weight(.medium))
                        Text("Enable in System Settings > Privacy to see health context")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let snapshot = healthSnapshot {
                macHealthDataGrid(snapshot)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "heart.text.square")
                        .foregroundColor(.secondary)
                    Text("No health data available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Label("Health Context", systemImage: "heart.fill")
                .foregroundColor(.pink)
        } footer: {
            if healthSnapshot != nil {
                Text("Live data from Apple Health — not stored with this entry.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func macHealthDataGrid(_ snapshot: HealthKitSnapshot) -> some View {
        HStack(spacing: 16) {
            if let sleep = snapshot.sleepHours {
                MacHealthTile(
                    icon: "bed.double.fill",
                    label: "Sleep",
                    value: String(format: "%.1f hrs", sleep),
                    color: sleep < 5 ? .red : (sleep < 6.5 ? .orange : .green)
                )
            }
            
            if let hrv = snapshot.hrv {
                MacHealthTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: String(format: "%.0f ms", hrv),
                    color: hrv < 20 ? .red : (hrv < 40 ? .orange : .green)
                )
            }
            
            if let rhr = snapshot.restingHeartRate {
                MacHealthTile(
                    icon: "heart.fill",
                    label: "Resting HR",
                    value: String(format: "%.0f bpm", rhr),
                    color: .red
                )
            }
            
            if let steps = snapshot.steps {
                MacHealthTile(
                    icon: "figure.walk",
                    label: "Steps",
                    value: steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)",
                    color: steps < 3000 ? .orange : (steps < 7000 ? .blue : .green)
                )
            }
            
            if let days = snapshot.daysSinceMenstruation {
                MacHealthTile(
                    icon: "calendar.circle.fill",
                    label: "Menstrual",
                    value: "\(days)d ago",
                    color: .purple
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - macOS Health Tile

struct MacHealthTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
    }
} 