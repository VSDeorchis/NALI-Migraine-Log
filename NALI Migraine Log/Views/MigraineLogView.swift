import SwiftUI

struct MigraineLogView: View {
    @ObservedObject var migraineStore: MigraineStore
    @State private var showingNewMigraineSheet = false
    @State private var selectedMigraine: MigraineEvent?
    @State private var showingEditSheet = false
    @State private var filterOption = FilterOption.all
    @State private var searchText = ""
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case lastWeek = "Last Week"
        case lastMonth = "Last Month"
        case lastYear = "Last Year"
        case highPain = "High Pain"
        case withAura = "With Aura"
    }
    
    var filteredMigraines: [MigraineEvent] {
        let calendar = Calendar.current
        let now = Date()
        
        var filtered = migraineStore.migraines
        
        // Apply search if text exists
        if !searchText.isEmpty {
            filtered = filtered.filter { migraine in
                let notesMatch = migraine.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let medicationsMatch = migraine.medications.contains { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
                let triggersMatch = migraine.triggers.contains { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
                return notesMatch || medicationsMatch || triggersMatch
            }
        }
        
        // Apply selected filter
        switch filterOption {
        case .all:
            return filtered
        case .lastWeek:
            let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return filtered.filter { $0.startTime >= oneWeekAgo }
        case .lastMonth:
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return filtered.filter { $0.startTime >= oneMonthAgo }
        case .lastYear:
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            return filtered.filter { $0.startTime >= oneYearAgo }
        case .highPain:
            return filtered.filter { $0.painLevel >= 7 }
        case .withAura:
            return filtered.filter { $0.hasAura }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter and Search Section
                VStack(spacing: 8) {
                    // Filter buttons
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            FilterButton(title: "All", isSelected: filterOption == .all) {
                                filterOption = .all
                            }
                            FilterButton(title: "Last Week", isSelected: filterOption == .lastWeek) {
                                filterOption = .lastWeek
                            }
                            FilterButton(title: "Last Month", isSelected: filterOption == .lastMonth) {
                                filterOption = .lastMonth
                            }
                        }
                        
                        HStack(spacing: 8) {
                            FilterButton(title: "Last Year", isSelected: filterOption == .lastYear) {
                                filterOption = .lastYear
                            }
                            FilterButton(title: "High Pain", isSelected: filterOption == .highPain) {
                                filterOption = .highPain
                            }
                            FilterButton(title: "With Aura", isSelected: filterOption == .withAura) {
                                filterOption = .withAura
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    SearchBar(text: $searchText)
                }
                .padding(.vertical, 8)
                
                List {
                    ForEach(filteredMigraines.sorted(by: { $0.startTime > $1.startTime })) { migraine in
                        MigraineRowView(migraine: migraine)
                            .onTapGesture {
                                selectedMigraine = migraine
                                showingEditSheet = true
                            }
                    }
                    .onDelete { indexSet in
                        let sortedMigraines = filteredMigraines.sorted(by: { $0.startTime > $1.startTime })
                        indexSet.forEach { index in
                            migraineStore.removeMigraine(sortedMigraines[index])
                        }
                    }
                }
            }
            .navigationTitle("Migraine Log")
            .toolbar {
                Button {
                    showingNewMigraineSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingNewMigraineSheet) {
                NewMigraineView(migraineStore: migraineStore)
            }
            .sheet(isPresented: $showingEditSheet) {
                if let migraine = selectedMigraine {
                    NewMigraineView(migraineStore: migraineStore, editingMigraine: migraine)
                }
            }
        }
    }
}

// Custom SearchBar View
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search medications, triggers, or notes", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
    }
} 