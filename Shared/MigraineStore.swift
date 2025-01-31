import Foundation
import WatchConnectivity

@MainActor
class MigraineStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = MigraineStore()
    
    @Published private(set) var migraines: [MigraineEvent] = []
    private let saveKey = "migraines"
    private var session: WCSession?
    
    // Get the documents directory URL
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // Create a specific file URL for our data
    private var migrainesFileURL: URL {
        documentsDirectory.appendingPathComponent("migraines.json")
    }
    
    override init() {
        super.init()
        print("MigraineStore initializing...")
        if WCSession.isSupported() {
            print("WCSession is supported")
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            
            #if os(iOS)
            print("iOS App - Watch App Installed: \(session?.isWatchAppInstalled ?? false)")
            #else
            print("Watch App - iOS App Installed: \(session?.isCompanionAppInstalled ?? false)")
            #endif
        } else {
            print("WCSession is not supported")
        }
        loadMigraines()
    }
    
    func addMigraine(_ migraine: MigraineEvent) {
        migraines.append(migraine)
        saveMigraines()
        sendMigraineToCounterpart(migraine)
    }
    
    func updateMigraine(_ migraine: MigraineEvent) {
        if let index = migraines.firstIndex(where: { $0.id == migraine.id }) {
            migraines[index] = migraine
            saveMigraines()
        }
    }
    
    func removeMigraine(_ migraine: MigraineEvent) {
        migraines.removeAll { $0.id == migraine.id }
        saveMigraines()
    }
    
    private func sendMigraineToCounterpart(_ migraine: MigraineEvent) {
        guard let session = session else {
            print("No session available")
            return
        }
        
        guard session.activationState == .activated else {
            print("Session not activated. Current state: \(session.activationState.rawValue)")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(migraine)
            #if os(iOS)
            if session.isWatchAppInstalled {
                print("iOS: Attempting to send migraine to watch")
                session.sendMessage(["migraine": data], replyHandler: { reply in
                    print("iOS: Watch confirmed receipt: \(reply)")
                }) { error in
                    print("iOS: Error sending to watch: \(error.localizedDescription)")
                }
            } else {
                print("iOS: Watch app not installed")
            }
            #else
            if session.isCompanionAppInstalled {
                print("Watch: Attempting to send migraine to phone")
                session.sendMessage(["migraine": data], replyHandler: { reply in
                    print("Watch: Phone confirmed receipt: \(reply)")
                }) { error in
                    print("Watch: Error sending to phone: \(error.localizedDescription)")
                }
            } else {
                print("Watch: Phone app not installed")
            }
            #endif
        } catch {
            print("Error encoding migraine: \(error.localizedDescription)")
        }
    }
    
    private func syncAllMigraines() {
        guard let session = session, session.activationState == .activated else { return }
        
        if let data = try? JSONEncoder().encode(migraines) {
            #if os(iOS)
            if session.isWatchAppInstalled {
                session.sendMessage(["allMigraines": data], replyHandler: nil) { error in
                    print("Error syncing to watch: \(error.localizedDescription)")
                }
            }
            #else
            if session.isCompanionAppInstalled {
                session.sendMessage(["allMigraines": data], replyHandler: nil) { error in
                    print("Error syncing to phone: \(error.localizedDescription)")
                }
            }
            #endif
        }
    }
    
    func saveMigraines() {
        do {
            let data = try JSONEncoder().encode(migraines)
            try data.write(to: migrainesFileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Error saving migraines: \(error)")
        }
    }
    
    private func loadMigraines() {
        do {
            let data = try Data(contentsOf: migrainesFileURL)
            migraines = try JSONDecoder().decode([MigraineEvent].self, from: data)
        } catch {
            print("Error loading migraines: \(error)")
            migraines = []
        }
    }
    
    // WCSessionDelegate methods
    private static nonisolated func getCurrentDevice() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(watchOS)
        return "Watch"
        #else
        return "Unknown"
        #endif
    }
    
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let device = Self.getCurrentDevice()
        print("\(device): Session activation completed - State: \(activationState.rawValue)")
        
        if let error = error {
            print("\(device): Activation error: \(error.localizedDescription)")
            return
        }
        
        if activationState == .activated {
            Task { @MainActor in
                print("\(device): Initiating full sync")
                self.syncAllMigraines()
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let device = Self.getCurrentDevice()
        print("\(device): Received message")
        
        if let data = message["migraine"] as? Data {
            print("\(device): Decoding received migraine")
            if let migraine = try? JSONDecoder().decode(MigraineEvent.self, from: data) {
                Task { @MainActor in
                    print("\(device): Adding received migraine")
                    self.migraines.append(migraine)
                    self.saveMigraines()
                }
            } else {
                print("\(device): Failed to decode migraine")
            }
        } else if let data = message["allMigraines"] as? Data {
            if let newMigraines = try? JSONDecoder().decode([MigraineEvent].self, from: data) {
                Task { @MainActor in
                    self.migraines = newMigraines
                    self.saveMigraines()
                    print("Received and saved all migraines (no reply)")
                }
            }
        }
    }
    
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("Session became inactive")
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("Session deactivated")
        session.activate()
    }
    #endif
    
    // Statistics
    var migrainesLastMonth: Int {
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        return migraines.filter { $0.startTime >= oneMonthAgo }.count
    }
    
    var averageMigrainesPerMonth: Double {
        let calendar = Calendar.current
        guard let oldestMigraine = migraines.map({ $0.startTime }).min() else { return 0 }
        let months = calendar.dateComponents([.month], from: oldestMigraine, to: Date()).month ?? 1
        return Double(migraines.count) / Double(max(1, months))
    }
    
    var abortiveMedicationUseCount: Int {
        migraines.reduce(0) { $0 + $1.medications.count }
    }
    
    var averageDuration: TimeInterval? {
        let durations = migraines.compactMap { $0.duration }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }
    
    var shortestDuration: TimeInterval? {
        migraines.compactMap { $0.duration }.min()
    }
    
    var longestDuration: TimeInterval? {
        migraines.compactMap { $0.duration }.max()
    }
    
    var medicationUsageCounts: [(Medication, Int)] {
        var counts: [Medication: Int] = [:]
        
        for migraine in migraines {
            for medication in migraine.medications {
                counts[medication, default: 0] += 1
            }
        }
        
        return counts.sorted { $0.value > $1.value }
    }
}