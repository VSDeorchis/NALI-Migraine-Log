struct MigraineListView: View {
    @ObservedObject var viewModel: MigraineViewModel
    
    var body: some View {
        List(viewModel.migraines) { migraine in
            MigraineRowView(migraine: migraine)
        }
        .onAppear {
            viewModel.fetchMigraines()  // Refresh when view appears
        }
    }
} 