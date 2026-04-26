import SwiftUI
import WatchConnectivity
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct WatchMigraineRowView: View {
    let migraine: MigraineEvent
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    private var activeTriggers: [String] {
        migraine.orderedTriggers.map(\.displayName)
    }

    private var activeMedications: [String] {
        migraine.orderedMedications.map(\.displayName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Safely handle the start time
            if let startTime = migraine.startTime {
                Text(dateFormatter.string(from: startTime))
                    .font(.headline)
            } else {
                Text("Unknown Time")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Pain level with safe integer conversion
            Text("Pain: \(migraine.painLevel)")
                .font(.subheadline)
            
            // Safely handle location
            if let location = migraine.location {
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show active triggers
            let triggers = activeTriggers
            if !triggers.isEmpty {
                Text(triggers.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            // Show active medications
            let medications = activeMedications
            if !medications.isEmpty {
                Text(medications.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.purple)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func painColor(level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
} 
