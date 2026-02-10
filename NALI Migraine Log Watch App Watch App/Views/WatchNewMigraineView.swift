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
    private let triggers = ["Stress", "Lack of Sleep", "Dehydration", "Weather", "Menstrual", "Alcohol", "Caffeine", "Food", "Exercise", "Screen Time", "Other"]
    private let medications = ["Sumatriptan", "Rizatriptan", "Frovatriptan", "Naratriptan", "Ubrelvy", "Nurtec", "Tylenol", "Advil", "Excedrin", "Other"]
    
    private let totalSections = 7
    
    private var sectionTitle: String {
        switch currentSection {
        case 0: return "Pain & Location"
        case 1: return "Triggers"
        case 2: return "Symptoms"
        case 3: return "Impact"
        case 4: return "Medications"
        case 5: return "Notes"
        case 6: return "Save"
        default: return ""
        }
    }
    
    var body: some View {
        TabView(selection: $currentSection) {
            // Pain Details Section
            VStack(spacing: 8) {
                StepIndicator(current: 0, total: totalSections)
                
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
                    StepIndicator(current: 1, total: totalSections)
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
                    StepIndicator(current: 2, total: totalSections)
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
                    StepIndicator(current: 3, total: totalSections)
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
                    StepIndicator(current: 4, total: totalSections)
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
                    StepIndicator(current: 5, total: totalSections)
                    Text("Notes")
                        .font(.headline)
                    TextField("Add notes here", text: $notes)
                        .font(.body)
                }
                .padding()
            }
            .tag(5)
            
            // Save Button
            VStack(spacing: 12) {
                StepIndicator(current: 6, total: totalSections)
                
                Button("Save Entry") {
                    saveMigraine()
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .font(.title3)
            }
        }
        .tabViewStyle(.page)
        .navigationTitle("New Entry")
    }
    
}

// MARK: - Step Indicator for Watch
struct StepIndicator: View {
    let current: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

// MARK: - Save Logic
extension WatchNewMigraineView {
    func saveMigraine() {
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