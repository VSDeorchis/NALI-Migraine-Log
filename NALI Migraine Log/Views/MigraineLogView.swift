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
    @State private var isRefreshing = false
    
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
                    
                    // Migraine list with pull-to-refresh
                    if filteredMigraines.isEmpty {
                        // Empty state
                        EmptyMigraineStateView(
                            filterOption: filterOption,
                            searchText: searchText,
                            onAddTapped: { showingNewMigraineSheet = true }
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredMigraines) { migraine in
                                    MigraineRowView(viewModel: viewModel, migraine: migraine)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                            impactFeedback.impactOccurred()
                                            selectedMigraine = migraine
                                        }
                                        .contextMenu {
                                            Button {
                                                selectedMigraine = migraine
                                            } label: {
                                                Label("View Details", systemImage: "eye")
                                            }
                                            
                                            Button {
                                                duplicateMigraine(migraine)
                                            } label: {
                                                Label("Duplicate", systemImage: "doc.on.doc")
                                            }
                                            
                                            Divider()
                                            
                                            Button(role: .destructive) {
                                                Task {
                                                    await viewModel.deleteMigraine(migraine)
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                let feedback = UINotificationFeedbackGenerator()
                                                feedback.notificationOccurred(.warning)
                                                Task {
                                                    await viewModel.deleteMigraine(migraine)
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                let feedback = UIImpactFeedbackGenerator(style: .medium)
                                                feedback.impactOccurred()
                                                duplicateMigraine(migraine)
                                            } label: {
                                                Label("Duplicate", systemImage: "doc.on.doc")
                                            }
                                            .tint(.blue)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(accessibilityLabel(for: migraine))
                                        .accessibilityHint("Double tap to view details")
                                }
                            }
                            .padding(.top, 8)
                        }
                        .refreshable {
                            await refreshData()
                        }
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
                    ((searchText.localizedCaseInsensitiveContains("menstrual") || searchText.localizedCaseInsensitiveContains("hormones")) && migraine.isTriggerHormones) ||
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
                    (searchText.localizedCaseInsensitiveContains("symbravo") && migraine.tookSymbravo) ||
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
    
    private func duplicateMigraine(_ migraine: MigraineEvent) {
        Task {
            await viewModel.addMigraine(
                startTime: Date(),
                endTime: nil,
                painLevel: migraine.painLevel,
                location: migraine.location ?? "Frontal",
                triggers: migraine.selectedTriggerNames,
                hasAura: migraine.hasAura,
                hasPhotophobia: migraine.hasPhotophobia,
                hasPhonophobia: migraine.hasPhonophobia,
                hasNausea: migraine.hasNausea,
                hasVomiting: migraine.hasVomiting,
                hasWakeUpHeadache: migraine.hasWakeUpHeadache,
                hasTinnitus: migraine.hasTinnitus,
                hasVertigo: migraine.hasVertigo,
                missedWork: migraine.missedWork,
                missedSchool: migraine.missedSchool,
                missedEvents: migraine.missedEvents,
                medications: migraine.selectedMedicationNames,
                notes: nil
            )
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
        }
    }
    
    private func deleteMigraines(at offsets: IndexSet) {
        Task {
            for index in offsets {
                await viewModel.deleteMigraine(filteredMigraines[index])
            }
        }
    }
    
    // MARK: - Pull to Refresh
    
    private func refreshData() async {
        isRefreshing = true
        // Give haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Trigger a refresh of the data
        await viewModel.refreshMigraines()
        
        // Small delay for visual feedback
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
    
    // MARK: - Accessibility
    
    private func accessibilityLabel(for migraine: MigraineEvent) -> String {
        var label = ""
        
        if let date = migraine.startTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            label += "Migraine on \(formatter.string(from: date)). "
        }
        
        label += "Pain level \(migraine.painLevel) out of 10. "
        
        if let location = migraine.location {
            label += "\(location) location. "
        }
        
        if migraine.hasWeatherData {
            label += "Weather: \(Int(migraine.weatherTemperature)) degrees. "
        }
        
        return label
    }
}

// MARK: - Empty State View

struct EmptyMigraineStateView: View {
    let filterOption: MigraineLogView.FilterOption
    let searchText: String
    let onAddTapped: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: iconName)
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Text
            VStack(spacing: 8) {
                Text(titleText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(subtitleText)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Action button (only for empty state, not for filtered/search)
            if filterOption == .all && searchText.isEmpty {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onAddTapped()
                }) {
                    Label("Log Your First Migraine", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 8)
            }
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var iconName: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        }
        switch filterOption {
        case .all:
            return "brain.head.profile"
        case .lastWeek, .lastMonth, .lastYear:
            return "calendar"
        case .highPain:
            return "exclamationmark.triangle"
        case .withAura:
            return "sparkles"
        case .missedWork, .missedSchool:
            return "briefcase"
        }
    }
    
    private var titleText: String {
        if !searchText.isEmpty {
            return "No Results Found"
        }
        switch filterOption {
        case .all:
            return "No Migraines Logged"
        case .lastWeek:
            return "No Migraines This Week"
        case .lastMonth:
            return "No Migraines This Month"
        case .lastYear:
            return "No Migraines This Year"
        case .highPain:
            return "No High Pain Migraines"
        case .withAura:
            return "No Migraines with Aura"
        case .missedWork:
            return "No Missed Work Days"
        case .missedSchool:
            return "No Missed School Days"
        }
    }
    
    private var subtitleText: String {
        if !searchText.isEmpty {
            return "Try adjusting your search terms or clearing the filter"
        }
        switch filterOption {
        case .all:
            return "Start tracking your migraines to identify patterns and triggers"
        case .lastWeek:
            return "Great news! You haven't logged any migraines in the past week"
        case .lastMonth:
            return "Wonderful! No migraines logged in the past month"
        case .lastYear:
            return "Amazing! No migraines logged in the past year"
        case .highPain:
            return "No severe migraines (pain level 7+) found"
        case .withAura:
            return "No migraines with aura symptoms recorded"
        case .missedWork:
            return "No migraines that caused missed work"
        case .missedSchool:
            return "No migraines that caused missed school"
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
        Button(action: {
            let feedback = UISelectionFeedbackGenerator()
            feedback.selectionChanged()
            action()
        }) {
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
                Button(action: {
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                    text = ""
                }) {
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