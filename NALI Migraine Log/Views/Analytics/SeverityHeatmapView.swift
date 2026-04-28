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
    
    /// Width of the grid's container, captured from a background
    /// `GeometryReader`. We use this to scale `cellSize` so the
    /// heatmap fills its card on iPad instead of clumping against the
    /// leading edge. A value of 0 means "not measured yet" — the
    /// first render uses `minCellSize` until the preference callback
    /// fires.
    @State private var measuredWidth: CGFloat = 0
    
    /// Days per week. Named rather than hard-coded so the transposed
    /// layout below reads clearly (7 = number of *rows*, i.e. weekday
    /// labels and cells-per-week, not columns).
    private let daysPerWeek = 7
    /// Lower bound for the cell size. Matches the compact iPhone
    /// layout we've shipped since the heatmap was introduced.
    private let minCellSize: CGFloat = 14
    /// Upper bound for the cell size on wider containers (iPad full
    /// screen, Split View with a generous detail column, etc.).
    /// Without a ceiling, a 3-month heatmap on a 12.9" iPad would
    /// stretch each cell into a tile the size of a postage stamp and
    /// lose the "density overview" character of the heatmap. Bumped
    /// from the earlier 28pt cap so the transposed landscape grid
    /// actually fills the wide Analytics card on iPad instead of
    /// clumping into the middle.
    private let maxCellSize: CGFloat = 48
    private let cellSpacing: CGFloat = 3
    
    private var calendar: Calendar { .current }
    
    /// Per-cell size, derived from the card's measured width and the
    /// number of visible week columns (+ one leading column for the
    /// weekday labels). Scales linearly between `minCellSize` and
    /// `maxCellSize` so the grid fills the container's horizontal
    /// space when the period is long enough; shorter periods center
    /// their narrower grid inside the card rather than blowing each
    /// cell up to absurd sizes. Falls back to `minCellSize` during
    /// the first layout pass before `measuredWidth` has been
    /// reported.
    private var cellSize: CGFloat {
        let columnCount = max(1, weekColumns.count + 1) // +1 = weekday-label column
        guard measuredWidth > 0 else { return minCellSize }
        let totalSpacing = cellSpacing * CGFloat(columnCount - 1)
        let perCell = (measuredWidth - totalSpacing) / CGFloat(columnCount)
        return max(minCellSize, min(maxCellSize, perCell))
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
    
    /// Transposed (GitHub-contribution-style) heatmap: weekday labels
    /// stack vertically as a leading column, then each calendar week
    /// becomes its own column of 7 day-cells to the right. This is a
    /// much better fit than the previous 7-cols-by-N-rows portrait
    /// layout for the Analytics card, which is landscape-oriented
    /// everywhere the heatmap appears (iPhone card full width, iPad
    /// card even more so). Rendering weeks as columns lets the grid
    /// grow horizontally as the period grows instead of stretching
    /// into a tall narrow strip that clumps against the card's
    /// vertical center line.
    private var grid: some View {
        let columnsSlice = weekColumns
        // Cache per-render so every cell + header label uses the same
        // size for this layout pass (avoids any race if `measuredWidth`
        // changes mid-render).
        let size = cellSize
        let cornerRadius = max(3, size * 0.22)
        // Scale the weekday label font proportionally to the cell so
        // the "S M T W T F S" column doesn't read as tiny 9pt text
        // next to 48pt tiles on iPad.
        let headerFontSize = max(9, min(13, size * 0.5))
        
        // The inner HStack is the actual grid (weekday labels + week
        // columns). Its natural width is `columnCount × cellSize +
        // spacings`. We wrap it in an outer HStack with leading and
        // trailing `Spacer()`s so the outer HStack *always* takes the
        // full proposed width — the grid itself stays at its natural
        // width and the spacers distribute leftover horizontal space
        // symmetrically. This pattern also sidesteps a known SwiftUI
        // quirk where `GeometryReader` inside `.background` on a
        // `.frame(maxWidth: .infinity)`-wrapped HStack reports the
        // HStack's *intrinsic* width instead of the expanded frame,
        // which was causing the heatmap to measure ~390pt on an
        // ~780pt iPad card and render at half-width.
        let innerGrid = HStack(alignment: .top, spacing: cellSpacing) {
            // Leading weekday-label column.
            VStack(alignment: .center, spacing: cellSpacing) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: headerFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: size, height: size)
                }
            }
            
            // One VStack per calendar week, 7 cells tall.
            ForEach(columnsSlice.indices, id: \.self) { weekIndex in
                VStack(spacing: cellSpacing) {
                    ForEach(0..<daysPerWeek, id: \.self) { dayIndex in
                        let cell = columnsSlice[weekIndex][dayIndex]
                        if let cell {
                            cellView(for: cell,
                                     size: size,
                                     cornerRadius: cornerRadius)
                        } else {
                            Color.clear.frame(width: size, height: size)
                        }
                    }
                }
            }
        }
        
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            innerGrid
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(
            // Measure the outer full-width HStack (not the intrinsic
            // inner grid) so `cellSize` scales to the real card width
            // on iPad. Using the `content:`-less `.background(_:)`
            // overload keeps the geometry reader out of the layout
            // pass that determines the HStack's size.
            GeometryReader { geo in
                Color.clear
                    .preference(key: HeatmapWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(HeatmapWidthKey.self) { newValue in
            // Guard against layout-loop oscillation: only commit when
            // the reported width moves by more than a half-point.
            if abs(newValue - measuredWidth) > 0.5 {
                measuredWidth = newValue
            }
        }
    }
    
    @ViewBuilder
    private func cellView(for cell: DailyPainCell?,
                          size: CGFloat,
                          cornerRadius: CGFloat) -> some View {
        let isSelected = cell != nil && cell?.date == selected?.date
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor(for: cell))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

/// Carries the grid container's measured width from the background
/// `GeometryReader` up to `SeverityHeatmapView`'s `@State` so `cellSize`
/// can scale to fill available horizontal space. Private because no
/// other view needs to consume it.
private struct HeatmapWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
