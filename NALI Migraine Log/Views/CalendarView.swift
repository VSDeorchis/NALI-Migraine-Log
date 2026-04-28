import SwiftUI
import CoreData

private struct CalendarDay: Identifiable {
    let id: Int
    let date: Date?
}

struct CalendarView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()
    @State private var selectedMigraine: MigraineEvent?
    @State private var showingNewMigraine = false
    /// iPad-only: the day the right pane is currently focused on.
    /// `nil` means "show the whole month" instead of a specific day.
    @State private var selectedDay: Date?
    
    /// Drives the side-by-side layout on iPad. iPhone keeps the
    /// existing single-column flow with NavigationLink-based pushes.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    iPadBody
                } else {
                    iPhoneBody
                }
            }
            .navigationTitle("Calendar")
            .sheet(isPresented: $showingNewMigraine) {
                NewMigraineView(viewModel: viewModel)
            }
            .onChange(of: selectedDate) {
                // Moving to a new month invalidates whatever day was
                // pinned on the right pane.
                if let day = selectedDay,
                   !calendar.isDate(day, equalTo: selectedDate, toGranularity: .month) {
                    selectedDay = nil
                }
            }
        }
    }
    
    // MARK: - iPhone (compact)
    
    private var iPhoneBody: some View {
        VStack(spacing: 20) {
            monthSelector
            daysOfWeekHeader
            calendarGrid()
            CalendarLegend()
                .padding(.horizontal)
            
            // Month-scoped detail list. Earlier this section listed
            // `viewModel.migraines` (every entry the user had ever
            // logged) while the empty-state copy below claimed "No
            // migraines this month" — a real bug that made the page
            // contradict itself the moment the user navigated to
            // any month other than the current one. Both branches
            // now agree on `migrainesInVisibleMonth`.
            monthMigraineList
        }
    }
    
    // MARK: - iPad (regular)
    
    /// Side-by-side calendar (left) and day or month migraine list
    /// (right). Mirrors how iPadOS Calendar puts the month grid
    /// alongside the day's events instead of stacking them.
    ///
    /// The left column used to be `VStack { … calendarGrid; Spacer() }`
    /// with the grid's `DayCell`s hard-coded to a 44pt height. On an
    /// iPad that meant the month grid only consumed ~300pt at the top
    /// of the screen and the `Spacer` ate the rest — the calendar
    /// visually "only took up the upper half". We now measure the
    /// available vertical space with a `GeometryReader` and pass a
    /// computed per-row height into the grid so each week row splits
    /// the remaining column height evenly. The 44pt floor guards
    /// against the initial zero-size layout pass and extremely short
    /// Split View windows.
    private var iPadBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                monthSelector
                    .padding(.top, 8)
                daysOfWeekHeader
                GeometryReader { geo in
                    let rowCount = max(daysInMonth().count / 7, 1)
                    let rowSpacing: CGFloat = 8
                    let availableHeight = geo.size.height
                    let rowHeight = max(
                        44,
                        (availableHeight - rowSpacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
                    )
                    calendarGrid(cellHeight: rowHeight, rowSpacing: rowSpacing)
                }
                CalendarLegend()
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            iPadDetailColumn
                .frame(width: 380)
                .background(Color(.systemGroupedBackground))
        }
    }
    
    @ViewBuilder
    private var iPadDetailColumn: some View {
        if let day = selectedDay {
            let dayMigraines = migrainesForDate(day)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.formatted(date: .complete, time: .omitted))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        if dayMigraines.isEmpty {
                            Text("No migraines logged")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(dayMigraines.count) migraine\(dayMigraines.count == 1 ? "" : "s")")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        selectedDay = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show whole month")
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                if dayMigraines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 36))
                            .foregroundColor(.green.opacity(0.6))
                        Text("Migraine-free day")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(dayMigraines) { migraine in
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
                    .listStyle(.plain)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(dateFormatter.string(from: selectedDate))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                let monthMigraines = migrainesInVisibleMonth
                if monthMigraines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 36))
                            .foregroundColor(.green.opacity(0.6))
                        Text("No migraines this month")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("Tap a day to focus on it.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(monthMigraines) { migraine in
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
                    .listStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Shared chrome
    
    private var monthSelector: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }
            
            Text(dateFormatter.string(from: selectedDate))
                .font(.title2)
                .frame(maxWidth: .infinity)
            
            Button(action: {
                selectedDate = Date()
            }) {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .padding(.horizontal)
    }
    
    private var daysOfWeekHeader: some View {
        LazyVGrid(columns: columns, spacing: 15) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// The shared calendar grid. On iPad, cells are buttons that pin
    /// the right pane to that day; on iPhone, cells push DayDetailView.
    ///
    /// `cellHeight` — when non-nil, overrides each cell's default 44pt
    /// height. Used by the iPad layout to stretch the grid vertically
    /// so it fills the available column height instead of leaving a
    /// large empty band below the last week.
    /// `rowSpacing` — vertical spacing between week rows; callers that
    /// supply a custom `cellHeight` typically also tighten this so the
    /// rows visually "belong together" at larger cell heights.
    @ViewBuilder
    private func calendarGrid(cellHeight: CGFloat? = nil, rowSpacing: CGFloat = 15) -> some View {
        let isPad = horizontalSizeClass == .regular
        LazyVGrid(columns: columns, spacing: rowSpacing) {
            ForEach(daysInMonth(), id: \.self) { date in
                if let date = date {
                    DayCell(
                        date: date,
                        migraines: migrainesForDate(date),
                        viewModel: viewModel,
                        isSelected: isPad && (selectedDay.map {
                            calendar.isDate($0, inSameDayAs: date)
                        } ?? false),
                        onTap: isPad ? { selectedDay = date } : nil,
                        cellHeight: cellHeight
                    )
                } else {
                    // Keep the leading/trailing empty slots the same
                    // height as their populated neighbors so every row
                    // in the grid has a consistent baseline.
                    if let cellHeight {
                        Color.clear.frame(height: cellHeight)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var monthMigraineList: some View {
        let monthMigraines = migrainesInVisibleMonth
        if !monthMigraines.isEmpty {
            List(monthMigraines) { migraine in
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
        } else {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundColor(.green.opacity(0.6))
                Text("No migraines this month")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Text("Tap any day to see details")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func previousMonth() {
        selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
    }
    
    private func nextMonth() {
        selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
    }
    
    private func daysInMonth() -> [Date?] {
        let range = calendar.range(of: .day, in: .month, for: selectedDate)!
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        var days: [Date?] = []
        
        // Add empty days at start
        for _ in 0..<(firstWeekday - 1) {
            days.append(nil)
        }
        
        // Add days of month
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        // Add empty days at end
        let remainingDays = (7 - (days.count % 7)) % 7
        for _ in 0..<remainingDays {
            days.append(nil)
        }
        
        return days
    }
    
    private func migrainesForDate(_ date: Date) -> [MigraineEvent] {
        viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return calendar.isDate(startTime, inSameDayAs: date)
        }
    }

    /// Migraines whose `startTime` falls in the same calendar month as
    /// `selectedDate`, sorted newest-first. Backs both the bottom list
    /// and the "No migraines this month" empty state, so they always
    /// agree about what "this month" means as the user pages through.
    private var migrainesInVisibleMonth: [MigraineEvent] {
        viewModel.migraines
            .filter { migraine in
                guard let startTime = migraine.startTime else { return false }
                return calendar.isDate(startTime, equalTo: selectedDate, toGranularity: .month)
            }
            .sorted { lhs, rhs in
                (lhs.startTime ?? .distantPast) > (rhs.startTime ?? .distantPast)
            }
    }
    
    private func printDebugInfo() {
        AppLogger.ui.debug("CalendarView migraine count=\(viewModel.migraines.count, privacy: .public)")
    }
}

struct DayCell: View {
    let date: Date
    let migraines: [MigraineEvent]
    @ObservedObject var viewModel: MigraineViewModel
    /// Visual selection state (iPad only — the iPhone cell never sets
    /// this since it pushes immediately). Drives the outer ring drawn
    /// underneath the day's content.
    var isSelected: Bool = false
    /// When set, the cell becomes a `Button` that fires this closure
    /// (used by the iPad side-by-side layout). When `nil`, the cell
    /// falls back to its long-standing `NavigationLink` behavior so
    /// the iPhone keeps pushing `DayDetailView` on tap.
    var onTap: (() -> Void)? = nil
    /// Optional height override for the cell's frame. iPad stretches
    /// each week row to fill the available column height (computed in
    /// `CalendarView.iPadBody` via `GeometryReader`) and passes that
    /// per-row height in here. iPhone omits this and gets the 44pt
    /// default that matches the long-standing compact layout.
    var cellHeight: CGFloat? = nil
    
    private var maxPainLevel: Int16 {
        migraines.map(\.painLevel).max() ?? 0
    }
    
    /// Severity bucket for the day's worst migraine. Single source of
    /// truth for the calendar dot's color so it cannot drift from the
    /// ranges that drive the Severity Heatmap, the Analytics bar chart
    /// buckets, the HealthKit headache severity mapping, and the
    /// notification copy. Returns `nil` for pain 0 / no migraines.
    private var severityBucket: SeverityBucket? {
        SeverityBucket.bucket(for: Int(maxPainLevel))
    }
    
    private var painColor: Color {
        severityBucket?.color ?? .clear
    }
    
    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cellContent
                }
                .buttonStyle(.plain)
                // Trackpad hover bubbles for iPad — circular shape so
                // the highlight reads as "this day", not a square cell.
                .hoverEffect(.highlight)
            } else {
                NavigationLink(destination: DayDetailView(date: date, migraines: migraines, viewModel: viewModel)) {
                    cellContent
                }
            }
        }
    }
    
    private var cellContent: some View {
        // When the iPad layout stretches cells, scale the inner
        // indicators proportionally so a 34pt dot doesn't float lost
        // in the middle of a 120pt cell. iPhone's 44pt default keeps
        // the original sizes byte-for-byte.
        let baseHeight = cellHeight ?? 44
        let indicatorSize = min(max(baseHeight * 0.72, 34), 64)
        let selectionSize = min(max(baseHeight * 0.85, 40), 72)
        let isToday = Calendar.current.isDateInToday(date)
        
        return ZStack {
            // Selection ring (iPad). Drawn behind everything else so
            // the existing pain-level dot still reads on top.
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: selectionSize, height: selectionSize)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: selectionSize, height: selectionSize)
            }
            
            if !migraines.isEmpty {
                // 0.7 opacity — enough saturation that a "severe 8"
                // day actually reads as orange (matching the legend
                // swatch and the Severity Heatmap on the Analytics
                // tab) without crushing the contrast of the day
                // number drawn on top. The heatmap can afford its
                // higher 0.85 opacity because its cells have no
                // overlaid text.
                Circle()
                    .fill(painColor.opacity(0.7))
                    .frame(width: indicatorSize, height: indicatorSize)
            }
            
            if isToday {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: indicatorSize, height: indicatorSize)
                
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: indicatorSize, height: indicatorSize)
            }
            
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(isToday ? .blue : .primary)
                
                if migraines.count > 1 {
                    Text("\(migraines.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 12, height: 12)
                        .background(painColor)
                        .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: baseHeight)
        .contentShape(Rectangle())
    }
}

// MARK: - Calendar Legend

/// Legend for the calendar's day-dot color ramp. Driven directly from
/// `SeverityBucket.allCases` + `SeverityBucket.color` so the legend,
/// the calendar dots, the Severity Heatmap, and the Analytics charts
/// cannot drift apart — updating the canonical `SeverityBucket.color`
/// ripples through every surface at once.
///
/// The swatches use the same `0.7` fill opacity as the calendar day
/// dots (see `DayCell.cellContent`) so a user comparing a swatch to a
/// dot sees byte-identical colors, not a pale dot next to a richer
/// swatch.
struct CalendarLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(SeverityBucket.allCases) { bucket in
                legendItem(
                    color: bucket.color,
                    label: "\(bucket.title) (\(bucket.rangeDescription))"
                )
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

struct DayDetailView: View {
    let date: Date
    let migraines: [MigraineEvent]
    @ObservedObject var viewModel: MigraineViewModel
    
    var body: some View {
        List(migraines) { migraine in
            MigraineRowView(viewModel: viewModel, migraine: migraine)
        }
        .navigationTitle(date.formatted(date: .complete, time: .omitted))
    }
}

struct MigraineSummaryCard: View {
    let migraine: MigraineEvent
    
    private var activeMedications: [String] {
        migraine.orderedMedications.map(\.displayName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(migraine.startTime!, style: .time)
                    .font(.headline)
                if let duration = migraine.duration {
                    Text("(\(Int(duration/3600))h \(Int((duration.truncatingRemainder(dividingBy: 3600))/60))m)")
                        .foregroundColor(.secondary)
                } else {
                    Text("(Ongoing)")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Pain: \(migraine.painLevel)/10")
                    .font(.subheadline)
                    .padding(4)
                    .background(painLevelColor.opacity(0.2))
                    .cornerRadius(4)
            }
            
            let medications = activeMedications
            if !medications.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(medications, id: \.self) { medication in
                            Text(medication)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
        .padding(.horizontal)
    }
    
    private var painLevelColor: Color {
        switch migraine.painLevel {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return CalendarView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 

