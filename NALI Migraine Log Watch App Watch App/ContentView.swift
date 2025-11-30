//
//  ContentView.swift
//  NALI Migraine Log Watch App Watch App
//
//  Created by Vincent S. DeOrchis on 1/26/25.
//

import SwiftUI
import CoreData
import WatchConnectivity
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct ContentView: View {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some View {
        Group {
            if viewModel.migraines.isEmpty {
                ProgressView("Loading…")
                    .task {
                        connectivityManager.requestFullSync()
                    }
            } else {
        WatchMigraineLogView(viewModel: viewModel)
            }
        }
            .environmentObject(connectivityManager)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
