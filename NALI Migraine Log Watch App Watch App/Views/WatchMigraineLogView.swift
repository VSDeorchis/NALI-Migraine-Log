import SwiftUI
import CoreData

struct WatchMigraineLogView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @ObservedObject private var navigator = WatchNavigationCoordinator.shared
    
    var body: some View {
        List {
            // Quick actions
            Section {
                Button(action: {
                    navigator.requestNewEntry()
                }) {
                    Label("New Entry", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                
                NavigationLink {
                    WatchMigraineRiskView(viewModel: viewModel)
                } label: {
                    Label("Risk Prediction", systemImage: "brain.head.profile")
                        .foregroundColor(.purple)
                }
            }
            
            // Recent migraines
            Section("Recent") {
                if viewModel.migraines.isEmpty {
                    Text("No migraines logged")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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