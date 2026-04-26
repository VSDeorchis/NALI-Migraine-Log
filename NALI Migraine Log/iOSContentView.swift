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
    
    /// The character used in the corresponding ⌘-key shortcut.
    /// Mirrors the destination's display order so users learn it as
    /// "command-1 = the first thing in the sidebar". Surfaced via
    /// `iOSContentView.globalKeyboardShortcuts`.
    var shortcutKey: KeyEquivalent {
        switch self {
        case .log: return "1"
        case .calendar: return "2"
        case .analytics: return "3"
        case .about: return "4"
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
        .background { globalKeyboardShortcuts }
        .environmentObject(connectivityManager)
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
    
    /// Off-screen buttons that exist purely to host hardware-keyboard
    /// shortcuts so the iPad's "press and hold ⌘" overlay surfaces
    /// them. We deliberately attach these at the root so they fire
    /// regardless of which destination is currently visible — the
    /// in-destination toolbar buttons (e.g. the `+` in `MigraineLogView`)
    /// would only respond when their tab was already on screen.
    ///
    /// - ⌘N: log a new migraine
    /// - ⌘1 / ⌘2 / ⌘3 / ⌘4: jump to Log / Calendar / Analytics / About
    @ViewBuilder
    private var globalKeyboardShortcuts: some View {
        // Wrapped in a zero-size, hidden container so the buttons never
        // claim layout space yet still register their shortcuts. We
        // don't need accessibility here — VoiceOver users already have
        // the visible toolbar buttons + sidebar list to invoke the
        // same actions.
        Group {
            Button("Log New Migraine") { showingNewMigraine = true }
                .keyboardShortcut("n", modifiers: .command)
            
            ForEach(AppDestination.allCases) { destination in
                Button("Switch to \(destination.title)") {
                    selectedDestination = destination
                }
                .keyboardShortcut(destination.shortcutKey, modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
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
            // Docked CTA at the bottom of the sidebar — always visible
            // regardless of which destination is selected. Mirrors the
            // pattern used by Reminders and Notes on iPadOS so users
            // can log a migraine without first navigating to the Log
            // tab.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarLogCTA
            }
            .toolbar {
                // Compact "+" in the sidebar nav bar mirrors what
                // first-time iPad users expect from Mail/Reminders
                // (they don't always notice the docked button at the
                // bottom). The keyboard shortcut itself is hosted on
                // the hidden root button in `globalKeyboardShortcuts`
                // so it works from any destination, not just when the
                // sidebar is focused.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewMigraine = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log New Migraine")
                    .accessibilityHint("Opens a form to record a new migraine entry")
                }
            }
        } detail: {
            destinationView(for: selectedDestination)
                .id(selectedDestination)
        }
    }
    
    /// Bottom-docked sidebar footer: an always-on summary of the user's
    /// recent activity (migraines this month + current migraine-free
    /// streak) above a prominent CTA for logging a new migraine. The
    /// summary makes the sidebar feel like a dashboard rather than a
    /// pure navigation list, and it's reactive — every save through
    /// `MigraineViewModel` updates `viewModel.migraines`, which
    /// re-evaluates the computeds below.
    private var sidebarLogCTA: some View {
        VStack(spacing: 0) {
            Divider()
            sidebarStatsSummary
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            Button {
                showingNewMigraine = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Log Migraine")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
            .accessibilityLabel("Log New Migraine")
            .accessibilityHint("Opens a form to record a new migraine entry")
        }
    }
    
    /// Two-line summary of the dataset, surfaced above the CTA. We use
    /// the same `Array<MigraineEvent>` extension that the Analytics
    /// dashboard uses (`currentMigraineFreeStreak`) so the sidebar
    /// can never disagree with the streak tile.
    private var sidebarStatsSummary: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(migrainesThisMonth)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("this month")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 8)
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(streakDisplay)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                Text("day\(streakDisplay == "1" ? "" : "s") migraine-free")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(migrainesThisMonth) migraine\(migrainesThisMonth == 1 ? "" : "s") this month, "
                + accessibilityStreakLabel
        )
    }
    
    private var migrainesThisMonth: Int {
        let cal = Calendar.current
        let now = Date()
        return viewModel.migraines.reduce(into: 0) { count, migraine in
            guard let start = migraine.startTime else { return }
            if cal.isDate(start, equalTo: now, toGranularity: .month) {
                count += 1
            }
        }
    }
    
    /// `nil` (no migraines logged) → em-dash; otherwise the day count.
    /// Capped to a string so the right-aligned number stays compact
    /// even when `currentMigraineFreeStreak()` returns a large value.
    private var streakDisplay: String {
        guard let streak = viewModel.migraines.currentMigraineFreeStreak() else {
            return "—"
        }
        return String(streak)
    }
    
    private var accessibilityStreakLabel: String {
        guard let streak = viewModel.migraines.currentMigraineFreeStreak() else {
            return "no migraines logged yet"
        }
        return "\(streak) day\(streak == 1 ? "" : "s") migraine-free"
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
