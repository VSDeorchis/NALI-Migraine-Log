import SwiftUI
import WatchConnectivity
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct WatchNewMigraineView: View {
    @EnvironmentObject var migraineStore: MigraineStore
    @Environment(\.dismiss) var dismiss
    
    @State private var painLevel = 5
    @State private var location: PainLocation = .frontal
    @State private var selectedTriggers: Set<Trigger> = []
    @State private var hasAura = false
    @State private var hasPhotophobia = false
    @State private var hasPhonophobia = false
    @State private var hasNausea = false
    @State private var hasVomiting = false
    @State private var hasWakeUpHeadache = false
    @State private var hasTinnitus = false
    @State private var selectedMedications: Set<Medication> = []
    @State private var currentSection = 0
    @State private var hasVertigo = false
    @State private var missedWork = false
    @State private var missedSchool = false
    @State private var missedEvents = false
    
    let sections = ["Pain", "Triggers", "Symptoms", "Quality of Life", "Medications"]
    
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
                    ForEach(PainLocation.allCases, id: \.self) { location in
                        Text(location.rawValue)
                            .tag(location)
                    }
                }
                .labelsHidden()
            }
            .tag(0)
            
            // Triggers Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Trigger.allCases, id: \.self) { trigger in
                        Toggle(trigger.rawValue, isOn: Binding(
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
                    ForEach(Medication.allCases, id: \.self) { medication in
                        Toggle(medication.rawValue, isOn: Binding(
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
            
            // Save Button
            Button("Save Entry") {
                // Ensure we don't save future dates
                let now = Date()
                let migraine = MigraineEvent(
                    startTime: min(now, Date()),  // Ensures start time isn't in future
                    painLevel: painLevel,
                    location: location,
                    triggers: selectedTriggers,
                    hasPhotophobia: hasPhotophobia,
                    hasPhonophobia: hasPhonophobia,
                    hasNausea: hasNausea,
                    hasVomiting: hasVomiting,
                    hasAura: hasAura,
                    hasWakeUpHeadache: hasWakeUpHeadache,
                    hasTinnitus: hasTinnitus,
                    hasVertigo: hasVertigo,
                    missedWork: missedWork,
                    missedSchool: missedSchool,
                    missedEvents: missedEvents,
                    medications: selectedMedications
                )
                migraineStore.addMigraine(migraine)
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .font(.title3)
            .tag(5)
        }
        .tabViewStyle(.page)
        .navigationTitle("New Entry")
    }
} 