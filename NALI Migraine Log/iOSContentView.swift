//
//  ContentView.swift
//  NALI Migraine Log
//
//  Created by Vincent DeOrchis on 1/26/25.
//

import SwiftUI
import CoreData

/// Top-level destinations. Reused by both the iPhone `TabView` and the
/// iPad sidebar so the two layouts can never drift out of sync — add a
/// case here and both layouts pick it up automatically.
enum AppDestination: Int, CaseIterable, Identifiable {
    case log = 0
    case calendar = 1
    case analytics = 2
    case about = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .log: return "Log"
        case .calendar: return "Calendar"
        case .analytics: return "Analytics"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .log: return "list.bullet"
        case .calendar: return "calendar"
        case .analytics: return "chart.bar"
        case .about: return "info.circle"
        }
    }
}

struct iOSContentView: View {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @State private var selectedDestination: AppDestination = .log
    @State private var showingNewMigraine = false

    /// `.regular` ≈ iPad in any orientation, plus iPhone Plus/Pro Max in
    /// landscape. We only swap to the sidebar in that case; everything
    /// else (compact iPhone) keeps the familiar bottom tab bar.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadSplitLayout
            } else {
                iPhoneTabLayout
            }
        }
        .sheet(isPresented: $showingNewMigraine) {
            NewMigraineView(viewModel: viewModel)
        }
        .environmentObject(connectivityManager)
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }

    // MARK: - iPhone (compact)

    private var iPhoneTabLayout: some View {
        TabView(selection: $selectedDestination) {
            ForEach(AppDestination.allCases) { destination in
                destinationView(for: destination)
                    .tabItem {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                    .tag(destination)
            }
        }
    }

    // MARK: - iPad (regular)

    /// Sidebar + detail layout for iPad. Each destination already brings
    /// its own `NavigationStack`, so the detail column just hosts that
    /// stack — split-view manages the sidebar/detail relationship and
    /// each destination keeps its own back stack untouched.
    private var iPadSplitLayout: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { Optional(selectedDestination) },
                set: { newValue in
                    if let value = newValue { selectedDestination = value }
                }
            )) {
                ForEach(AppDestination.allCases) { destination in
                    NavigationLink(value: destination) {
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                    .tag(destination)
                }
            }
            .navigationTitle("Headway")
            .listStyle(.sidebar)
        } detail: {
            destinationView(for: selectedDestination)
                .id(selectedDestination)
        }
    }

    // MARK: - Routing

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .log:       MigraineLogView(viewModel: viewModel)
        case .calendar:  CalendarView(viewModel: viewModel)
        case .analytics: StatisticsView(viewModel: viewModel)
        case .about:     AboutView()
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return iOSContentView()
        .environment(\.managedObjectContext, context)
}
