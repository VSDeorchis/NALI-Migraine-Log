import SwiftUI
import WatchConnectivity
// Add import if models are in a separate module
// import NALIMigraineLogShared

struct WatchMigraineRowView: View {
    let migraine: MigraineEvent
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(migraine.startTime.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
            
            HStack {
                Text("Pain: \(migraine.painLevel)")
                    .foregroundColor(painColor(level: migraine.painLevel))
                Spacer()
                Text(migraine.location.rawValue)
            }
            .font(.caption2)
        }
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