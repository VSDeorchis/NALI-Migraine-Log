class MigraineViewModel: ObservableObject {
    // ... existing properties ...
    private let connectivityManager = WatchConnectivityManager.shared
    
    @Published private(set) var migraines: [MigraineEvent] = []
    
    init(context: NSManagedObjectContext) {
        self.context = context
        fetchMigraines()
    }
    
    @MainActor
    func fetchMigraines() {
        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        context.perform {
        do {
                let result = try self.context.fetch(request)
                Task { @MainActor in
                    self.migraines = result
                }
        } catch {
                print("Watch fetch error: \(error)")
            }
        }
    }

    func requestInitialSync() {
        connectivityManager.requestFullSync()
    }
    
    func saveMigraine(_ migraine: MigraineEvent) async {
        do {
            try await context.perform {
                try self.context.save()
                self.fetchMigraines()  // Refresh the list after saving
                
                // After saving locally, sync to phone
                self.connectivityManager.sendMigraineData(migraine)
            }
        } catch {
            print("Error saving migraine: \(error)")
        }
    }
} 