struct MainWindowView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var showingSettings = false
    
    var body: some View {
        // ... existing view code ...
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
} 