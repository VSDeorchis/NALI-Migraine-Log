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
    @State private var showingNewMigraine = false
    @State private var showingSplash = true
    @State private var hasAcceptedDisclaimer = UserDefaults.standard.bool(forKey: Constants.hasAcceptedDisclaimer)
    let persistenceController = PersistenceController.shared
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasAcceptedDisclaimer {
                    DisclaimerView(hasAcceptedDisclaimer: $hasAcceptedDisclaimer) {
                        NSApplication.shared.terminate(nil)
                    }
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
                    MacContentView(context: persistenceController.container.viewContext)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                }
            }
        }
        .commands {
            AppCommands(viewModel: viewModel, showingNewMigraine: $showingNewMigraine)
            SidebarCommands()
        }
        
        Settings {
            SettingsView()
        }
    }
}
