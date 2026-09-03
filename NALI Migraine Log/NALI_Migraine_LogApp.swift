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
    private let settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    /// Receives "open a screen" requests from App Intents (Siri /
    /// Shortcuts). Currently drives the New Entry sheet below via
    /// `OpenNewEntryIntent`.
    @Bindable private var navigator = AppNavigationCoordinator.shared
    /// One-time launch work (legacy import, version upgrade steps) runs
    /// from `.task` below; the splash stays up only until it finishes
    /// (floor matches the splash intro animation length).
    @State private var launch = AppLaunchCoordinator(
        steps: [
            LaunchStep(title: "Importing earlier entries") { context in
                try DataMigrationHelper.migrateLegacyDataIfNeeded(context: context)
            },
            LaunchStep(title: "Updating your data") { context in
                MigrationCoordinator.runLaunchSequence(context: context)
            }
        ],
        minimumSplashDuration: .seconds(1.6)
    )
    @State private var hasAcceptedDisclaimer = UserDefaults.standard.bool(forKey: Constants.hasAcceptedDisclaimer)
    /// Set when the user taps Decline. The app stays open on a blocking
    /// explanation until they return to the disclaimer and accept.
    @State private var declinedDisclaimer = false
    @State private var showingSettings = false
    /// One-time "What's New" announcement after a feature update. Gated
    /// by `WhatsNew` so it shows once per release and never to a
    /// brand-new install.
    @State private var showingWhatsNew = false
    @Environment(\.scenePhase) private var scenePhase
    let persistenceController = PersistenceController.shared
    
    init() {
        AppLogger.general.notice("App initializing")
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))

        // Stamp first-launch date + bump launch counter for the review
        // prompt gate. The coordinator is `@MainActor` and `init()`
        // already runs on the main actor, so no dispatch is needed.
        MainActor.assumeIsolated {
            ReviewPromptCoordinator.recordLaunch()
        }

        // Register the BG refresh task handler. **Must** happen during
        // app init — calling it later trips iOS's "unknown task
        // identifier" runtime check. The actual `submit()` calls happen
        // in the .background scenePhase below.
        MainActor.assumeIsolated {
            BackgroundTaskScheduler.register()
        }

        AppLogger.general.notice("App initialized")
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasAcceptedDisclaimer {
                    if declinedDisclaimer {
                        DisclaimerDeclinedView {
                            declinedDisclaimer = false
                        }
                    } else {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        DisclaimerView(
                            hasAcceptedDisclaimer: $hasAcceptedDisclaimer,
                            declineAction: {
                                declinedDisclaimer = true
                            }
                        )
                    }
                } else if !launch.isReady {
                    SplashScreen()
                        .overlay(alignment: .bottom) {
                            LaunchProgressView(
                                coordinator: launch,
                                context: persistenceController.container.viewContext
                            )
                        }
                        .transition(.opacity)
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
                    // Siri / Shortcuts "Open New Migraine Entry" lands
                    // here regardless of which tab is showing.
                    // `NewMigraineView` brings its own NavigationStack +
                    // toolbar, so present it bare.
                    .sheet(isPresented: $navigator.showNewEntry) {
                        NewMigraineView(viewModel: viewModel)
                    }
                    // Immersive one-time update announcement. Uses a
                    // fullScreenCover (not another `.sheet`) so it can't
                    // collide with the Settings / New Entry sheets above.
                    .fullScreenCover(isPresented: $showingWhatsNew) {
                        WhatsNewView(onDismiss: {
                            WhatsNew.markSeen()
                            showingWhatsNew = false
                        })
                    }
                    .onAppear {
                        AppLogger.ui.debug("Main TabView appeared")
                        // Request location permission on first launch
                        locationManager.requestPermission()
                        // Surface the What's New sheet to upgrading users
                        // once the main UI is visible (post-splash).
                        // `launchCount` is @MainActor; onAppear already runs
                        // on the main actor, so assumeIsolated is safe and
                        // matches the idiom used in `init()` above.
                        MainActor.assumeIsolated {
                            if WhatsNew.shouldPresentOnLaunch(launchCount: ReviewPromptCoordinator.launchCount) {
                                showingWhatsNew = true
                            }
                        }
                    }
                }
            }
            .animation(.default, value: launch.isReady)
            .task {
                await launch.run(context: persistenceController.container.viewContext)
            }
            .preferredColorScheme(settings.colorScheme.colorScheme)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    /// Drives our background-aware behaviors: every time the app loses
    /// focus we ask iOS to wake us in the future, and every time we
    /// regain focus we re-evaluate what notifications should be
    /// scheduled (because the OS auth status, the user's data, or the
    /// weather forecast may have all changed since we last looked).
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            BackgroundTaskScheduler.scheduleNextRefresh()

        case .active:
            // Foregrounding cancels the daily re-engagement push (the
            // user is right here — no need to nag), and reconciles
            // forecast pushes against the current data + forecast.
            // We piggyback on the cached forecast inside
            // `WeatherForecastService.shared`; if it's empty the
            // notification manager early-returns and the BG task will
            // try again on its next run.
            Task { @MainActor in
                await NotificationManager.shared.cancelReengagementNotifications()
                await NotificationManager.shared.reconcileAllNotifications(
                    migraines: viewModel.migraines,
                    forecast: WeatherForecastService.shared.next(hours: 24)
                )
            }

        default:
            break
        }
    }
}
