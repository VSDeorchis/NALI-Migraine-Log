//
//  NALI_Migraine_LogApp.swift
//  NALI Migraine Log
//
//  Created by Vincent DeOrchis on 1/26/25.
//

import SwiftUI

@main
struct NALI_Migraine_LogApp: App {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingSplash = true
    @State private var hasAcceptedDisclaimer = UserDefaults.standard.bool(forKey: Constants.hasAcceptedDisclaimer)
    @Environment(\.scenePhase) private var scenePhase
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
                    iOSContentView(viewModel: viewModel)
                        .environmentObject(locationManager)
                        .onAppear {
                            AppLogger.ui.debug("Main navigation appeared")
                            // Request location permission on first launch
                            locationManager.requestPermission()
                        }
                }
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
                viewModel.fetchMigraines()
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
