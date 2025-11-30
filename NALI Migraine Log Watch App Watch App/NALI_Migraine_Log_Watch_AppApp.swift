//
//  NALI_Migraine_Log_Watch_AppApp.swift
//  NALI Migraine Log Watch App Watch App
//
//  Created by Vincent S. DeOrchis on 1/26/25.
//

import SwiftUI
import CoreData
import WatchConnectivity

@main
struct NALI_Migraine_Log_Watch_AppApp: App {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    let persistenceController = PersistenceController.shared
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
        
        // Initialize WatchConnectivity
        if WCSession.isSupported() {
            WCSession.default.activate()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(connectivityManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
