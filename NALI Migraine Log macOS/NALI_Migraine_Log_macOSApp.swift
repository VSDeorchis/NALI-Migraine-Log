//
//  NALI_Migraine_Log_macOSApp.swift
//  NALI Migraine Log macOS
//
//  Created by Vincent S. DeOrchis on 2/8/25.
//

import SwiftUI

@main
struct NALI_Migraine_Log_macOSApp: App {
    @StateObject private var viewModel: MigraineViewModel
    @State private var launch = AppLaunchCoordinator(
        steps: [
            LaunchStep(title: "Updating your data") { context in
                MigrationCoordinator.runLaunchSequence(context: context)
            }
        ],
        minimumSplashDuration: .seconds(1.6)
    )
    @State private var hasAcceptedDisclaimer = UserDefaults.standard.bool(forKey: Constants.hasAcceptedDisclaimer)
    @State private var declinedDisclaimer = false
    let persistenceController = PersistenceController.shared
    
    init() {
        // Concretize the iCloud sync preference once so the `@AppStorage`-backed
        // Settings/Disclaimer toggles reflect the real default (ON for new
        // installs, OFF for users who onboarded before this default existed)
        // instead of a hard-coded literal that could misrepresent the store.
        if UserDefaults.standard.object(forKey: "useICloudSync") == nil {
            UserDefaults.standard.set(UserDefaults.standard.headwayICloudSyncEnabled, forKey: "useICloudSync")
        }

        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
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
                        DisclaimerView(hasAcceptedDisclaimer: $hasAcceptedDisclaimer) {
                            declinedDisclaimer = true
                        }
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
                    MacContentView(viewModel: viewModel)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                }
            }
            .animation(.default, value: launch.isReady)
            .task {
                await launch.run(context: persistenceController.container.viewContext)
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            AppCommands()
            SidebarCommands()
        }
        
        Settings {
            SettingsView()
        }
    }
}
