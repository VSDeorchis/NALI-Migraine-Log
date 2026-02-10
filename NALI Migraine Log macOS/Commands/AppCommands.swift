import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var viewModel: MigraineViewModel
    @Binding var showingNewMigraine: Bool
    @Binding var selectedTab: Int
    
    var body: some Commands {
        // File menu
        CommandGroup(after: .newItem) {
            Button("New Migraine") {
                showingNewMigraine = true
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Divider()
            
            Button("Export All Data…") {
                exportAllData()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            
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
        
        // Help menu
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
            
            Divider()
            
            Text("Keyboard Shortcuts")
                .font(.caption)
            
            Group {
                Text("⌘N  New Migraine")
                Text("⌘1-5  Switch Views")
                Text("⌘R  Refresh Data")
                Text("⌘I  Toggle Inspector")
                Text("⇧⌘E  Export Data")
                Text("⌘,  Settings")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    private func exportAllData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Headway_Export_\(dateStamp()).csv"
        panel.title = "Export All Migraine Data"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var csv = "Date,Time,Pain Level,Location,Duration,Triggers,Medications,Notes\n"
            
            for m in viewModel.migraines {
                let date = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? ""
                let time = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
                let pain = "\(m.painLevel)"
                let location = m.location ?? ""
                var duration = ""
                if let s = m.startTime, let e = m.endTime {
                    let mins = Int(e.timeIntervalSince(s) / 60)
                    let h = mins / 60; let min = mins % 60
                    duration = h > 0 ? "\(h)h \(min)m" : "\(min)m"
                }
                let triggers = m.selectedTriggerNames.joined(separator: "; ")
                let medications = m.selectedMedicationNames.joined(separator: "; ")
                let notes = (m.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                
                csv += "\"\(date)\",\"\(time)\",\(pain),\"\(location)\",\"\(duration)\",\"\(triggers)\",\"\(medications)\",\"\(notes)\"\n"
            }
            
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
