import SwiftUI

struct MigraineRowView: View {
    let migraine: MigraineEvent
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"  // e.g., "Monday, Jan 15, 2025"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateFormatter.string(from: migraine.startTime))
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack {
                Label("Pain Level: \(migraine.painLevel)", systemImage: "thermometer")
                    .foregroundColor(painLevelColor(migraine.painLevel))
                    .font(.caption)
                Spacer()
                Text(migraine.location.rawValue)
                    .font(.caption)
            }
            
            if !migraine.triggers.isEmpty {
                Text("Triggers: \(migraine.triggers.map { $0.rawValue }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Main symptoms with icons
            if migraine.hasAura || migraine.hasPhotophobia || migraine.hasPhonophobia ||
               migraine.hasNausea || migraine.hasVomiting {
                HStack {
                    if migraine.hasAura {
                        Label("Aura", systemImage: "sparkles")
                    }
                    if migraine.hasPhotophobia {
                        Label("Light", systemImage: "sun.max")
                    }
                    if migraine.hasPhonophobia {
                        Label("Sound", systemImage: "speaker.wave.2")
                    }
                    if migraine.hasNausea {
                        Label("Nausea", systemImage: "face.dashed")
                    }
                    if migraine.hasVomiting {
                        Label("Vomiting", systemImage: "cross.case")
                    }
                }
                .font(.caption)
            }
            
            // Additional symptoms as text
            let additionalSymptoms = getAdditionalSymptomsList()
            if !additionalSymptoms.isEmpty {
                Text("Additional Symptoms: \(additionalSymptoms)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !migraine.medications.isEmpty {
                Text("Medications: \(migraine.medications.map { $0.rawValue }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = migraine.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func getAdditionalSymptomsList() -> String {
        var symptoms: [String] = []
        if migraine.hasWakeUpHeadache { symptoms.append("Wake up Headache") }
        if migraine.hasTinnitus { symptoms.append("Tinnitus") }
        if migraine.hasVertigo { symptoms.append("Vertigo/Dysequilibrium") }
        return symptoms.joined(separator: ", ")
    }
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return Color(.systemGreen)
        case 4...6: return Color(.systemYellow)
        case 7...8: return Color(.systemOrange)
        case 9...10: return Color(.systemRed)
        default: return Color(.systemGray)
        }
    }
} 