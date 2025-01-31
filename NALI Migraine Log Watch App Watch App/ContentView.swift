//
//  ContentView.swift
//  NALI Migraine Log Watch App Watch App
//
//  Created by Vincent S. DeOrchis on 1/26/25.
//

import SwiftUI
import WatchConnectivity
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct ContentView: View {
    @EnvironmentObject var migraineStore: MigraineStore
    
    var body: some View {
        WatchMigraineLogView()
    }
}

#Preview {
    ContentView()
        .environmentObject(MigraineStore.shared)
}
