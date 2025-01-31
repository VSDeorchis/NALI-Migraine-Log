import SwiftUI

struct NewMigraineView: View {
    @ObservedObject var migraineStore: MigraineStore
    @Environment(\.dismiss) var dismiss
    
    var editingMigraine: MigraineEvent?
    
    @State private var startTime: Date
    @State private var endTime: Date?
    @State private var painLevel: Int
    @State private var location: PainLocation
    @State private var selectedTriggers: Set<Trigger>
    @State private var hasAura: Bool
    @State private var hasPhotophobia: Bool
    @State private var hasPhonophobia: Bool
    @State private var hasNausea: Bool
    @State private var hasVomiting: Bool
    @State private var hasWakeUpHeadache: Bool
    @State private var hasTinnitus: Bool
    @State private var selectedMedications: Set<Medication>
    @State private var notes: String
    @State private var hasVertigo: Bool
    @State private var missedWork: Bool
    @State private var missedSchool: Bool
    @State private var missedEvents: Bool
    
    init(migraineStore: MigraineStore, editingMigraine: MigraineEvent? = nil) {
        self.migraineStore = migraineStore
        self.editingMigraine = editingMigraine
        
        _startTime = State(initialValue: editingMigraine?.startTime ?? Date())
        _endTime = State(initialValue: editingMigraine?.endTime)
        _painLevel = State(initialValue: editingMigraine?.painLevel ?? 5)
        _location = State(initialValue: editingMigraine?.location ?? .frontal)
        _selectedTriggers = State(initialValue: editingMigraine?.triggers ?? [])
        _hasAura = State(initialValue: editingMigraine?.hasAura ?? false)
        _hasPhotophobia = State(initialValue: editingMigraine?.hasPhotophobia ?? false)
        _hasPhonophobia = State(initialValue: editingMigraine?.hasPhonophobia ?? false)
        _hasNausea = State(initialValue: editingMigraine?.hasNausea ?? false)
        _hasVomiting = State(initialValue: editingMigraine?.hasVomiting ?? false)
        _hasWakeUpHeadache = State(initialValue: editingMigraine?.hasWakeUpHeadache ?? false)
        _hasTinnitus = State(initialValue: editingMigraine?.hasTinnitus ?? false)
        _selectedMedications = State(initialValue: editingMigraine?.medications ?? [])
        _notes = State(initialValue: editingMigraine?.notes ?? "")
        _hasVertigo = State(initialValue: editingMigraine?.hasVertigo ?? false)
        _missedWork = State(initialValue: editingMigraine?.missedWork ?? false)
        _missedSchool = State(initialValue: editingMigraine?.missedSchool ?? false)
        _missedEvents = State(initialValue: editingMigraine?.missedEvents ?? false)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Time") {
                    DatePicker("Start Time", selection: $startTime, in: ...Date())
                    Toggle("Migraine Ended", isOn: Binding(
                        get: { endTime != nil },
                        set: { if $0 { endTime = Date() } else { endTime = nil } }
                    ))
                    if endTime != nil {
                        DatePicker("End Time", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = min($0, Date()) }
                        ), in: startTime...Date())
                    }
                }
                
                Section("Pain Details") {
                    Picker("Pain Level (1-10)", selection: $painLevel) {
                        ForEach(1...10, id: \.self) { level in
                            Text("\(level)").tag(level)
                        }
                    }
                    
                    Picker("Location", selection: $location) {
                        ForEach(PainLocation.allCases, id: \.self) { location in
                            Text(location.rawValue).tag(location)
                        }
                    }
                }
                
                Section("Triggers") {
                    ForEach(Array(Trigger.allCases), id: \.self) { trigger in
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
                
                Section("Symptoms") {
                    Toggle("Aura", isOn: $hasAura)
                    Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                    Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                    Toggle("Nausea", isOn: $hasNausea)
                    Toggle("Vomiting", isOn: $hasVomiting)
                    Toggle("Wake up Headache", isOn: $hasWakeUpHeadache)
                    Toggle("Tinnitus", isOn: $hasTinnitus)
                    Toggle("Vertigo/Dysequilibrium", isOn: $hasVertigo)
                }
                
                Section("Medications Used") {
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
                
                Section("Quality of Life Impact") {
                    Toggle("Missed Work", isOn: $missedWork)
                    Toggle("Missed School", isOn: $missedSchool)
                    Toggle("Missed Events", isOn: $missedEvents)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 100)
                }
            }
            .navigationTitle(editingMigraine != nil ? "Edit Migraine" : "New Migraine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let migraine = MigraineEvent(
                            id: editingMigraine?.id ?? UUID(),
                            startTime: startTime,
                            endTime: endTime,
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
                            medications: selectedMedications,
                            notes: notes.isEmpty ? nil : notes
                        )
                        
                        if editingMigraine != nil {
                            migraineStore.updateMigraine(migraine)
                        } else {
                            migraineStore.addMigraine(migraine)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NewMigraineView(migraineStore: MigraineStore())
} 