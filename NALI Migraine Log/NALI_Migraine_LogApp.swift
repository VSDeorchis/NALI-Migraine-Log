//
//  NALI_Migraine_LogApp.swift
//  NALI Migraine Log
//
//  Created by Vincent DeOrchis on 1/26/25.
//

import SwiftUI
import WatchConnectivity
import CoreData

@main
struct NALI_Migraine_LogApp: App {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingSplash = true
    @State private var hasAcceptedDisclaimer = UserDefaults.standard.bool(forKey: Constants.hasAcceptedDisclaimer)
    @State private var showingSettings = false
    let persistenceController = PersistenceController.shared
    
    init() {
        NSLog("🟣 [App] ===== APP INITIALIZING =====")
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
        
        // Perform data migration if needed
        DataMigrationHelper.checkAndMigrateData(context: context)
        NSLog("🟣 [App] ===== APP INITIALIZED =====")
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasAcceptedDisclaimer {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    DisclaimerView(
                        hasAcceptedDisclaimer: $hasAcceptedDisclaimer,
                        dismissAction: {
                            exit(0)
                        },
                        viewModel: viewModel
                    )
                } else if showingSplash {
                    SplashScreen()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showingSplash = false
                                }
                            }
                        }
                } else {
                    TabView {
                        MigraineLogView(viewModel: viewModel)
                            .tabItem {
                                Label("Log", systemImage: "list.bullet")
                            }
                        
                        CalendarView(viewModel: viewModel)
                            .tabItem {
                                Label("Calendar", systemImage: "calendar")
                            }
                        
                        StatisticsView(viewModel: viewModel)
                            .tabItem {
                                Label("Analytics", systemImage: "chart.bar")
                            }
                        
                        AboutView()
                            .tabItem {
                                Label("About", systemImage: "info.circle")
                            }
                    }
                    .environmentObject(connectivityManager)
                    .environmentObject(locationManager)
                    .sheet(isPresented: $showingSettings) {
                        SettingsView(viewModel: viewModel)
                    }
                    .onAppear {
                        NSLog("🟣 [App] Main TabView appeared")
                        // Request location permission on first launch
                        locationManager.requestPermission()
                    }
                }
            }
            .preferredColorScheme(settings.colorScheme.colorScheme)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
