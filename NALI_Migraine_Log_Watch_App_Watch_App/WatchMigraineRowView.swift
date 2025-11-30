struct WatchMigraineRowView: View {
    let migraine: MigraineEvent
    @State private var isPressed = false
    
    // Cache formatted date to avoid repeated formatting
    private var formattedDate: String {
        if let startTime = migraine.startTime {
            return Self.dateFormatter.string(from: startTime)
        }
        return "Unknown Date"
    }
    
    // Make formatter static to share across instances
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Use cached date string
            Text(formattedDate)
                .font(.system(.headline, design: .rounded))
                .minimumScaleFactor(0.8)
            
            // Use ViewBuilder to conditionally show content
            painAndLocationView
            symptomsView
        }
        .padding(.vertical, 2) // Reduce padding for better list density
        .contentShape(Rectangle()) // Improve tap target
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // Add haptic feedback and visual response to touches
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .pressEvents(onPress: {
            isPressed = true
            WKInterfaceDevice.current().play(.click)
        }, onRelease: {
            isPressed = false
            WKInterfaceDevice.current().play(.directionUp)
        })
        .onTapGesture {
            // Play success haptic when tapped
            WKInterfaceDevice.current().play(.success)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            // Play notification haptic for long press
            WKInterfaceDevice.current().play(.notification)
        }
    }
    
    @ViewBuilder
    private var painAndLocationView: some View {
        HStack(spacing: 6) {
            Label {
                Text("\(migraine.painLevel)")
            } icon: {
                Image(systemName: "thermometer")
                    .foregroundStyle(painLevelColor(Int(migraine.painLevel)))
            }
            .font(.system(.caption, design: .rounded))
            .onTapGesture {
                playPainLevelHaptic(Int(migraine.painLevel))
            }
            
            if let location = migraine.location, !location.isEmpty {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(location)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(1)
            }
        }
    }
    
    @ViewBuilder
    private var symptomsView: some View {
        if migraine.hasAura || migraine.hasPhotophobia || migraine.hasNausea {
            HStack(spacing: 8) {
                ForEach(symptoms, id: \.self) { symptom in
                    Image(systemName: symptom.icon)
                        .foregroundStyle(.blue)
                        .font(.caption2)
                        .symbolEffect(.pulse)
                        .onTapGesture {
                            // Play different haptics for different symptoms
                            switch symptom {
                            case .aura:
                                WKInterfaceDevice.current().play(.directionUp)
                            case .photophobia:
                                WKInterfaceDevice.current().play(.click)
                            case .nausea:
                                WKInterfaceDevice.current().play(.directionDown)
                            }
                        }
                }
            }
        }
    }
    
    // Compute symptoms once
    private var symptoms: [Symptom] {
        var result: [Symptom] = []
        if migraine.hasAura { result.append(.aura) }
        if migraine.hasPhotophobia { result.append(.photophobia) }
        if migraine.hasNausea { result.append(.nausea) }
        return result
    }
    
    private enum Symptom: String, CaseIterable {
        case aura = "sparkles"
        case photophobia = "sun.max"
        case nausea = "face.dashed"
        
        var icon: String { rawValue }
    }
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    // Accessibility support
    private var accessibilityLabel: String {
        var components: [String] = []
        components.append("Migraine on \(formattedDate)")
        components.append("Pain level \(migraine.painLevel)")
        if let location = migraine.location {
            components.append("Location: \(location)")
        }
        if migraine.hasAura { components.append("with aura") }
        if migraine.hasPhotophobia { components.append("with light sensitivity") }
        if migraine.hasNausea { components.append("with nausea") }
        return components.joined(separator: ", ")
    }
    
    // Add pressure event handling
    private func pressEvents(
        onPress: @escaping () -> Void = {},
        onRelease: @escaping () -> Void = {}
    ) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onPress()
                }
                .onEnded { _ in
                    onRelease()
                }
        )
    }
    
    // Add haptics for different pain levels
    private func playPainLevelHaptic(_ level: Int) {
        switch level {
        case 1...3:
            WKInterfaceDevice.current().play(.success)
        case 4...6:
            WKInterfaceDevice.current().play(.click)
        case 7...8:
            WKInterfaceDevice.current().play(.directionUp)
        case 9...10:
            WKInterfaceDevice.current().play(.notification)
        default:
            break
        }
    }
}

// Preview provider
struct WatchMigraineRowView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let migraine = MigraineEvent(context: context)
        migraine.startTime = Date()
        migraine.painLevel = 5
        migraine.location = "Frontal"
        migraine.hasAura = true
        
        return WatchMigraineRowView(migraine: migraine)
    }
} 