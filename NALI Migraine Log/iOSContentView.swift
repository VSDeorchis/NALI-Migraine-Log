//
//  ContentView.swift
//  NALI Migraine Log
//
//  Created by Vincent DeOrchis on 1/26/25.
//

import SwiftUI
import CoreData

struct iOSContentView: View {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var selectedTab = 0
    @State private var showingNewMigraine = false
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MigraineLogView(viewModel: viewModel)
                .tabItem {
                    Label("Log", systemImage: "list.bullet")
                }
                .tag(0)
            
            CalendarView(viewModel: viewModel)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)
            
            StatisticsView(viewModel: viewModel)
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }
                .tag(2)
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(3)
        }
        .sheet(isPresented: $showingNewMigraine) {
            NewMigraineView(viewModel: viewModel)
        }
        .environmentObject(connectivityManager)
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return iOSContentView()
        .environment(\.managedObjectContext, context)
}
