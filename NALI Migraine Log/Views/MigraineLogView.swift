import SwiftUI
import CoreData

struct MigraineLogView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var showingNewMigraineSheet = false
    @State private var selectedMigraine: MigraineEvent?
    @State private var filterOption = FilterOption.all
    @State private var searchText = ""
    @State private var showingSettings = false
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case lastWeek = "Last Week"
        case lastMonth = "Last Month"
        case lastYear = "Last Year"
        case highPain = "High Pain"
        case withAura = "With Aura"
        case missedWork = "Missed Work"
        case missedSchool = "Missed School"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    SyncStatusView()
                        .padding(.top, 8)
                    
                    // Filter buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                FilterButton(
                                    title: option.rawValue,
                                    isSelected: filterOption == option
                                ) {
                                    filterOption = option
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Search bar
                    SearchBar(text: $searchText)
                        .padding(.top, 8)
                    
                    // Migraine list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredMigraines) { migraine in
                                let _ = NSLog("🔶 [MigraineLogView] Rendering row for migraine: \(migraine.id?.uuidString ?? "nil")")
                                MigraineRowView(viewModel: viewModel, migraine: migraine)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedMigraine = migraine
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteMigraine(migraine)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Headway: Migraine Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewMigraineSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewMigraineSheet) {
                NewMigraineView(viewModel: viewModel)
            }
            .sheet(item: $selectedMigraine) { migraine in
                NavigationStack {
                    MigraineDetailView(migraine: migraine, viewModel: viewModel, dismiss: { selectedMigraine = nil })
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
    }
    
    private var filteredMigraines: [MigraineEvent] {
        var migraines = viewModel.migraines
        
        // Apply time filter
        let calendar = Calendar.current
        let now = Date()
        
        switch filterOption {
        case .lastWeek:
            let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            migraines = migraines.filter { $0.startTime! >= oneWeekAgo }
        case .lastMonth:
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            migraines = migraines.filter { $0.startTime! >= oneMonthAgo }
        case .lastYear:
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            migraines = migraines.filter { $0.startTime! >= oneYearAgo }
        case .all:
            break
        case .highPain:
            migraines = migraines.filter { $0.painLevel >= 7 }
        case .withAura:
            migraines = migraines.filter { $0.hasAura }
        case .missedWork:
            migraines = migraines.filter { $0.missedWork }
        case .missedSchool:
            migraines = migraines.filter { $0.missedSchool }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            migraines = migraines.filter { migraine in
                let matchesLocation = migraine.location?.localizedCaseInsensitiveContains(searchText) ?? false
                let matchesNotes = migraine.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                
                // Search in triggers
                let matchesTriggers = 
                    (searchText.localizedCaseInsensitiveContains("stress") && migraine.isTriggerStress) ||
                    (searchText.localizedCaseInsensitiveContains("sleep") && migraine.isTriggerLackOfSleep) ||
                    (searchText.localizedCaseInsensitiveContains("dehydration") && migraine.isTriggerDehydration) ||
                    (searchText.localizedCaseInsensitiveContains("weather") && migraine.isTriggerWeather) ||
                    (searchText.localizedCaseInsensitiveContains("hormones") && migraine.isTriggerHormones) ||
                    (searchText.localizedCaseInsensitiveContains("alcohol") && migraine.isTriggerAlcohol) ||
                    (searchText.localizedCaseInsensitiveContains("caffeine") && migraine.isTriggerCaffeine) ||
                    (searchText.localizedCaseInsensitiveContains("food") && migraine.isTriggerFood) ||
                    (searchText.localizedCaseInsensitiveContains("exercise") && migraine.isTriggerExercise) ||
                    (searchText.localizedCaseInsensitiveContains("screen") && migraine.isTriggerScreenTime) ||
                    (searchText.localizedCaseInsensitiveContains("other") && migraine.isTriggerOther)
                
                // Search in medications
                let matchesMedications = 
                    (searchText.localizedCaseInsensitiveContains("ibuprofen") && migraine.tookIbuprofin) ||
                    (searchText.localizedCaseInsensitiveContains("excedrin") && migraine.tookExcedrin) ||
                    (searchText.localizedCaseInsensitiveContains("tylenol") && migraine.tookTylenol) ||
                    (searchText.localizedCaseInsensitiveContains("sumatriptan") && migraine.tookSumatriptan) ||
                    (searchText.localizedCaseInsensitiveContains("rizatriptan") && migraine.tookRizatriptan) ||
                    (searchText.localizedCaseInsensitiveContains("naproxen") && migraine.tookNaproxen) ||
                    (searchText.localizedCaseInsensitiveContains("frovatriptan") && migraine.tookFrovatriptan) ||
                    (searchText.localizedCaseInsensitiveContains("naratriptan") && migraine.tookNaratriptan) ||
                    (searchText.localizedCaseInsensitiveContains("nurtec") && migraine.tookNurtec) ||
                    (searchText.localizedCaseInsensitiveContains("ubrelvy") && migraine.tookUbrelvy) ||
                    (searchText.localizedCaseInsensitiveContains("reyvow") && migraine.tookReyvow) ||
                    (searchText.localizedCaseInsensitiveContains("trudhesa") && migraine.tookTrudhesa) ||
                    (searchText.localizedCaseInsensitiveContains("elyxyb") && migraine.tookElyxyb) ||
                    (searchText.localizedCaseInsensitiveContains("other") && migraine.tookOther)
                
                return matchesLocation || matchesNotes || matchesTriggers || matchesMedications
            }
        }
        
        return migraines
    }
    
    private func deleteMigraines(at offsets: IndexSet) {
        Task {
            for index in offsets {
                await viewModel.deleteMigraine(filteredMigraines[index])
            }
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return MigraineLogView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
}

// Custom FilterButton View
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(Color.blue.gradient)
                        } else {
                            Capsule()
                                .fill(Color(.secondarySystemGroupedBackground))
                        }
                    }
                )
                .foregroundColor(isSelected ? .white : .primary)
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
                )
                .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// Custom SearchBar View
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            
            TextField("Search medications, triggers, or notes", text: $text)
                .font(.system(.body, design: .rounded))
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.systemGray4), lineWidth: 1)
        )
        .padding(.horizontal)
    }
} 