import SwiftUI

struct MigraineDetailView: View {
    let migraine: MigraineEvent
    let viewModel: MigraineViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var editedStartTime: Date
    @State private var editedEndTime: Date?
    @State private var editedPainLevel: Int16
    @State private var editedLocation: String
    @State private var editedNotes: String
    @State private var editedTriggers: Set<String>
    @State private var editedMedications: Set<String>
    @State private var editedHasAura: Bool
    @State private var editedHasPhotophobia: Bool
    @State private var editedHasPhonophobia: Bool
    @State private var editedHasNausea: Bool
    @State private var editedHasVomiting: Bool
    @State private var editedHasWakeUpHeadache: Bool
    @State private var editedHasTinnitus: Bool
    @State private var editedHasVertigo: Bool
    @State private var editedMissedWork: Bool
    @State private var editedMissedSchool: Bool
    @State private var editedMissedEvents: Bool
    let isEditingOnAppear: Bool
    
    init(migraine: MigraineEvent, viewModel: MigraineViewModel, isEditingOnAppear: Bool = false) {
        self.migraine = migraine
        self.viewModel = viewModel
        self.isEditingOnAppear = isEditingOnAppear
        _isEditing = State(initialValue: isEditingOnAppear)
        _editedStartTime = State(initialValue: migraine.startTime ?? Date())
        _editedEndTime = State(initialValue: migraine.endTime)
        _editedPainLevel = State(initialValue: migraine.painLevel)
        _editedLocation = State(initialValue: migraine.location ?? "")
        _editedNotes = State(initialValue: migraine.notes ?? "")
        _editedTriggers = State(initialValue: Set(migraine.selectedTriggerNames))
        _editedMedications = State(initialValue: Set(migraine.selectedMedicationNames))
        _editedHasAura = State(initialValue: migraine.hasAura)
        _editedHasPhotophobia = State(initialValue: migraine.hasPhotophobia)
        _editedHasPhonophobia = State(initialValue: migraine.hasPhonophobia)
        _editedHasNausea = State(initialValue: migraine.hasNausea)
        _editedHasVomiting = State(initialValue: migraine.hasVomiting)
        _editedHasWakeUpHeadache = State(initialValue: migraine.hasWakeUpHeadache)
        _editedHasTinnitus = State(initialValue: migraine.hasTinnitus)
        _editedHasVertigo = State(initialValue: migraine.hasVertigo)
        _editedMissedWork = State(initialValue: migraine.missedWork)
        _editedMissedSchool = State(initialValue: migraine.missedSchool)
        _editedMissedEvents = State(initialValue: migraine.missedEvents)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Migraine Details")
                    .font(.title)
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                    }
                    Button("Save") {
                        saveChanges()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Edit") {
                        isEditing = true
                    }
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .padding()
            
            if isEditing {
                EditMigraineView(
                    startTime: $editedStartTime,
                    endTime: $editedEndTime,
                    painLevel: $editedPainLevel,
                    location: $editedLocation,
                    notes: $editedNotes,
                    selectedTriggers: $editedTriggers,
                    selectedMedications: $editedMedications,
                    hasAura: $editedHasAura,
                    hasPhotophobia: $editedHasPhotophobia,
                    hasPhonophobia: $editedHasPhonophobia,
                    hasNausea: $editedHasNausea,
                    hasVomiting: $editedHasVomiting,
                    hasWakeUpHeadache: $editedHasWakeUpHeadache,
                    hasTinnitus: $editedHasTinnitus,
                    hasVertigo: $editedHasVertigo,
                    missedWork: $editedMissedWork,
                    missedSchool: $editedMissedSchool,
                    missedEvents: $editedMissedEvents
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Time Details
                        Group {
                            DetailSection(title: "Time") {
                                Text("Start: \(migraine.startTime!, style: .date) \(migraine.startTime!, style: .time)")
                                if let endTime = migraine.endTime {
                                    Text("End: \(endTime, style: .date) \(endTime, style: .time)")
                                    Text("Duration: \(duration)")
                                } else {
                                    Text("Status: Ongoing")
                                }
                            }
                        }
                        
                        // Pain Details
                        DetailSection(title: "Pain Details") {
                            Text("Pain Level: \(migraine.painLevel)")
                                .foregroundColor(painLevelColor(migraine.painLevel))
                            Text("Location: \(migraine.location ?? "Not specified")")
                        }
                        
                        // Symptoms
                        DetailSection(title: "Symptoms") {
                            SymptomsGrid(migraine: migraine)
                        }
                        
                        // Triggers
                        if !migraine.selectedTriggerNames.isEmpty {
                            DetailSection(title: "Triggers") {
                                FlowLayout {
                                    ForEach(migraine.selectedTriggerNames, id: \.self) { trigger in
                                        Text(trigger)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        
                        // Medications
                        if !migraine.selectedMedicationNames.isEmpty {
                            DetailSection(title: "Medications") {
                                FlowLayout {
                                    ForEach(migraine.selectedMedicationNames, id: \.self) { medication in
                                        Text(medication)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        
                        // Impact
                        DetailSection(title: "Impact") {
                            if migraine.missedWork { Text("Missed Work") }
                            if migraine.missedSchool { Text("Missed School") }
                            if migraine.missedEvents { Text("Missed Events") }
                        }
                        
                        // Notes
                        if let notes = migraine.notes, !notes.isEmpty {
                            DetailSection(title: "Notes") {
                                Text(notes)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private var duration: String {
        guard let endTime = migraine.endTime else { return "Ongoing" }
        let duration = endTime.timeIntervalSince(migraine.startTime!)
        let hours = Int(duration) / 3600
        let minutes = Int(duration.truncatingRemainder(dividingBy: 3600)) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func painLevelColor(_ level: Int16) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    private func saveChanges() {
        viewModel.updateMigraine(
            migraine,
            startTime: editedStartTime,
            endTime: editedEndTime,
            painLevel: editedPainLevel,
            location: editedLocation,
            notes: editedNotes.isEmpty ? nil : editedNotes,
            triggers: Array(editedTriggers),
            medications: Array(editedMedications),
            hasAura: editedHasAura,
            hasPhotophobia: editedHasPhotophobia,
            hasPhonophobia: editedHasPhonophobia,
            hasNausea: editedHasNausea,
            hasVomiting: editedHasVomiting,
            hasWakeUpHeadache: editedHasWakeUpHeadache,
            hasTinnitus: editedHasTinnitus,
            hasVertigo: editedHasVertigo,
            missedWork: editedMissedWork,
            missedSchool: editedMissedSchool,
            missedEvents: editedMissedEvents
        )
        isEditing = false
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
                .padding(.leading)
        }
    }
}

struct SymptomsGrid: View {
    let migraine: MigraineEvent
    
    private var activeSymptoms: [(String, String)] {
        var symptoms: [(String, String)] = []
        if migraine.hasAura { symptoms.append(("Aura", "eye.circle")) }
        if migraine.hasPhotophobia { symptoms.append(("Photophobia", "sun.max")) }
        if migraine.hasPhonophobia { symptoms.append(("Phonophobia", "ear")) }
        if migraine.hasNausea { symptoms.append(("Nausea", "stomach")) }
        if migraine.hasVomiting { symptoms.append(("Vomiting", "exclamationmark.triangle")) }
        if migraine.hasWakeUpHeadache { symptoms.append(("Wake Up Headache", "bed.double")) }
        if migraine.hasTinnitus { symptoms.append(("Tinnitus", "waveform")) }
        if migraine.hasVertigo { symptoms.append(("Vertigo", "arrow.triangle.2.circlepath")) }
        return symptoms
    }
    
    var body: some View {
        if activeSymptoms.isEmpty {
            Text("No symptoms recorded")
                .foregroundColor(.secondary)
        } else {
            FlowLayout {
                ForEach(activeSymptoms, id: \.0) { name, icon in
                    Label(name, systemImage: icon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layoutHelper(sizes: sizes, proposal: proposal).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = layoutHelper(sizes: sizes, proposal: proposal).positions
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: positions[index], proposal: .unspecified)
        }
    }
    
    private func layoutHelper(sizes: [CGSize], proposal: ProposedViewSize) -> (positions: [CGPoint], size: CGSize) {
        let spacing: CGFloat = 8
        let width = proposal.width ?? .infinity
        
        var currentPosition = CGPoint.zero
        var positions: [CGPoint] = []
        var maxHeight: CGFloat = 0
        
        for size in sizes {
            if currentPosition.x + size.width > width {
                currentPosition.x = 0
                currentPosition.y += maxHeight + spacing
                maxHeight = 0
            }
            
            positions.append(currentPosition)
            currentPosition.x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
        
        return (positions, CGSize(width: width, height: currentPosition.y + maxHeight))
    }
}

struct EditMigraineView: View {
    @Binding var startTime: Date
    @Binding var endTime: Date?
    @Binding var painLevel: Int16
    @Binding var location: String
    @Binding var notes: String
    @Binding var selectedTriggers: Set<String>
    @Binding var selectedMedications: Set<String>
    @Binding var hasAura: Bool
    @Binding var hasPhotophobia: Bool
    @Binding var hasPhonophobia: Bool
    @Binding var hasNausea: Bool
    @Binding var hasVomiting: Bool
    @Binding var hasWakeUpHeadache: Bool
    @Binding var hasTinnitus: Bool
    @Binding var hasVertigo: Bool
    @Binding var missedWork: Bool
    @Binding var missedSchool: Bool
    @Binding var missedEvents: Bool
    
    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]
    private let triggers = ["Stress", "Sleep Changes", "Weather", "Food", "Caffeine", "Alcohol", "Exercise", "Screen Time", "Hormonal", "Other"]
    private let medications = ["Sumatriptan", "Rizatriptan", "Frovatriptan", "Naratriptan", "Ubrelvy", "Nurtec", "Tylenol", "Advil", "Excedrin", "Other"]
    
    var body: some View {
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
                    ForEach(locations, id: \.self) { loc in
                        Text(loc).tag(loc)
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
    }
}
