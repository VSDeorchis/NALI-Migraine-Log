import SwiftUI
import WatchConnectivity
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct WatchMigraineLogView: View {
    @EnvironmentObject var migraineStore: MigraineStore
    @State private var showingNewEntry = false
    
    var body: some View {
        List {
            Button(action: {
                showingNewEntry = true
            }) {
                Label("New Entry", systemImage: "plus.circle.fill")
            }
            
            ForEach(migraineStore.migraines.prefix(5).sorted(by: { $0.startTime > $1.startTime })) { migraine in
                WatchMigraineRowView(migraine: migraine)
            }
        }
        .navigationTitle("NALI Migraines")
        .sheet(isPresented: $showingNewEntry) {
            WatchNewMigraineView()
                .environmentObject(migraineStore)
        }
    }
} 