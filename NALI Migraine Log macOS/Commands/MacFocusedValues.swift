import SwiftUI

/// Primary sidebar destinations. Raw values match the `selectedTab`
/// integers `MacContentView` has always used (smart filters live at 10+).
enum MacDestination: Int, CaseIterable, Identifiable {
    case log = 0
    case calendar = 1
    case predict = 2
    case analytics = 3
    case about = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .log:       return "Migraine Log"
        case .calendar:  return "Calendar"
        case .predict:   return "Predict"
        case .analytics: return "Analytics"
        case .about:     return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .log:       return "list.bullet"
        case .calendar:  return "calendar"
        case .predict:   return "brain.head.profile"
        case .analytics: return "chart.bar"
        case .about:     return "info.circle"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .log:       return "1"
        case .calendar:  return "2"
        case .predict:   return "3"
        case .analytics: return "4"
        case .about:     return "5"
        }
    }
}

/// Actions the key window's migraine list exposes to the menu bar.
/// Published with `focusedSceneValue` so `AppCommands` acts on whatever
/// window is frontmost instead of on app-level state.
struct MigraineListActions {
    let hasSelection: Bool
    let editSelected: () -> Void
    let deleteSelected: () -> Void
    let exportCSV: () -> Void
}

extension FocusedValues {
    @Entry var newMigraine: (() -> Void)?
    @Entry var refreshMigraines: (() -> Void)?
    @Entry var selectedTab: Binding<Int>?
    @Entry var migraineListActions: MigraineListActions?
}
