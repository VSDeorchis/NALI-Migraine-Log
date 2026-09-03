import SwiftUI

struct MacContentView: View {
    @ObservedObject var viewModel: MigraineViewModel
    /// Per-window so each restored window comes back on the view it was showing.
    @SceneStorage("mac.selectedTab") private var selectedTab = 0
    @State private var showingNewMigraine = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var selectedFilter: SmartFilter = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedTab) {
                // Main navigation
                Section("Navigation") {
                    ForEach(MacDestination.allCases) { destination in
                        NavigationLink(value: destination.rawValue) {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                        .tag(destination.rawValue)
                    }
                }
                
                // Smart Filters (only visible when on Migraine Log tab)
                if selectedTab == 0 || selectedTab >= 10 {
                    Section("Smart Filters") {
                        ForEach(SmartFilter.allCases) { filter in
                            Button {
                                selectedFilter = filter
                                selectedTab = filter == .all ? 0 : (10 + (SmartFilter.allCases.firstIndex(of: filter) ?? 0))
                            } label: {
                                Label {
                                    Text(filter.rawValue)
                                        .foregroundStyle(selectedFilter == filter ? Color.accentColor : Color.primary)
                                } icon: {
                                    Image(systemName: filter.icon)
                                        .foregroundStyle(selectedFilter == filter ? Color.accentColor : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                            .background(
                                selectedFilter == filter
                                    ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.1))
                                    : nil
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedTab {
                case 0, 10, 11, 12, 13, 14, 15, 16:
                    MigraineListView(viewModel: viewModel, activeFilter: selectedFilter)
                case 1:
                    CalendarView(viewModel: viewModel)
                case 2:
                    MacMigraineRiskView(viewModel: viewModel)
                case 3:
                    StatisticsView(viewModel: viewModel)
                case 4:
                    AboutView()
                default:
                    MigraineListView(viewModel: viewModel, activeFilter: selectedFilter)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { showingNewMigraine = true }) {
                    Image(systemName: "plus")
                        .font(.title3)
                }
                .help("New Migraine (⌘N)")
            }
        }
        .focusedSceneValue(\.newMigraine, { showingNewMigraine = true })
        .focusedSceneValue(\.refreshMigraines, { viewModel.fetchMigraines() })
        .focusedSceneValue(\.selectedTab, $selectedTab)
        .onAppear {
            viewModel.fetchMigraines()
            if selectedTab >= 10 {
                let filters = SmartFilter.allCases
                selectedFilter = filters.indices.contains(selectedTab - 10) ? filters[selectedTab - 10] : .all
            }
        }
        .sheet(isPresented: $showingNewMigraine) {
            NewMigraineView(viewModel: viewModel)
        }
        .onChange(of: selectedTab) { newTab in
            // Reset filter when switching away from Migraine Log
            if newTab >= 1 && newTab < 10 {
                selectedFilter = .all
            }
        }
    }
}

#Preview {
    MacContentView(viewModel: MigraineViewModel(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
