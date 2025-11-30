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
        _editedTriggers = State(initialValue: Set((migraine.triggers as? NSSet)?.allObjects.compactMap { ($0 as? TriggerEntity)?.name } ?? []))
        _editedMedications = State(initialValue: Set((migraine.medications as? NSSet)?.allObjects.compactMap { ($0 as? MedicationEntity)?.name } ?? []))
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
                    selectedMedications: $editedMedications
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
                            Text("Location: \(migraine.location)")
                        }
                        
                        // Symptoms
                        DetailSection(title: "Symptoms") {
                            SymptomsGrid(migraine: migraine)
                        }
                        
                        // Triggers
                        if let triggers = migraine.triggers as? NSSet, triggers.count > 0 {
                            DetailSection(title: "Triggers") {
                                FlowLayout {
                                    ForEach(Array((migraine.triggers as? NSSet)?.allObjects ?? []).compactMap { $0 as? TriggerEntity }, id: \.id) { trigger in
                                        Text(trigger.name ?? "")
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        
                        // Medications
                        if let medications = migraine.medications as? NSSet, medications.count > 0 {
                            DetailSection(title: "Medications") {
                                FlowLayout {
                                    ForEach(Array((migraine.medications as? NSSet)?.allObjects ?? []).compactMap { $0 as? MedicationEntity }, id: \.id) { medication in
                                        Text(medication.name ?? "")
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
            medications: Array(editedMedications)
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
    
    var body: some View {
        Text("Symptoms data not available")
            .foregroundColor(.secondary)
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

// Add this struct for the edit mode view
struct EditMigraineView: View {
    @Binding var startTime: Date
    @Binding var endTime: Date?
    @Binding var painLevel: Int16
    @Binding var location: String
    @Binding var notes: String
    @Binding var selectedTriggers: Set<String>
    @Binding var selectedMedications: Set<String>
    
    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]
    private let triggers = ["Stress", "Sleep Changes", "Weather", "Food", "Caffeine", "Alcohol", "Exercise", "Screen Time", "Hormonal", "Other"]
    private let medications = ["Sumatriptan", "Rizatriptan", "Frovatriptan", "Naratriptan", "Ubrelvy", "Nurtec", "Tylenol", "Advil", "Excedrin", "Other"]
    
    var body: some View {
        Form {
            // Similar form layout as NewMigraineView but with bindings to edited values
            // ... (add form sections similar to NewMigraineView)
        }
        .formStyle(.grouped)
    }
} 
