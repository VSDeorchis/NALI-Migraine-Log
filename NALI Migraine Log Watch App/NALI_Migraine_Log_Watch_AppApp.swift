import SwiftUI
import CoreData
import WatchConnectivity

@main
struct NALI_Migraine_Log_Watch_AppApp: App {
    @StateObject private var viewModel: MigraineViewModel
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    let persistenceController = PersistenceController.shared
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: MigraineViewModel(context: context))
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                WatchMigraineLogView(viewModel: viewModel)  // Use our main watch view
            }
            .environmentObject(viewModel)
            .environmentObject(connectivityManager)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
} 