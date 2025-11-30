import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: MigraineViewModel
    @State private var selectedTab = 0
    @State private var showingNewMigraine = false
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some View {
        NavigationSplitView {
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
            Text("Select a view")
        }
        .sheet(isPresented: $showingNewMigraine) {
            NewMigraineView(viewModel: viewModel)
        }
    }
}

#Preview {
    ContentView(context: PersistenceController.preview.container.viewContext)
} 