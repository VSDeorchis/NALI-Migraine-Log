import SwiftUI
import UIKit

struct MigraineRowView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @ObservedObject private var settings = SettingsManager.shared
    let migraine: MigraineEvent
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"  // e.g., "Monday, Jan 15, 2025"
        return formatter
    }()
    
    // Helper to get active triggers
    private var activeTriggers: [String] {
        var triggers: [String] = []
        if migraine.isTriggerStress { triggers.append("Stress") }
        if migraine.isTriggerLackOfSleep { triggers.append("Lack of Sleep") }
        if migraine.isTriggerDehydration { triggers.append("Dehydration") }
        if migraine.isTriggerWeather { triggers.append("Weather") }
        if migraine.isTriggerHormones { triggers.append("Hormones") }
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
        if migraine.tookUbrelvy { medications.append("Ubrelvy") }
        if migraine.tookReyvow { medications.append("Reyvow") }
        if migraine.tookTrudhesa { medications.append("Trudhesa") }
        if migraine.tookElyxyb { medications.append("Elyxyb") }
        if migraine.tookOther { medications.append("Other") }
        return medications
    }
    
    // Get valid weather icon name from weather code
    private var weatherIconName: String {
        weatherIconForCode(Int(migraine.weatherCode))
    }
    
    // Local copy of weather icon mapping to avoid @MainActor issues
    private func weatherIconForCode(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.rain.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    
    var body: some View {
        #if DEBUG
        let _ = NSLog("🔷 [MigraineRowView] body computed for migraine: \(migraine.id?.uuidString ?? "nil")")
        let _ = NSLog("🔷 [MigraineRowView] hasWeatherData: \(migraine.hasWeatherData)")
        #endif
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header row with date and pain level
            HStack(alignment: .center, spacing: 12) {
                // Pain level indicator circle
                ZStack {
                    Circle()
                        .fill(painLevelColor(Int(migraine.painLevel)).gradient)
                        .frame(width: 44, height: 44)
                    
                    VStack(spacing: 0) {
                        Text("\(migraine.painLevel)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("pain")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .accessibilityLabel("Pain level \(migraine.painLevel) out of 10, \(painSeverityDescription)")
                
                // Date and location
                VStack(alignment: .leading, spacing: 2) {
                    if let startTime = migraine.startTime {
                        Text(dateFormatter.string(from: startTime))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(migraine.location ?? "Unknown")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Weather icon (if available)
                if migraine.hasWeatherData {
                    VStack(spacing: 2) {
                        Image(systemName: weatherIconName)
                            .font(.system(size: 22))
                            .foregroundColor(weatherIconColor(for: migraine.weatherCode))
                        
                        Text(settings.formatTemperature(migraine.weatherTemperature))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Weather: \(WeatherService.weatherCondition(for: Int(migraine.weatherCode))), \(settings.formatTemperature(migraine.weatherTemperature))")
                    .accessibilityHint(weatherAccessibilityHint)
                }
            }
            .padding(.bottom, 8)
            
            // Compact info row
            HStack(spacing: 8) {
                // Symptoms count
                if hasAnySymptoms {
                    CompactBadge(
                        icon: "exclamationmark.triangle.fill",
                        text: "\(symptomCount)",
                        color: .purple
                    )
                }
                
                // Triggers count
                if !activeTriggers.isEmpty {
                    CompactBadge(
                        icon: "bolt.fill",
                        text: "\(activeTriggers.count)",
                        color: .orange
                    )
                }
                
                // Medications count
                if !activeMedications.isEmpty {
                    CompactBadge(
                        icon: "pill.fill",
                        text: "\(activeMedications.count)",
                        color: .blue
                    )
                }
                
                // Pressure change indicator (show if >= 1.5 mmHg, which is ~2 hPa)
                if migraine.hasWeatherData && abs(migraine.weatherPressureChange24h) >= 2 {
                    let pressureChangeValue = settings.convertPressure(migraine.weatherPressureChange24h)
                    HStack(spacing: 3) {
                        Image(systemName: pressureChangeValue > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text(String(format: "%.1f", abs(pressureChangeValue)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(pressureChangeColor(migraine.weatherPressureChange24h))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pressureChangeColor(migraine.weatherPressureChange24h).opacity(0.15))
                    .clipShape(Capsule())
                }
                
                Spacer()
            }
            
            // Notes preview (if available)
            if let userNotes = viewModel.getUserNotes(from: migraine),
               !userNotes.isEmpty {
                Text(userNotes)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(.systemGray4).opacity(0.5),
                            Color(.systemGray5).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    // Helper computed properties
    private var hasAnySymptoms: Bool {
        migraine.hasAura || migraine.hasPhotophobia || migraine.hasPhonophobia ||
        migraine.hasNausea || migraine.hasVomiting || migraine.hasWakeUpHeadache ||
        migraine.hasTinnitus || migraine.hasVertigo
    }
    
    // Accessibility helpers
    private var painSeverityDescription: String {
        switch migraine.painLevel {
        case 1...3: return "mild"
        case 4...6: return "moderate"
        case 7...8: return "severe"
        case 9...10: return "very severe"
        default: return ""
        }
    }
    
    private var weatherAccessibilityHint: String {
        let pressureChange = migraine.weatherPressureChange24h
        let pressureChangeValue = settings.convertPressure(pressureChange)
        let unitName = settings.pressureUnit == .mmHg ? "millimeters of mercury" : "hectopascals"
        if abs(pressureChange) >= 5 {
            return "Significant pressure change of \(String(format: "%.1f", abs(pressureChangeValue))) \(unitName) in 24 hours"
        } else if abs(pressureChange) >= 2 {
            return "Moderate pressure change of \(String(format: "%.1f", abs(pressureChangeValue))) \(unitName) in 24 hours"
        }
        return ""
    }
    
    private var symptomCount: Int {
        var count = 0
        if migraine.hasAura { count += 1 }
        if migraine.hasPhotophobia { count += 1 }
        if migraine.hasPhonophobia { count += 1 }
        if migraine.hasNausea { count += 1 }
        if migraine.hasVomiting { count += 1 }
        if migraine.hasWakeUpHeadache { count += 1 }
        if migraine.hasTinnitus { count += 1 }
        if migraine.hasVertigo { count += 1 }
        return count
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
    
    private func getAdditionalSymptomsList() -> String? {
        var symptoms: [String] = []
        if migraine.hasWakeUpHeadache { symptoms.append("Wake up Headache") }
        if migraine.hasTinnitus { symptoms.append("Tinnitus") }
        if migraine.hasVertigo { symptoms.append("Vertigo") }
        return symptoms.isEmpty ? nil : symptoms.joined(separator: ", ")
    }
    
    private func weatherIconColor(for code: Int16) -> Color {
        switch code {
        case 0, 1: return .yellow
        case 2: return .orange
        case 3: return .gray
        case 45, 48: return .gray
        case 51...57: return .blue
        case 61...67: return .blue
        case 71...77: return .cyan
        case 80...86: return .blue
        case 95...99: return .purple
        default: return .gray
        }
    }
    
    private func pressureChangeColor(_ change: Double) -> Color {
        if abs(change) < 2 {
            return .green
        } else if abs(change) < 5 {
            return .orange
        } else {
            return .red
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? .infinity,
            height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(rows.count - 1)
        )
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        
        for row in rows {
            var x = bounds.minX
            for subview in row.subviews {
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: subview.sizeThatFits(.unspecified).width, height: row.height)
                )
                x += subview.sizeThatFits(.unspecified).width + spacing
            }
            y += row.height + spacing
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()
        var x: CGFloat = 0
        
        let maxWidth = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > maxWidth && !currentRow.subviews.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
                x = 0
            }
            
            currentRow.subviews.append(subview)
            currentRow.height = max(currentRow.height, size.height)
            x += size.width + spacing
        }
        
        if !currentRow.subviews.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    struct Row {
        var subviews: [LayoutSubview] = []
        var height: CGFloat = 0
    }
}

// Compact badge for counts
struct CompactBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// Add custom symptom tag style
struct SymptomTag: View {
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        Label {
            Text(title)
                .font(.system(.caption, design: .rounded))
        } icon: {
            Image(systemName: systemImage)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
} 
