import SwiftUI

struct MigraineListView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var searchText = ""
    @State private var selectedMigraine: MigraineEvent?
    @State private var isEditing = false
    @State private var sortOption: SortOption = .dateNewest
    
    enum SortOption: String, CaseIterable {
        case dateNewest = "Date (Newest)"
        case dateOldest = "Date (Oldest)"
        case painHighest = "Pain (Highest)"
        case painLowest = "Pain (Lowest)"
        case durationLongest = "Duration (Longest)"
    }
    
    var filteredMigraines: [MigraineEvent] {
        var result: [MigraineEvent]
        if searchText.isEmpty {
            result = viewModel.migraines
        } else {
            result = viewModel.migraines.filter { migraine in
                let notesMatch = migraine.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let medicationsMatch = migraine.selectedMedicationNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                let triggersMatch = migraine.selectedTriggerNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                let locationMatch = migraine.location?.localizedCaseInsensitiveContains(searchText) ?? false
                return notesMatch || medicationsMatch || triggersMatch || locationMatch
            }
        }
        
        switch sortOption {
        case .dateNewest:
            result.sort { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
        case .dateOldest:
            result.sort { ($0.startTime ?? .distantPast) < ($1.startTime ?? .distantPast) }
        case .painHighest:
            result.sort { $0.painLevel > $1.painLevel }
        case .painLowest:
            result.sort { $0.painLevel < $1.painLevel }
        case .durationLongest:
            result.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SearchBar(text: $searchText)
                
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 200)
                
                Text("\(filteredMigraines.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
        .task {
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
    
    private var formattedDuration: String? {
        guard let start = migraine.startTime else { return nil }
        if let end = migraine.endTime {
            let interval = end.timeIntervalSince(start)
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(minutes)m"
        }
        return "Ongoing"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let startTime = migraine.startTime {
                    Text(startTime, style: .date)
                        .font(.headline)
                }
                Spacer()
                if let durationText = formattedDuration {
                    Label(durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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