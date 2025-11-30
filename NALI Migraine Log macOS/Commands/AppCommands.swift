import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var viewModel: MigraineViewModel
    @Binding var showingNewMigraine: Bool
    
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Migraine") {
                showingNewMigraine = true
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Button("Settings...") {
                NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
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