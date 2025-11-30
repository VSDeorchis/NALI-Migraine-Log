import SwiftUI

struct MacContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: MigraineViewModel
    @State private var selectedTab = 0
    @State private var showingNewMigraine = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedTab) {
                NavigationLink(destination: MigraineListView(viewModel: viewModel)) {
                    Label("Migraine Log", systemImage: "list.bullet")
                }
                .tag(0)
                
                NavigationLink(destination: CalendarView(viewModel: viewModel)) {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)
                
                NavigationLink(destination: StatisticsView(viewModel: viewModel)) {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(2)
                
                NavigationLink(destination: AboutView()) {
                    Label("About", systemImage: "info.circle")
                }
                .tag(3)
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem {
                    Button(action: { showingNewMigraine = true }) {
                        Label("Add Migraine", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Group {
                switch selectedTab {
                case 0:
                    MigraineListView(viewModel: viewModel)
                case 1:
                    CalendarView(viewModel: viewModel)
                case 2:
                    StatisticsView(viewModel: viewModel)
                case 3:
                    AboutView()
                default:
                    MigraineListView(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            viewModel.fetchMigraines()  // Fetch data when app launches
        }
        .sheet(isPresented: $showingNewMigraine) {
            NewMigraineView(viewModel: viewModel)
        }
    }
}

#Preview {
    MacContentView(context: PersistenceController.preview.container.viewContext)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 