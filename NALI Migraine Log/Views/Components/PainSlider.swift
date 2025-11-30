import SwiftUI

struct PainSlider: View {
    @Binding var value: Int16
    @State private var feedbackGenerator = UISelectionFeedbackGenerator()
    @State private var impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    @State private var lastWholeNumber: Int = 0
    
    private func currentColor(_ value: Double) -> Color {
        let normalizedValue = (value - 1.0) / 9.0 // Convert 1-10 to 0-1 range
        
        if normalizedValue <= 0.5 {
            // Interpolate from green to yellow
            return Color.interpolate(from: .green, to: .yellow, progress: normalizedValue * 2)
        } else {
            // Interpolate from yellow to red
            return Color.interpolate(from: .yellow, to: .red, progress: (normalizedValue - 0.5) * 2)
        }
    }
    
    private func checkTransitionPoints(_ newValue: Int16) {
        // Crossing into moderate pain (4)
        if lastWholeNumber < 4 && newValue >= 4 {
            impactGenerator.impactOccurred(intensity: 0.7)
        }
        // Crossing into severe pain (7)
        else if lastWholeNumber < 7 && newValue >= 7 {
            impactGenerator.impactOccurred(intensity: 1.0)
        }
        // Moving back down to moderate
        else if lastWholeNumber >= 7 && newValue < 7 {
            impactGenerator.impactOccurred(intensity: 0.7)
        }
        // Moving back down to mild
        else if lastWholeNumber >= 4 && newValue < 4 {
            impactGenerator.impactOccurred(intensity: 0.5)
        }
        
        lastWholeNumber = Int(newValue)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Pain Level: \(value)")
                    .font(.headline)
                Spacer()
                Text(painLevelDescription(value))
                    .font(.subheadline)
                    .foregroundColor(currentColor(Double(value)))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with current color
                    Rectangle()
                        .fill(currentColor(Double(value)))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    // Slider
                    Slider(value: Binding(
                        get: { Double(value) },
                        set: { newValue in
                            let roundedValue = Int16(newValue)
                            if roundedValue != value {
                                feedbackGenerator.selectionChanged()
                                checkTransitionPoints(roundedValue)
                            }
                            value = roundedValue
                        }
                    ), in: 1...10, step: 1)
                    .tint(.clear)
                }
            }
            .frame(height: 30)
            .onAppear {
                feedbackGenerator.prepare()
                impactGenerator.prepare()
                lastWholeNumber = Int(value)
            }
            
            HStack {
                Text("Mild")
                    .foregroundColor(.green)
                Spacer()
                Text("Moderate")
                    .foregroundColor(.yellow)
                Spacer()
                Text("Severe")
                    .foregroundColor(.red)
            }
            .font(.caption)
        }
    }
    
    private func painLevelDescription(_ level: Int16) -> String {
        switch level {
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        case 9...10: return "Very Severe"
        default: return "Unknown"
        }
    }
}

// Helper extension for color interpolation
extension Color {
    static func interpolate(from: Color, to: Color, progress: Double) -> Color {
        let clampedProgress = max(0, min(1, progress))
        
        // Convert colors to RGB components
        let fromComponents = from.components
        let toComponents = to.components
        
        // Interpolate each component
        let red = fromComponents.red + (toComponents.red - fromComponents.red) * clampedProgress
        let green = fromComponents.green + (toComponents.green - fromComponents.green) * clampedProgress
        let blue = fromComponents.blue + (toComponents.blue - fromComponents.blue) * clampedProgress
        
        return Color(red: red, green: green, blue: blue)
    }
    
    var components: (red: Double, green: Double, blue: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        
        guard let color = UIColor(self).cgColor.components else {
            return (0, 0, 0)
        }
        
        if color.count >= 3 {
            red = color[0]
            green = color[1]
            blue = color[2]
        }
        
        return (Double(red), Double(green), Double(blue))
    }
} 