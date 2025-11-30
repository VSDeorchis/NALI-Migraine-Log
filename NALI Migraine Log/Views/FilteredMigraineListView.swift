import SwiftUI
import CoreData

struct FilteredMigraineListView: View {
    let viewModel: MigraineViewModel
    let title: String
    let migraines: [MigraineEvent]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List(migraines) { migraine in
            NavigationLink {
                MigraineDetailView(
                    migraine: migraine,
                    viewModel: viewModel,
                    dismiss: { dismiss() }
                )
            } label: {
                MigraineRowView(viewModel: viewModel, migraine: migraine)
            }
        }
        .navigationTitle(title)
        .onAppear {
            print("Filtered migraines count: \(migraines.count)")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let viewModel = MigraineViewModel(context: context)
    return FilteredMigraineListView(
        viewModel: viewModel,
        title: "Test Filter",
        migraines: []
    )
    .environment(\.managedObjectContext, context)
} 