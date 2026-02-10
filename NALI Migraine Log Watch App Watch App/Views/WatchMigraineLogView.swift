import SwiftUI
import CoreData

struct WatchMigraineLogView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var showingNewEntry = false
    
    var body: some View {
        List {
            // Quick actions
            Section {
                Button(action: {
                    showingNewEntry = true
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
        .sheet(isPresented: $showingNewEntry) {
            WatchNewMigraineView(viewModel: viewModel)
        }
    }
} 