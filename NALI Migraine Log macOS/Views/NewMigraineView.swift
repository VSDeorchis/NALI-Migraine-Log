import SwiftUI

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
    
    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]
    private let triggers = ["Stress", "Sleep Changes", "Weather", "Food", "Caffeine", "Alcohol", "Exercise", "Screen Time", "Hormonal", "Other"]
    private let medications = ["Sumatriptan", "Rizatriptan", "Frovatriptan", "Naratriptan", "Ubrelvy", "Nurtec", "Tylenol", "Advil", "Excedrin", "Other"]
    
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
        .frame(width: 600, height: 800)
        .background(Color(.windowBackgroundColor))
    }
} 