//
//  NALI_Migraine_LogApp.swift
//  NALI Migraine Log
//
//  Created by Vincent DeOrchis on 1/26/25.
//

import SwiftUI

@main
struct NALI_Migraine_LogApp: App {
    @StateObject private var migraineStore = MigraineStore()
    @State private var showingSplash = true
    
    var body: some Scene {
        WindowGroup {
            if showingSplash {
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
                    MigraineLogView(migraineStore: migraineStore)
                        .tabItem {
                            Label("Log", systemImage: "list.bullet")
                        }
                    
                    CalendarView(migraineStore: migraineStore)
                        .tabItem {
                            Label("Calendar", systemImage: "calendar")
                        }
                    
                    StatisticsView(migraineStore: migraineStore)
                        .tabItem {
                            Label("Statistics", systemImage: "chart.bar")
                        }
                    
                    AboutView()
                        .tabItem {
                            Label("About", systemImage: "info.circle")
                        }
                }
            }
        }
    }
}
