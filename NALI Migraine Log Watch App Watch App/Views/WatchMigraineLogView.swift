import SwiftUI
import CoreData
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct WatchMigraineLogView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var showingNewEntry = false
    
    var body: some View {
        List {
            Button(action: {
                showingNewEntry = true
            }) {
                Label("New Entry", systemImage: "plus.circle.fill")
            }
            
            ForEach(viewModel.migraines.prefix(5)) { migraine in
                WatchMigraineRowView(migraine: migraine)
            }
        }
        .navigationTitle("Headway")
        .sheet(isPresented: $showingNewEntry) {
            WatchNewMigraineView(viewModel: viewModel)
        }
    }
} 