import SwiftUI
import CoreData

struct WatchMigraineLogView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Bindable private var navigator = WatchNavigationCoordinator.shared
    
    var body: some View {
        List {
            // Quick actions
            Section {
                Button(action: {
                    navigator.requestNewEntry()
                }) {
                    Label("New Entry", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                
                NavigationLink {
                    WatchMigraineRiskView()
                } label: {
                    Label("Risk Prediction", systemImage: "brain.head.profile")
                        .foregroundStyle(.purple)
                }
            }
            
            // Recent migraines
            Section("Recent") {
                if viewModel.migraines.isEmpty {
                    Text("No migraines logged")
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.migraines.prefix(5)) { migraine in
                        WatchMigraineRowView(migraine: migraine)
                    }
                }
            }
        }
        .navigationTitle("Headway")
        // A single New Entry sheet driven by the shared coordinator, so
        // both the in-app button and a Siri / Shortcuts "open new entry"
        // intent present the same screen without competing bindings.
        .sheet(isPresented: $navigator.showNewEntry) {
            WatchNewMigraineView(viewModel: viewModel)
        }
    }
} 