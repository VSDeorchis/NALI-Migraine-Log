import SwiftUI

/// Menu-bar commands. Everything here targets the key window through
/// `FocusedValues` (see `MacFocusedValues.swift`), so items are disabled
/// when no window — or no migraine list — can handle them.
struct AppCommands: Commands {
    @FocusedValue(\.newMigraine) private var newMigraine
    @FocusedValue(\.refreshMigraines) private var refreshMigraines
    @FocusedValue(\.selectedTab) private var selectedTab
    @FocusedValue(\.migraineListActions) private var listActions
    
    var body: some Commands {
        // File menu
        CommandGroup(after: .newItem) {
            Button("New Migraine") {
                newMigraine?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newMigraine == nil)
            
            Divider()
            
            Button("Export Entries as CSV…") {
                listActions?.exportCSV()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(listActions == nil)
            
            Divider()
            
            Button("Settings…") {
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        // Edit menu
        CommandGroup(after: .pasteboard) {
            Divider()
            
            Button("Edit Migraine") {
                listActions?.editSelected()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(listActions?.hasSelection != true)
            
            Button("Delete Migraine…") {
                listActions?.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(listActions?.hasSelection != true)
        }
        
        // Sidebar
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NSApp.keyWindow?.firstResponder?
                    .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
        
        // View menu
        CommandMenu("View") {
            Button("Refresh Data") {
                refreshMigraines?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshMigraines == nil)
            
            Divider()
            
            ForEach(MacDestination.allCases) { destination in
                Button(destination.title) {
                    selectedTab?.wrappedValue = destination.rawValue
                }
                .keyboardShortcut(destination.shortcutKey, modifiers: .command)
                .disabled(selectedTab == nil)
            }
        }
        
        // Help menu
        CommandMenu("Help") {
            Button("Visit Website") {
                NSWorkspace.shared.open(AppContactInfo.websiteURL)
            }

            Button("Contact Support") {
                if let url = URL(string: "tel:\(AppContactInfo.supportPhoneRaw)") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            // App Store + feedback. macOS doesn't have an in-app review
            // sheet equivalent we want to ship right now (SwiftUI's
            // `requestReview` action exists on macOS but the UX is much
            // less polished than on iOS), so both buttons here are
            // unconditional out-bound jumps. The "Send Feedback" path
            // uses a `mailto:` URL rather than the iOS in-app form
            // because AppKit/macOS users overwhelmingly prefer their
            // own configured mail client over an in-app composer.
            Button("Rate Headway on the App Store") {
                NSWorkspace.shared.open(AppContactInfo.appStoreWriteReviewURL)
            }

            Button("Send Feedback…") {
                let subject = "\(AppContactInfo.feedbackEmailSubjectPrefix) (macOS)"
                let mailto = "mailto:\(AppContactInfo.feedbackEmailAddress)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject)"
                if let url = URL(string: mailto) {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Privacy Policy") {
                NSWorkspace.shared.open(AppContactInfo.privacyPolicyURL)
            }

            Divider()

            Text("Keyboard Shortcuts")
                .font(.caption)
            
            Group {
                Text("⌘N  New Migraine")
                Text("⌘E  Edit Selected Migraine")
                Text("⌘⌫  Delete Selected Migraine")
                Text("⌘1-5  Switch Views")
                Text("⌘R  Refresh Data")
                Text("⌘I  Toggle Inspector")
                Text("⇧⌘E  Export Entries as CSV")
                Text("⌘,  Settings")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
}
