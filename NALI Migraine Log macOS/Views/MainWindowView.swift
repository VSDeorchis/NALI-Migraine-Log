import SwiftUI

/// Unused placeholder view. The macOS app uses MacContentView as its main view.
struct MainWindowView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var showingSettings = false
    
    var body: some View {
        Text("NALI Migraine Log")
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
    }
}
