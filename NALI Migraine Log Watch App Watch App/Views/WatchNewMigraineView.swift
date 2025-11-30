import SwiftUI
import CoreData

struct WatchNewMigraineView: View {
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
    @State private var currentSection = 0
    @State private var notes = ""
    
    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]
    private let triggers = ["Stress", "Sleep Changes", "Weather", "Food", "Caffeine", "Alcohol", "Exercise", "Screen Time", "Hormonal", "Other"]
    private let medications = ["Sumatriptan", "Rizatriptan", "Frovatriptan", "Naratriptan", "Ubrelvy", "Nurtec", "Tylenol", "Advil", "Excedrin", "Other"]
    
    var body: some View {
        TabView(selection: $currentSection) {
            // Pain Details Section
            VStack(spacing: 15) {
                Text("Pain Level: \(painLevel)")
                    .font(.headline)
                
                Picker("Pain Level", selection: $painLevel) {
                    ForEach(1...10, id: \.self) { level in
                        Text("\(level)")
                            .tag(level)
                    }
                }
                .labelsHidden()
                
                Picker("Location", selection: $location) {
                    ForEach(locations, id: \.self) { location in
                        Text(location)
                            .tag(location)
                    }
                }
                .labelsHidden()
            }
            .tag(0)
            
            // Triggers Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
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
                    }
                }
                .padding()
            }
            .tag(1)
            
            // Symptoms Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Aura", isOn: $hasAura)
                    Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                    Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                    Toggle("Nausea", isOn: $hasNausea)
                    Toggle("Vomiting", isOn: $hasVomiting)
                    Toggle("Wake up Headache", isOn: $hasWakeUpHeadache)
                    Toggle("Tinnitus", isOn: $hasTinnitus)
                    Toggle("Vertigo/Dysequilibrium", isOn: $hasVertigo)
                }
                .padding()
            }
            .tag(2)
            
            // Quality of Life Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Missed Work", isOn: $missedWork)
                    Toggle("Missed School", isOn: $missedSchool)
                    Toggle("Missed Events", isOn: $missedEvents)
                }
                .padding()
            }
            .tag(3)
            
            // Medications Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
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
                    }
                }
                .padding()
            }
            .tag(4)
            
            // Notes Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notes")
                        .font(.headline)
                    TextField("Add notes here", text: $notes)
                        .font(.body)
                }
                .padding()
            }
            .tag(5)
            
            // Save Button
            Button("Save Entry") {
                saveMigraine()
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .font(.title3)
        }
        .tabViewStyle(.page)
        .navigationTitle("New Entry")
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