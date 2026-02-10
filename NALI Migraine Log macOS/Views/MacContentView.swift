import SwiftUI

struct MacContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: MigraineViewModel
    @State private var selectedTab = 0
    @State private var showingNewMigraine = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var selectedFilter: SmartFilter = .all
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedTab) {
                // Main navigation
                Section("Navigation") {
                    NavigationLink(value: 0) {
                        Label("Migraine Log", systemImage: "list.bullet")
                    }
                    .tag(0)
                    
                    NavigationLink(value: 1) {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(1)
                    
                    NavigationLink(value: 2) {
                        Label("Predict", systemImage: "brain.head.profile")
                    }
                    .tag(2)
                    
                    NavigationLink(value: 3) {
                        Label("Analytics", systemImage: "chart.bar")
                    }
                    .tag(3)
                    
                    NavigationLink(value: 4) {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(4)
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
                                        .foregroundColor(selectedFilter == filter ? .accentColor : .primary)
                                } icon: {
                                    Image(systemName: filter.icon)
                                        .foregroundColor(selectedFilter == filter ? .accentColor : .secondary)
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
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onAppear {
            viewModel.fetchMigraines()
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
    MacContentView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
