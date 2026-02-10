import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var viewModel: MigraineViewModel
    @Binding var showingNewMigraine: Bool
    @Binding var selectedTab: Int
    
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Migraine") {
                showingNewMigraine = true
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Divider()
            
            Button("Settings...") {
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.keyWindow?.firstResponder?
                    .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
        
        CommandMenu("View") {
            Button("Refresh Data") {
                viewModel.fetchMigraines()
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Divider()
            
            Button("Migraine Log") {
                selectedTab = 0
            }
            .keyboardShortcut("1", modifiers: .command)
            
            Button("Calendar") {
                selectedTab = 1
            }
            .keyboardShortcut("2", modifiers: .command)
            
            Button("Predict") {
                selectedTab = 2
            }
            .keyboardShortcut("3", modifiers: .command)
            
            Button("Analytics") {
                selectedTab = 3
            }
            .keyboardShortcut("4", modifiers: .command)
            
            Button("About") {
                selectedTab = 4
            }
            .keyboardShortcut("5", modifiers: .command)
        }
        
        CommandMenu("Help") {
            Button("Visit Website") {
                if let url = URL(string: "https://www.neuroli.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("Contact Support") {
                if let url = URL(string: "tel:5164664700") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
} 