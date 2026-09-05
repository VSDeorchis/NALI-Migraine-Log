import SwiftUI

// Supporting views, chart point models and helpers used by `StatisticsView`.

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// Data Models
struct FrequencyPoint: Identifiable {
    let id = UUID()
    let month: String
    let count: Int
}

struct PainLevelPoint: Identifiable {
    let id = UUID()
    let level: Int
    let count: Int
}

struct TriggerPoint: Identifiable {
    let id = UUID()
    let trigger: String
    let count: Int
}

struct MedicationPoint: Identifiable {
    let id = UUID()
    let medication: String
    let count: Int
}

struct TimeOfDayPoint: Identifiable {
    let id = UUID()
    let timeOfDay: String
    let count: Int
}

struct QualityOfLifePoint: Identifiable {
    let id = UUID()
    let type: String
    let count: Int
}

struct MonthlyPoint: Identifiable {
    let id = UUID()
    let month: Date
    let count: Int
}

/// Compact `ContentUnavailableView` sized to sit where a chart would be,
/// so cards keep a stable height when a period has no data.
struct ChartEmptyState: View {
    let title: String
    var systemImage: String = "chart.bar.xaxis"
    var message: String = "Try a different time range, or log a migraine to start seeing this chart."
    var height: CGFloat = 200

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .scaledFont(size: 15, weight: .semibold, design: .rounded)
        } description: {
            Text(message)
                .scaledFont(size: 13)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .accessibilityElement(children: .combine)
    }
}

/// "Based on N entries" footnote under a chart so users can judge how
/// much weight to give a pattern.
struct SampleSizeLabel: View {
    let count: Int
    var noun: String = "entry"
    var suffix: String? = nil

    private var pluralNoun: String {
        noun.hasSuffix("y") && count != 1
            ? String(noun.dropLast()) + "ies"
            : (count == 1 ? noun : noun + "s")
    }

    private var text: String {
        let base = "Based on \(count) \(pluralNoun)"
        guard let suffix else { return base }
        return "\(base) \(suffix)"
    }

    var body: some View {
        Text(text)
            .scaledFont(size: 12)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Visual system

/// One accent per data domain so a colour always means the same thing
/// across the dashboard and its drill-downs.
enum AnalyticsDomain {
    case frequency
    case severity
    case health
    case cycle
    case weather
    case medication

    var accent: Color {
        switch self {
        case .frequency:  return .blue
        case .severity:   return .orange
        case .health:     return .teal
        case .cycle:      return Color(red: 214/255, green: 72/255, blue: 118/255)
        case .weather:    return .cyan
        case .medication: return .purple
        }
    }
}

/// Flat grouped surface shared by every dashboard card. No stroke or
/// drop shadow — hierarchy comes from typography and spacing.
struct AnalyticsSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func analyticsSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(AnalyticsSurface(cornerRadius: cornerRadius))
    }
}

/// Card header: optional symbol tinted with the domain accent, a title
/// and an optional trailing view (count, badge, menu).
struct AnalyticsSectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        systemImage: String? = nil,
        accent: Color = .primary,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.trailing = trailing
    }

    init(
        _ title: String,
        systemImage: String? = nil,
        accent: Color = .primary
    ) where Trailing == EmptyView {
        self.init(title, systemImage: systemImage, accent: accent) { EmptyView() }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(accent)
            }
            Text(title)
                .scaledFont(size: 16, weight: .semibold, design: .rounded)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// "Details ›" marker for cards that navigate somewhere, so a summary
/// reads as a link rather than a static tile. Hidden from VoiceOver —
/// the enclosing `NavigationLink` already announces itself as a button.
struct DetailsAffordance: View {
    var label: String? = "Details"

    var body: some View {
        HStack(spacing: 3) {
            if let label {
                Text(label)
                    .scaledFont(size: 12, weight: .medium, design: .rounded)
            }
            Image(systemName: "chevron.right")
                .scaledFont(size: 11, weight: .semibold)
        }
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}

// Supporting Views
struct ChartSection<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = .primary
    var showsDetailsAffordance = false
    @ViewBuilder let content: () -> Content
    
    init(
        title: String,
        systemImage: String? = nil,
        accent: Color = .primary,
        showsDetailsAffordance: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.showsDetailsAffordance = showsDetailsAffordance
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                AnalyticsSectionHeader(title, systemImage: systemImage, accent: accent) {
                    if showsDetailsAffordance {
                        DetailsAffordance()
                    }
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .analyticsSurface()
        .padding(.horizontal, 16)
    }
}

/// Whether a change is good news for the user. Fewer migraine days is
/// favourable; fewer migraine-free days is not — the caller decides.
enum TrendSentiment {
    case favorable
    case unfavorable
    case neutral

    var tint: Color {
        switch self {
        case .favorable:   return .green
        case .unfavorable: return .orange
        case .neutral:     return .secondary
        }
    }
}

/// Compact "▼ 2 vs last period" pill with semantic colour.
struct TrendChip: View {
    let direction: StatBox.TrendDirection
    let sentiment: TrendSentiment

    private var symbol: String {
        switch direction {
        case .up:   return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .same: return "arrow.right"
        }
    }

    private var text: String {
        switch direction {
        case .up(let detail), .down(let detail): return detail
        case .same: return "No change"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .scaledFont(size: 9, weight: .bold)
            Text(text)
                .scaledFont(size: 11, weight: .semibold, design: .rounded)
        }
        .foregroundStyle(sentiment.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(sentiment.tint.opacity(0.12), in: Capsule())
        .lineLimit(1)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch direction {
        case .up(let detail):   return "Up, \(detail)"
        case .down(let detail): return "Down, \(detail)"
        case .same:             return "No change from the previous period"
        }
    }
}

/// The single headline number on the dashboard.
struct HeroMetricCard: View {
    let title: String
    let value: String
    let unit: String
    var context: String? = nil
    var trend: StatBox.TrendDirection? = nil
    var trendSentiment: TrendSentiment = .neutral
    var accent: Color = AnalyticsDomain.frequency.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .tracking(0.6)
                    .scaledFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                DetailsAffordance()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .scaledFont(size: 48, weight: .bold, design: .rounded)
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .scaledFont(size: 17, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let trend {
                    TrendChip(direction: trend, sentiment: trendSentiment)
                }
                if let context {
                    Text(context)
                        .scaledFont(size: 12)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .analyticsSurface()
        .accessibilityElement(children: .combine)
    }
}

/// Compact secondary KPI. Value first, label under it, optional
/// trend chip. Sized to sit three or four to a row.
struct KPIChip: View {
    let title: String
    let value: String
    var detail: String? = nil
    var trend: StatBox.TrendDirection? = nil
    var trendSentiment: TrendSentiment = .neutral
    var accent: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text(value)
                    .scaledFont(size: 22, weight: .bold, design: .rounded)
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                DetailsAffordance(label: nil)
                    .padding(.top, 4)
            }
            Text(title)
                .scaledFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let trend {
                TrendChip(direction: trend, sentiment: trendSentiment)
            } else if let detail {
                Text(detail)
                    .scaledFont(size: 11)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .analyticsSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

/// "Based on N entries · 72% complete" style footer under a card.
struct AnalyticsFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(size: 11)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Horizontal gauge of acute-medication days per 30 days with the
/// reference bands drawn behind the marker. Reports, never diagnoses.
struct MedicationDaysGauge: View {
    let daysPerMonth: Double
    private let maximum: Double = 20

    private var band: AcuteMedicationBand { .band(daysPerMonth: daysPerMonth) }

    private var tint: Color {
        switch band {
        case .low:      return .green
        case .moderate: return .yellow
        case .frequent: return .orange
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let moderateX = width * CGFloat(Double(AcuteMedicationBand.moderateThreshold) / maximum)
            let frequentX = width * CGFloat(Double(AcuteMedicationBand.frequentThreshold) / maximum)
            let markerX = width * CGFloat(min(daysPerMonth, maximum) / maximum)
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Capsule().fill(Color.green.opacity(0.25)).frame(width: moderateX)
                    Capsule().fill(Color.yellow.opacity(0.3)).frame(width: frequentX - moderateX)
                    Capsule().fill(Color.orange.opacity(0.3))
                }
                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    .offset(x: max(0, markerX - 7))
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var trend: TrendDirection? = nil
    var trendSentiment: TrendSentiment = .neutral
    
    enum TrendDirection {
        case up(String)    // e.g. "up from 3"
        case down(String)  // e.g. "down from 8"
        case same
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .scaledFont(size: 22, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            
            Text(title)
                .scaledFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            if let trend {
                TrendChip(direction: trend, sentiment: trendSentiment)
            } else if let subtitle {
                Text(subtitle)
                    .scaledFont(size: 11)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .analyticsSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

struct MonthDetailView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) private var dismiss
    let month: Date
    
    private var migrainesForMonth: [MigraineEvent] {
        let calendar = Calendar.current
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return calendar.isDate(startTime, equalTo: month, toGranularity: .month)
        }.sorted { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }
    }
    
    var body: some View {
        List(migrainesForMonth) { migraine in
            NavigationLink {
                MigraineDetailView(
                    migraine: migraine, 
                    viewModel: viewModel,
                    dismiss: { dismiss() }
                )
            } label: {
                MigraineRowView(viewModel: viewModel, migraine: migraine)
            }
        }
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
    }
}


// Add extension to convert between TimeFrame types
extension StatisticsView.TimeFilter {
    var toViewModelTimeFrame: MigraineViewModel.TimeFrame {
        switch self {
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .range: return .week // Fallback mapping
        }
    }
}

// MARK: - Impact Badge
struct ImpactBadge: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .scaledFont(size: 20)
                    .foregroundStyle(color)
                
                Text("\(count)")
                    .scaledFont(size: 22, weight: .bold, design: .rounded)
                    .foregroundStyle(.primary)
                
                Text(label)
                    .scaledFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
