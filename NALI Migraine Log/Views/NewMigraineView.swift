import SwiftUI

struct NewMigraineView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var startTime = Date()
    @State private var endTime: Date?
    @State private var painLevel: Int16 = 5
    @State private var location = "Frontal"
    @State private var selectedTriggers: Set<String> = []
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
    @State private var selectedMedications: Set<String> = []
    @State private var notes = ""
    
    private let medications = [
        "Tylenol (acetaminophen)",
        "Ibuprofen",
        "Naproxen",
        "Excedrin",
        "Ubrelvy (ubrogepant)",
        "Nurtec (rimegepant)",
        "Sumatriptan",
        "Rizatriptan",
        "Eletriptan",
        "Naratriptan",
        "Frovatriptan",
        "Reyvow (lasmiditan)",
        "Trudhesa (dihydroergotamine)",
        "Elyxyb",
        "Other"
    ]
    
    private var locationPicker: some View {
        Picker("Location", selection: $location) {
            ForEach(viewModel.locations, id: \.self) { location in
                Text(location).tag(location)
            }
        }
    }
    
    private var triggersSection: some View {
        Section {
            ForEach(viewModel.triggers, id: \.self) { trigger in
                let isSelected = selectedTriggers.contains(trigger)
                Toggle(trigger, isOn: Binding(
                    get: { isSelected },
                    set: { newValue in
                        withAnimation {
                            if newValue {
                                selectedTriggers.insert(trigger)
                            } else {
                                selectedTriggers.remove(trigger)
                            }
                        }
                    }
                ))
            }
        } header: {
            SectionHeader(
                title: "TRIGGERS",
                systemImage: "bolt.fill",
                color: .blue
            )
        }
        .listRowBackground(Color(.systemGray6).opacity(0.5))
    }
    
    private var medicationsSection: some View {
        Section {
            ForEach(medications, id: \.self) { medication in
                let isSelected = selectedMedications.contains(medication)
                Toggle(medication, isOn: Binding(
                    get: { isSelected },
                    set: { newValue in
                        withAnimation {
                            if newValue {
                                selectedMedications.insert(medication)
                            } else {
                                selectedMedications.remove(medication)
                            }
                        }
                    }
                ))
            }
        } header: {
            SectionHeader(
                title: "MEDICATIONS",
                systemImage: "pill.fill",
                color: .purple
            )
        }
        .listRowBackground(Color(.systemGray6).opacity(0.5))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Weather fetch status banner
                if viewModel.weatherFetchStatus != .idle {
                    weatherStatusBanner
                }
                
                Form {
                    // Pain Details Section
                    Section {
                    DatePicker("Start Time", selection: $startTime)
                    Toggle("Add End Time", isOn: Binding(
                        get: { endTime != nil },
                        set: { newValue in
                            if newValue {
                                endTime = endTime ?? startTime
                            } else {
                                endTime = nil
                            }
                        }
                    ))
                    if endTime != nil {
                        DatePicker("End Time", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                    PainSlider(value: $painLevel)
                    locationPicker
                } header: {
                    SectionHeader(
                        title: "PAIN DETAILS",
                        systemImage: "thermometer",
                        color: .blue
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Primary Symptoms Section
                Section {
                    Toggle("Aura", isOn: $hasAura)
                    Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                    Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                    Toggle("Nausea", isOn: $hasNausea)
                    Toggle("Vomiting", isOn: $hasVomiting)
                } header: {
                    SectionHeader(
                        title: "PRIMARY SYMPTOMS",
                        systemImage: "exclamationmark.circle",
                        color: .purple
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Additional Symptoms Section
                Section {
                    Toggle("Wake-up Headache", isOn: $hasWakeUpHeadache)
                    Toggle("Tinnitus", isOn: $hasTinnitus)
                    Toggle("Vertigo", isOn: $hasVertigo)
                } header: {
                    SectionHeader(
                        title: "ADDITIONAL SYMPTOMS",
                        systemImage: "plus.circle",
                        color: .purple
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Triggers Section
                triggersSection
                
                // Medications Section
                medicationsSection
                
                // Impact Section
                Section {
                    Toggle("Missed Work", isOn: $missedWork)
                    Toggle("Missed School", isOn: $missedSchool)
                    Toggle("Missed Events", isOn: $missedEvents)
                } header: {
                    SectionHeader(
                        title: "IMPACT",
                        systemImage: "chart.bar.fill",
                        color: .red
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Notes Section
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                } header: {
                    SectionHeader(
                        title: "NOTES",
                        systemImage: "note.text",
                        color: .red
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.2))
                }
                .formStyle(.grouped)
                .navigationTitle("New Migraine")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    NSLog("🟣 [NewMigraineView] ===== VIEW APPEARED =====")
                    NSLog("🟣 [NewMigraineView] NewMigraineView is now visible")
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            NSLog("🔵 [NewMigraineView] Save button tapped")
                            Task { @MainActor in
                                NSLog("🔵 [NewMigraineView] Inside Task, calling addMigraine...")
                                let result = await viewModel.addMigraine(
                                    startTime: startTime,
                                    endTime: endTime,
                                    painLevel: painLevel,
                                    location: location,
                                    triggers: Array(selectedTriggers),
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
                                    missedEvents: missedEvents,
                                    medications: Array(selectedMedications),
                                    notes: notes.isEmpty ? nil : notes
                                )
                                
                                NSLog("🔵 [NewMigraineView] addMigraine returned: %@", result != nil ? "SUCCESS" : "FAILED")
                                
                                if result != nil {
                                    NSLog("🔵 [NewMigraineView] Save succeeded, about to dismiss")
                                    // Dismiss immediately without delay
                                    dismiss()
                                    NSLog("🔵 [NewMigraineView] dismiss() called successfully")
                                } else {
                                    NSLog("🔴 [NewMigraineView] Save failed, not dismissing")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var weatherStatusBanner: some View {
        Group {
            switch viewModel.weatherFetchStatus {
            case .idle:
                EmptyView()
            case .fetching:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Fetching weather data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
            case .success:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Weather data added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Weather data unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            case .locationDenied:
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundColor(.orange)
                    Text("Enable location for weather data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.weatherFetchStatus)
    }
    
    private func saveMigraine() {
        Task {
            await viewModel.addMigraine(
                startTime: startTime,
                endTime: endTime,
                painLevel: painLevel,
                location: location,
                triggers: Array(selectedTriggers),
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
                missedEvents: missedEvents,
                medications: Array(selectedMedications),
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        }
    }
}

// Add custom section header style
struct SectionHeader: View {
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(color)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return NewMigraineView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 