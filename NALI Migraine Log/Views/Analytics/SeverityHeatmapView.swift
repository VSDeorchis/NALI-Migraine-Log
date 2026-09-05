//
//  SeverityHeatmapView.swift
//  NALI Migraine Log
//
//  Calendar-style heatmap, one cell per day in the period. Cells inherit
//  their colour from `SeverityBucket`, and migraine-free days render as a
//  subtle grey background so users get an at-a-glance sense of how dense
//  their migraine days are without having to read individual numbers.
//

import SwiftUI

struct SeverityHeatmapView: View {
    /// Pre-computed via `[MigraineEvent].dailyPainCells(in:)`.
    let cells: [DailyPainCell]
    /// Start-of-day dates of logged cycle starts to mark on the grid.
    /// Empty for users without cycle insights; never persisted here.
    var cycleStartDays: Set<Date> = []
    var cycleAccent: Color = AnalyticsDomain.cycle.accent
    
    /// When non-nil, the selected cell is highlighted and the legend shows
    /// the date + pain detail. Reset on outside tap.
    @State private var selected: DailyPainCell?
    
    /// Days per week. Named rather than hard-coded so the transposed
    /// layout below reads clearly (7 = number of *rows*, i.e. weekday
    /// labels and cells-per-week, not columns).
    private let daysPerWeek = 7
    /// Upper bound for the cell size on wide containers (iPad full
    /// screen, short periods on a Plus-size iPhone). Without a ceiling
    /// a 4-week heatmap would stretch each cell into a postage stamp
    /// and lose the "density overview" character of the heatmap.
    private let maxCellSize: CGFloat = 44
    private let cellSpacing: CGFloat = 3
    private let cellCornerRadius: CGFloat = 4
    
    private var calendar: Calendar { .current }
    
    /// Widest the grid may grow before cells would exceed `maxCellSize`.
    /// Below this the grid stretches to fill the card; above it the grid
    /// stays leading-aligned so it lines up with the header and legend.
    private var maxGridWidth: CGFloat {
        let columnCount = weekColumns.count + 1 // +1 = weekday-label column
        return CGFloat(columnCount) * maxCellSize + CGFloat(columnCount - 1) * cellSpacing
    }
    
    /// Cells padded with leading "blank" entries so the first chunk of
    /// 7 begins at the correct weekday. We use `nil` placeholders to
    /// preserve the alignment without polluting the data model.
    private var paddedCells: [DailyPainCell?] {
        guard let first = cells.first else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first.date) // 1 = Sunday
        let leadingBlanks = max(0, firstWeekday - 1)
        return Array(repeating: nil, count: leadingBlanks) + cells.map { Optional($0) }
    }
    
    /// `paddedCells` grouped into week columns of 7 day-slots each
    /// (Sun…Sat, or the locale-rotated equivalent when the user's
    /// calendar starts the week on Monday). Drives the transposed
    /// GitHub-contribution-style grid: each element is one vertical
    /// column in the rendered heatmap, which lets the grid scale
    /// horizontally as the period grows instead of growing
    /// vertically into a tall narrow strip that wastes the
    /// card's horizontal space.
    private var weekColumns: [[DailyPainCell?]] {
        let flat = paddedCells
        guard !flat.isEmpty else { return [] }
        let totalWeeks = Int(ceil(Double(flat.count) / Double(daysPerWeek)))
        return (0..<totalWeeks).map { w in
            (0..<daysPerWeek).map { d in
                let idx = w * daysPerWeek + d
                return idx < flat.count ? flat[idx] : nil
            }
        }
    }
    
    private var weekdaySymbols: [String] {
        // Use the calendar's localized very-short symbols, then rotate so
        // we honour the user's first-day-of-week preference.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        let short = formatter.veryShortWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
        let firstWeekday = calendar.firstWeekday - 1   // index into 0..<7
        return Array(short[firstWeekday...] + short[..<firstWeekday])
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                AnalyticsSectionHeader("Severity Heatmap", systemImage: "calendar.badge.clock", accent: AnalyticsDomain.severity.accent)
                Spacer()
                if let selected = selected {
                    Text(selectedSummary(for: selected))
                        .scaledFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(periodSummary)
                        .scaledFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
            
            grid
            
            legend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Severity heatmap")
        .accessibilityValue(accessibilitySummary)
    }
    
    // MARK: - Grid
    
    /// Transposed (GitHub-contribution-style) heatmap: weekday labels
    /// stack vertically as a leading column, then each calendar week
    /// becomes its own column of 7 day-cells to the right. Every column
    /// is flexible and every cell is a square, so the grid divides the
    /// card's width evenly among the columns (up to `maxCellSize`)
    /// without measuring the container.
    private var grid: some View {
        let columnsSlice = weekColumns
        
        return HStack(alignment: .top, spacing: cellSpacing) {
            VStack(spacing: cellSpacing) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            
            ForEach(columnsSlice.indices, id: \.self) { weekIndex in
                VStack(spacing: cellSpacing) {
                    ForEach(0..<daysPerWeek, id: \.self) { dayIndex in
                        cellView(for: columnsSlice[weekIndex][dayIndex])
                    }
                }
            }
        }
        .frame(maxWidth: maxGridWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func cellView(for cell: DailyPainCell?) -> some View {
        let isSelected = cell != nil && cell?.date == selected?.date
        let isCycleStart = cell.map { cycleStartDays.contains($0.date) } ?? false
        RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
            .fill(fillColor(for: cell))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.6) : Color.clear,
                                  lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if isCycleStart {
                    Circle()
                        .fill(cycleAccent)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1))
                        .offset(x: 1, y: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let cell = cell else { return }
                if selected?.date == cell.date {
                    selected = nil
                } else {
                    selected = cell
                }
            }
    }
    
    private func fillColor(for cell: DailyPainCell?) -> Color {
        guard let cell = cell else { return Color.clear }
        guard let bucket = cell.bucket else {
            // Migraine-free day inside the period.
            return Color(.systemGray5).opacity(0.7)
        }
        return bucket.color.opacity(0.85)
    }
    
    // MARK: - Legend
    
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(SeverityBucket.allCases) { bucket in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bucket.color.opacity(0.85))
                        .frame(width: 10, height: 10)
                    Text(bucket.title)
                        .scaledFont(size: 10, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
            if !cycleStartDays.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(cycleAccent)
                        .frame(width: 8, height: 8)
                    Text("Period start")
                        .scaledFont(size: 10, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
    
    // MARK: - Summaries
    
    private var periodSummary: String {
        let migraineDays = cells.filter { $0.worstPain > 0 }.count
        let total = cells.count
        guard total > 0 else { return "No data" }
        return "\(migraineDays) of \(total) days"
    }
    
    private var accessibilitySummary: String {
        let marked = cells.filter { cycleStartDays.contains($0.date) }.count
        guard marked > 0 else { return periodSummary }
        return "\(periodSummary); \(marked) period start\(marked == 1 ? "" : "s") marked"
    }
    
    private func selectedSummary(for cell: DailyPainCell) -> String {
        let dateText = cell.date.formatted(.dateTime.month(.abbreviated).day())
        let cycleSuffix = cycleStartDays.contains(cell.date) ? " · period start" : ""
        if cell.worstPain == 0 {
            return "\(dateText) · migraine-free\(cycleSuffix)"
        }
        let suffix = cell.migraineCount > 1 ? " (\(cell.migraineCount))" : ""
        return "\(dateText) · pain \(cell.worstPain)\(suffix)\(cycleSuffix)"
    }
}

#Preview {
    let cal = Calendar.current
    let now = Date()
    let start = cal.date(byAdding: .day, value: -41, to: now) ?? now
    let interval = DateInterval(start: cal.startOfDay(for: start),
                                end: cal.startOfDay(for: now))
    
    let cells: [DailyPainCell] = (0...41).map { offset in
        let date = cal.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
        let pain = (offset % 5 == 0) ? 8 : (offset % 7 == 0 ? 4 : 0)
        return DailyPainCell(date: date,
                             worstPain: pain,
                             migraineCount: pain > 0 ? 1 : 0)
    }
    
    return SeverityHeatmapView(cells: cells)
        .padding()
}
