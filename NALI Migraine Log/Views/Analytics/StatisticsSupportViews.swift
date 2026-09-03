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

// Supporting Views
struct ChartSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .scaledFont(size: 17, weight: .semibold, design: .rounded)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            
            content()
                .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var trend: TrendDirection? = nil
    
    enum TrendDirection {
        case up(String)    // e.g. "up from 3"
        case down(String)  // e.g. "down from 8"
        case same
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .scaledFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Text(value)
                .scaledFont(size: 24, weight: .bold, design: .rounded)
                .foregroundStyle(Color(red: 68/255, green: 130/255, blue: 180/255))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .scaledFont(size: 10, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            if let trend = trend {
                trendLabel(trend)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 68/255, green: 130/255, blue: 180/255).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .shadow(color: Color(red: 68/255, green: 130/255, blue: 180/255).opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    @ViewBuilder
    private func trendLabel(_ trend: TrendDirection) -> some View {
        switch trend {
        case .up(let detail):
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.right")
                    .scaledFont(size: 9, weight: .bold)
                Text(detail)
                    .scaledFont(size: 9, weight: .medium, design: .rounded)
            }
            .foregroundStyle(.red)
        case .down(let detail):
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.right")
                    .scaledFont(size: 9, weight: .bold)
                Text(detail)
                    .scaledFont(size: 9, weight: .medium, design: .rounded)
            }
            .foregroundStyle(.green)
        case .same:
            HStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .scaledFont(size: 9, weight: .bold)
                Text("No change")
                    .scaledFont(size: 9, weight: .medium, design: .rounded)
            }
            .foregroundStyle(.secondary)
        }
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

// Add helper extension for date generation
extension Calendar {
    func generateDates(
        inside interval: DateInterval,
        matching components: DateComponents
    ) -> [Date] {
        var dates: [Date] = []
        dates.append(interval.start)
        
        enumerateDates(
            startingAfter: interval.start,
            matching: components,
            matchingPolicy: .nextTime
        ) { date, _, stop in
            if let date = date {
                if date < interval.end {
                    dates.append(date)
                } else {
                    stop = true
                }
            }
        }
        
        return dates
    }
}
