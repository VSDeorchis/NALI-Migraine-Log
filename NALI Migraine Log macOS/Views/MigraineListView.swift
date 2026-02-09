import SwiftUI

struct MigraineListView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var searchText = ""
    @State private var selectedMigraine: MigraineEvent?
    @State private var isEditing = false
    
    var filteredMigraines: [MigraineEvent] {
        if searchText.isEmpty {
            return viewModel.migraines
        } else {
            return viewModel.migraines.filter { migraine in
                let notesMatch = migraine.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let medicationsMatch = migraine.selectedMedicationNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                let triggersMatch = migraine.selectedTriggerNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                let locationMatch = migraine.location?.localizedCaseInsensitiveContains(searchText) ?? false
                return notesMatch || medicationsMatch || triggersMatch || locationMatch
            }
        }
    }
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText)
                .padding()
            
            List(selection: $selectedMigraine) {
                ForEach(filteredMigraines, id: \.id) { migraine in
                    MigraineRowView(migraine: migraine)
                        .tag(migraine)
                        .contextMenu {
                            Button {
                                selectedMigraine = migraine
                                isEditing = false
                            } label: {
                                Label("View Details", systemImage: "eye")
                            }
                            
                            Button {
                                selectedMigraine = migraine
                                isEditing = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                viewModel.deleteMigraine(migraine)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Migraine Log")
        .task {  // Use task instead of onAppear for better reliability
            viewModel.fetchMigraines()
        }
        .sheet(item: $selectedMigraine) { migraine in
            MigraineDetailView(migraine: migraine, viewModel: viewModel, isEditingOnAppear: isEditing)
        }
        .onChange(of: selectedMigraine) { _ in
            if selectedMigraine == nil {
                isEditing = false
            }
            viewModel.fetchMigraines()
        }
    }
}

struct MigraineRowView: View {
    let migraine: MigraineEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let startTime = migraine.startTime {
                Text(startTime, style: .date)
                    .font(.headline)
            }
            
            HStack {
                Label("Pain Level: \(migraine.painLevel)", systemImage: "thermometer")
                    .foregroundColor(painLevelColor(migraine.painLevel))
                Spacer()
                Text(migraine.location ?? "Unknown")
            }
            .font(.subheadline)
            
            if !migraine.selectedTriggerNames.isEmpty {
                Text("Triggers: \(migraine.selectedTriggerNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
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
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search medications, triggers, or notes", text: $text)
                .textFieldStyle(.roundedBorder)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    MigraineListView(viewModel: MigraineViewModel(context: PersistenceController.preview.container.viewContext))
} 