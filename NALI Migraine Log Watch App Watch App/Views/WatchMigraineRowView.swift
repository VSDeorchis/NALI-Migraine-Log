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
    
    // Helper to get active triggers
    private var activeTriggers: [String] {
        var triggers: [String] = []
        if migraine.isTriggerStress { triggers.append("Stress") }
        if migraine.isTriggerLackOfSleep { triggers.append("Lack of Sleep") }
        if migraine.isTriggerDehydration { triggers.append("Dehydration") }
        if migraine.isTriggerWeather { triggers.append("Weather") }
        if migraine.isTriggerHormones { triggers.append("Menstrual") }
        if migraine.isTriggerAlcohol { triggers.append("Alcohol") }
        if migraine.isTriggerCaffeine { triggers.append("Caffeine") }
        if migraine.isTriggerFood { triggers.append("Food") }
        if migraine.isTriggerExercise { triggers.append("Exercise") }
        if migraine.isTriggerScreenTime { triggers.append("Screen Time") }
        if migraine.isTriggerOther { triggers.append("Other") }
        return triggers
    }
    
    // Helper to get active medications
    private var activeMedications: [String] {
        var medications: [String] = []
        if migraine.tookIbuprofin { medications.append("Ibuprofen") }
        if migraine.tookExcedrin { medications.append("Excedrin") }
        if migraine.tookTylenol { medications.append("Tylenol") }
        if migraine.tookSumatriptan { medications.append("Sumatriptan") }
        if migraine.tookRizatriptan { medications.append("Rizatriptan") }
        if migraine.tookNaproxen { medications.append("Naproxen") }
        if migraine.tookFrovatriptan { medications.append("Frovatriptan") }
        if migraine.tookNaratriptan { medications.append("Naratriptan") }
        if migraine.tookNurtec { medications.append("Nurtec") }
        if migraine.tookSymbravo { medications.append("Symbravo") }
        if migraine.tookUbrelvy { medications.append("Ubrelvy") }
        if migraine.tookReyvow { medications.append("Reyvow") }
        if migraine.tookTrudhesa { medications.append("Trudhesa") }
        if migraine.tookElyxyb { medications.append("Elyxyb") }
        if migraine.tookOther { medications.append("Other") }
        return medications
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
