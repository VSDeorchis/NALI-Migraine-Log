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
    
    /// When non-nil, the selected cell is highlighted and the legend shows
    /// the date + pain detail. Reset on outside tap.
    @State private var selected: DailyPainCell?
    
    private let columns = 7
    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 3
    
    private var calendar: Calendar { .current }
    
    /// Cells padded with leading "blank" entries so the first row begins at
    /// the correct weekday column. We use `nil` placeholders to preserve
    /// the alignment without polluting the data model.
    private var paddedCells: [DailyPainCell?] {
        guard let first = cells.first else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first.date) // 1 = Sunday
        let leadingBlanks = max(0, firstWeekday - 1)
        return Array(repeating: nil, count: leadingBlanks) + cells.map { Optional($0) }
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
                Label("Severity Heatmap", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                if let selected = selected {
                    Text(selectedSummary(for: selected))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(periodSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            grid
            
            legend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Severity heatmap")
        .accessibilityValue(periodSummary)
    }
    
    // MARK: - Grid
    
    private var grid: some View {
        let totalRows = Int((Double(paddedCells.count) / Double(columns)).rounded(.up))
        return VStack(alignment: .leading, spacing: cellSpacing) {
            HStack(spacing: cellSpacing) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: cellSize)
                }
            }
            ForEach(0..<totalRows, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        if index < paddedCells.count {
                            cellView(for: paddedCells[index])
                        } else {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func cellView(for cell: DailyPainCell?) -> some View {
        let isSelected = cell != nil && cell?.date == selected?.date
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor(for: cell))
            .frame(width: cellSize, height: cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.6) : Color.clear,
                                  lineWidth: 1.5)
            )
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
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
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
    
    private func selectedSummary(for cell: DailyPainCell) -> String {
        let dateText = cell.date.formatted(.dateTime.month(.abbreviated).day())
        if cell.worstPain == 0 {
            return "\(dateText) · migraine-free"
        }
        let suffix = cell.migraineCount > 1 ? " (\(cell.migraineCount))" : ""
        return "\(dateText) · pain \(cell.worstPain)\(suffix)"
    }
}

#Preview {
    let cal = Calendar.current
    let now = Date()
    let start = cal.date(byAdding: .day, value: -41, to: now)!
    let interval = DateInterval(start: cal.startOfDay(for: start),
                                end: cal.startOfDay(for: now))
    
    let cells: [DailyPainCell] = (0...41).map { offset in
        let date = cal.date(byAdding: .day, value: offset, to: interval.start)!
        let pain = (offset % 5 == 0) ? 8 : (offset % 7 == 0 ? 4 : 0)
        return DailyPainCell(date: date,
                             worstPain: pain,
                             migraineCount: pain > 0 ? 1 : 0)
    }
    
    return SeverityHeatmapView(cells: cells)
        .padding()
}
