//
//  NALI_Migraine_Log_Watch_AppApp.swift
//  NALI Migraine Log Watch App Watch App
//
//  Created by Vincent S. DeOrchis on 1/26/25.
//

import SwiftUI
import WatchConnectivity

@main
struct NALI_Migraine_Log_Watch_AppApp: App {
    // Use the shared instance
    @StateObject private var migraineStore = MigraineStore.shared
    
    init() {
        // Initialize WatchConnectivity if supported
        if WCSession.isSupported() {
            WCSession.default.activate()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(migraineStore)
            }
        }
    }
}
