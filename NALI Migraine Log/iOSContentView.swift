//
//  ContentView.swift
//  NALI Migraine Log
//
//  Created by Vincent DeOrchis on 1/26/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var migraineStore: MigraineStore
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MigraineLogView(migraineStore: migraineStore)
                .tabItem {
                    Label("Log", systemImage: "square.and.pencil")
                }
                .tag(0)
            
            CalendarView(migraineStore: migraineStore)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)
            
            StatisticsView(migraineStore: migraineStore)
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
    }
}

#Preview {
    ContentView()
        .environmentObject(MigraineStore())
}
