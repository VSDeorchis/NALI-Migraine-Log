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
        AppLogger.general.notice("App initializing")
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))

        // One-time migration of legacy UserDefaults-backed migraines into
        // Core Data (no-op once it has run successfully).
        DataMigrationHelper.checkAndMigrateData(context: context)

        // Per-launch version-change check. Empty step registry today, but
        // the hook is wired so the first release that needs a one-time
        // data backfill can land it as a single edit to
        // `MigrationCoordinator.upgradeSteps`.
        MigrationCoordinator.runLaunchSequence(context: context)

        // Stamp first-launch date + bump launch counter for the review
        // prompt gate. Deliberately runs *after* the migration hook so
        // that a first-launch users coming from an upgrade still get the
        // legacy data migration before we start counting their tenure.
        // The coordinator is `@MainActor` and `init()` already runs on
        // the main actor, so no dispatch is needed.
        MainActor.assumeIsolated {
            ReviewPromptCoordinator.recordLaunch()
        }

        AppLogger.general.notice("App initialized")
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
                        
                        MigraineRiskView(viewModel: viewModel)
                            .tabItem {
                                Label("Predict", systemImage: "brain.head.profile")
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
                        AppLogger.ui.debug("Main TabView appeared")
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
