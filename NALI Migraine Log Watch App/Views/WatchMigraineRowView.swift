struct WatchMigraineRowView: View {
    let migraine: MigraineEvent
    
    var body: some View {
        VStack(alignment: .leading) {
            if let startTime = migraine.startTime {
                Text(startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
            }
            
            HStack {
                Text("Pain: \(migraine.painLevel)")
                    .foregroundColor(painColor(level: Int(migraine.painLevel)))
                Spacer()
                Text(migraine.location ?? "Unknown")
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