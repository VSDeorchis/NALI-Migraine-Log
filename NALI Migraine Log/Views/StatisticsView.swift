import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var timeFilter: TimeFilter = .month
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Date?
    @State private var showingMonthDetail = false
    @State private var lastUpdateTime: Date = Date()
    @State private var selectedMedication: String?
    @State private var selectedTrigger: String?
    @State private var selectedTimeOfDay: String?
    @State private var selectedImpactType: String?
    @State private var selectedPainLevel: Int?
    
    @State private var isNavigating = false
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate: Date = Date()
    
    /// Owns the cached HealthKit-derived correlation stats. The dashboard
    /// triggers `load(window:migraines:)` whenever the filter or migraine
    /// list changes; the section view + drill-downs read from the store.
    @StateObject private var healthCorrelationStore = HealthCorrelationStore()
    
    /// `.regular` ≈ iPad in any orientation + iPhone Plus/Pro Max in
    /// landscape. Drives the adaptive KPI grid below: 2 columns on
    /// compact iPhone, 4 on iPad so the dashboard reads at-a-glance
    /// rather than as a single tall scrolling stack.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    /// Column descriptor for the KPI tile grid. `adaptive(minimum:)`
    /// would also work but tile widths look more balanced when we hand
    /// SwiftUI a fixed column count per size class.
    private var kpiGridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }
    
    enum TimeFilter: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case range = "Range"
    }
    
    @ViewBuilder
    private func medicationNavigationView() -> some View {
        if let medicationName = selectedMedication,
           let medication = MigraineMedication(displayName: medicationName) {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines with \(medicationName)",
                migraines: filteredMigraines.filter { $0.medications.contains(medication) }
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func triggerNavigationView() -> some View {
        if let triggerName = selectedTrigger,
           let trigger = MigraineTrigger(displayName: triggerName) {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines with \(triggerName)",
                migraines: filteredMigraines.filter { $0.triggers.contains(trigger) }
            )
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func timeOfDayNavigationView() -> some View {
        if let timeSlot = selectedTimeOfDay {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines in \(timeSlot)",
                migraines: filteredMigraines.filter { migraine in
                    guard let date = migraine.startTime else { return false }
                    let hour = Calendar.current.component(.hour, from: date)
                    switch timeSlot {
                    case "Morning": return (5..<12).contains(hour)
                    case "Afternoon": return (12..<17).contains(hour)
                    case "Evening": return (17..<22).contains(hour)
                    case "Night": return hour < 5 || hour >= 22
                    default: return false
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func impactNavigationView() -> some View {
        if let impactType = selectedImpactType {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: impactType,
                migraines: filteredMigraines.filter { migraine in
                    switch impactType {
                    case "Missed Work": return migraine.missedWork
                    case "Missed School": return migraine.missedSchool
                    case "Missed Events": return migraine.missedEvents
                    default: return false
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func painLevelNavigationView() -> some View {
        if let level = selectedPainLevel {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Pain Level \(level)",
                migraines: filteredMigraines.filter { migraine in
                    migraine.painLevel == level
                }
            )
        }
    }
    
    private var timeFilterView: some View {
        VStack {
            Picker("Time Filter", selection: $timeFilter) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            if timeFilter == .year {
                Picker("Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            } else if timeFilter == .range {
                VStack {
                    DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker("End", selection: $customEndDate, in: customStartDate...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
        }
    }
    
    private var summaryStatsView: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: kpiGridColumns, spacing: 16) {
                tileLink(
                    metric: .total,
                    StatBox(
                        title: "\(timeFilter.rawValue) Total",
                        value: String(totalMigraines),
                        trend: totalTrend
                    )
                )
                tileLink(
                    metric: .averagePain,
                    StatBox(
                        title: "Avg Pain",
                        value: String(format: "%.1f", averagePain),
                        trend: painTrend
                    )
                )
                tileLink(
                    metric: .severeDays,
                    StatBox(
                        title: "Severe Days",
                        value: String(severePainDays),
                        subtitle: severePainDays > 0 ? "Pain ≥ 7" : nil
                    )
                )
                tileLink(
                    metric: .streak,
                    StatBox(
                        title: "Migraine-free",
                        value: streakDisplayValue,
                        subtitle: streakDisplaySubtitle
                    )
                )
                tileLink(
                    metric: .averageDuration,
                    StatBox(title: "Avg Duration", value: formatDuration(averageDuration))
                )
                tileLink(
                    metric: .topTrigger,
                    StatBox(
                        title: "Top Trigger",
                        value: topTriggerDisplayValue,
                        subtitle: topTriggerDisplaySubtitle
                    )
                )
                tileLink(
                    metric: .missedDays,
                    StatBox(
                        title: "Days Missed",
                        value: String(totalImpactDays),
                        subtitle: totalImpactDays > 0 ? "work / school / events" : nil
                    )
                )
                tileLink(
                    metric: .topMedication,
                    StatBox(title: "Abortives Used", value: String(abortivesUsed))
                )
            }
            .padding(.horizontal)
        }
    }
    
    /// Wraps a `StatBox` in a `NavigationLink` whose value drives the
    /// per-metric drill-down handled by `AnalyticsMetricDetailView`.
    private func tileLink<Content: View>(metric: AnalyticsMetric, _ content: Content) -> some View {
        NavigationLink(value: metric) {
            content
        }
        .buttonStyle(.plain)
        // `.lift` is the card-style hover (slight scale + shadow)
        // appropriate for tappable tiles. Trackpad-only — no-op on
        // iPhone touch.
        .hoverEffect(.lift)
        .accessibilityHint("Opens \(metric.title) details")
    }
    
    // MARK: - Impact Summary
    
    private var impactSummaryView: some View {
        let missedWorkCount = filteredMigraines.filter { $0.missedWork }.count
        let missedSchoolCount = filteredMigraines.filter { $0.missedSchool }.count
        let missedEventsCount = filteredMigraines.filter { $0.missedEvents }.count
        let totalImpact = missedWorkCount + missedSchoolCount + missedEventsCount
        
        return Group {
            if totalImpact > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Life Impact", systemImage: "heart.slash.fill")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                    
                    HStack(spacing: 12) {
                        if missedWorkCount > 0 {
                            ImpactBadge(
                                icon: "briefcase.fill",
                                count: missedWorkCount,
                                label: "Work",
                                color: .red
                            ) {
                                selectedImpactType = "Missed Work"
                            }
                        }
                        if missedSchoolCount > 0 {
                            ImpactBadge(
                                icon: "graduationcap.fill",
                                count: missedSchoolCount,
                                label: "School",
                                color: .orange
                            ) {
                                selectedImpactType = "Missed School"
                            }
                        }
                        if missedEventsCount > 0 {
                            ImpactBadge(
                                icon: "calendar.badge.exclamationmark",
                                count: missedEventsCount,
                                label: "Events",
                                color: .purple
                            ) {
                                selectedImpactType = "Missed Events"
                            }
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(.systemGray5), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Trend Calculations
    
    private var totalTrend: StatBox.TrendDirection? {
        guard timeFilter != .range else { return nil }
        let current = currentPeriodMigraines
        let previous = previousPeriodMigraines
        if current > previous {
            return .up("\(current - previous) more")
        } else if current < previous {
            return .down("\(previous - current) fewer")
        } else {
            return .same
        }
    }
    
    private var painTrend: StatBox.TrendDirection? {
        guard timeFilter != .range else { return nil }
        let currentPain = averagePain
        let previousPain = previousPeriodAveragePain
        guard previousPain > 0 else { return nil }
        let diff = currentPain - previousPain
        if abs(diff) < 0.2 { return .same }
        if diff > 0 {
            return .up(String(format: "+%.1f", diff))
        } else {
            return .down(String(format: "%.1f", diff))
        }
    }
    
    private var previousPeriodAveragePain: Double {
        let calendar = Calendar.current
        let now = Date()
        
        let prevMigraines = viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            switch timeFilter {
            case .week:
                let lastWeekStart = calendar.date(byAdding: .day, value: -14, to: now)!
                let lastWeekEnd = calendar.date(byAdding: .day, value: -7, to: now)!
                return startTime >= lastWeekStart && startTime < lastWeekEnd
            case .month:
                let lastMonthStart = calendar.date(byAdding: .month, value: -2, to: now)!
                let lastMonthEnd = calendar.date(byAdding: .month, value: -1, to: now)!
                return startTime >= lastMonthStart && startTime < lastMonthEnd
            case .year:
                return calendar.component(.year, from: startTime) == selectedYear - 1
            case .range:
                return false
            }
        }
        guard !prevMigraines.isEmpty else { return 0 }
        return prevMigraines.reduce(0.0) { $0 + Double($1.painLevel) } / Double(prevMigraines.count)
    }
    
    private var chartsView: some View {
        LazyVStack(spacing: 20) {
            painLevelDistributionChart
            trendsSection
            insightsSection
            healthCorrelationsSection
            impactSummaryView
            weatherCorrelationButton
        }
    }
    
    /// Sleep + HRV correlation cards, hidden entirely when HealthKit
    /// isn't available on the device.
    private var healthCorrelationsSection: some View {
        HealthCorrelationsSectionView(
            store: healthCorrelationStore,
            onConnectTapped: {
                Task {
                    await HealthKitManager.shared.requestAuthorization()
                    refreshHealthCorrelations()
                }
            }
        )
    }
    
    // MARK: - New dashboard sections
    
    /// Heatmap + monthly distribution, the two charts that benefit most from
    /// living above the fold. The heatmap uses a 60-day window so the
    /// rendered grid stays roughly square on iPhone — long-range exploration
    /// happens via the year filter or per-metric drill-downs.
    private var trendsSection: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 20) {
                SeverityHeatmapView(cells: heatmapCells)
                Divider()
                    .padding(.horizontal, -8)
                monthlyDistributionInline
            }
        }
    }
    
    /// Auto-generated narrative insights drawn from the filtered period.
    /// Hidden entirely when no signal is strong enough — keeps the screen
    /// quiet on light data sets.
    private var insightsSection: some View {
        AnalyticsInsightsView(
            insights: AnalyticsInsightGenerator.generate(
                for: filteredMigraines,
                currentStreak: currentMigraineFreeStreak
            )
        )
    }
    
    /// Subset of `dailyPainCells` covering the heatmap window. Computed
    /// off the unfiltered `viewModel.migraines` so multi-month time filters
    /// (year/range) still see migraine-free days outside the filter.
    private var heatmapCells: [DailyPainCell] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        let start: Date = {
            switch timeFilter {
            case .week:
                return cal.date(byAdding: .day, value: -27, to: end) ?? end
            case .month:
                return cal.date(byAdding: .day, value: -41, to: end) ?? end
            case .year:
                let y = cal.date(byAdding: .day, value: -89, to: end) ?? end
                return y
            case .range:
                let clampedStart = cal.startOfDay(for: customStartDate)
                let clampedEnd   = cal.startOfDay(for: customEndDate)
                let span = cal.dateComponents([.day], from: clampedStart, to: clampedEnd).day ?? 0
                if span > 90 {
                    return cal.date(byAdding: .day, value: -89, to: clampedEnd) ?? clampedStart
                }
                return clampedStart
            }
        }()
        let interval = DateInterval(start: start, end: end)
        return viewModel.migraines.dailyPainCells(in: interval)
    }
    
    /// Compact monthly bar chart used inside the Trends card. Identical
    /// data to `monthlyDistributionChart` but unwrapped from its own
    /// `ChartSection` so it nests cleanly under the heatmap.
    private var monthlyDistributionInline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Migraines per month", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.blue)
            if monthlyData.isEmpty {
                Text("No data for this period.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Chart(monthlyData) { point in
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(monthlyBarColor(count: point.count).gradient)
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                }
                .frame(height: 160)
            }
        }
    }
    
    private var weatherCorrelationButton: some View {
        NavigationLink(destination: WeatherCorrelationView(
            viewModel: viewModel,
            timeFilter: timeFilter,
            selectedYear: selectedYear,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weather Correlation")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Analyze how weather patterns correlate with your migraines")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: Color.blue.opacity(0.1), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Rolling 6-month bar chart data. Intentionally pulls from
    /// `viewModel.migraines` (not `filteredMigraines`) so months that
    /// fall in a prior calendar year — e.g. Oct/Nov/Dec 2025 when the
    /// time-filter is set to 2026 — still contribute their bars. The
    /// time-filter is a *year* picker for the rest of the Analytics
    /// tab; applying it to this rolling window would silently drop
    /// half the chart every January.
    private var monthlyData: [MonthlyPoint] {
        let calendar = Calendar.current
        let now = Date()
        // Start of *this* month: floors today to the 1st so the
        // six-months-back anchor lands on a month boundary regardless
        // of what day we render on.
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        // Lower bound = start of the month six months back. We widen
        // from the previous implementation, which used
        // `now - 6 months` — that produced a boundary like "Oct 26",
        // which excluded migraines logged on e.g. Oct 15 even though
        // October's bar was on the chart's X-axis.
        let windowStart = calendar.date(
            byAdding: .month, value: -6, to: currentMonthStart
        ) ?? currentMonthStart
        // End bound = start of next month so a migraine logged today
        // still qualifies for the current month's bar.
        let windowEnd = calendar.date(
            byAdding: .month, value: 1, to: currentMonthStart
        ) ?? now
        
        var counts: [Date: Int] = [:]
        let months = calendar.generateDates(
            inside: DateInterval(start: windowStart, end: windowEnd),
            matching: DateComponents(day: 1)
        )
        for month in months {
            counts[month] = 0
        }
        
        for migraine in viewModel.migraines {
            guard let date = migraine.startTime else { continue }
            guard date >= windowStart, date < windowEnd else { continue }
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date)
            )!
            counts[monthStart, default: 0] += 1
        }
        
        return counts.map { MonthlyPoint(month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }
    
    // Add helper function for monthly bar color
    private func monthlyBarColor(count: Int) -> Color {
        switch count {
        case 0...4: return .green
        case 5...8: return .yellow
        default: return .red
        }
    }
    
    var body: some View {
        NavigationStack {
            statisticsContent
                .navigationTitle("Overview")
                .navigationDestination(for: AnalyticsMetric.self) { metric in
                    AnalyticsMetricDetailView(
                        viewModel: viewModel,
                        healthStore: healthCorrelationStore,
                        metric: metric,
                        migraines: filteredMigraines,
                        periodLabel: periodLabel
                    )
                }
                .navigationDestination(isPresented: $showingMonthDetail) {
                    if let month = selectedMonth {
                        MonthDetailView(viewModel: viewModel, month: month)
                    }
                }
                .navigationDestination(isPresented: medicationBinding) {
                    medicationNavigationView()
                }
                .navigationDestination(isPresented: triggerBinding) {
                    triggerNavigationView()
                }
                .navigationDestination(isPresented: timeOfDayBinding) {
                    timeOfDayNavigationView()
                }
                .navigationDestination(isPresented: impactBinding) {
                    impactNavigationView()
                }
                .navigationDestination(isPresented: painLevelBinding) {
                    painLevelNavigationView()
                }
                .onAppear {
                    viewModel.fetchMigraines()
                    lastUpdateTime = Date()
                    refreshHealthCorrelations()
                }
                .onChange(of: viewModel.migraines) {
                    lastUpdateTime = Date()
                    refreshHealthCorrelations()
                }
                .onChange(of: timeFilter) {
                    lastUpdateTime = Date()
                    refreshHealthCorrelations()
                }
                .onChange(of: customStartDate) {
                    lastUpdateTime = Date()
                    refreshHealthCorrelations()
                }
                .onChange(of: customEndDate) {
                    lastUpdateTime = Date()
                    refreshHealthCorrelations()
                }
        }
    }
    
    // MARK: - Body Subviews
    
    private var statisticsContent: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                timeFilterView
                    .padding(.horizontal)
                    .padding(.top)
                    .background(Color(.systemGroupedBackground))
                
                ScrollView {
                    VStack(spacing: 20) {
                        if filteredMigraines.isEmpty {
                            VStack(spacing: 20) {
                                Spacer()
                                    .frame(height: 40)
                                
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: 100, height: 100)
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.system(size: 40))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                                
                                VStack(spacing: 8) {
                                    Text("No Data for This Period")
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    Text("Try selecting a different time range, or log a migraine to start seeing statistics.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                                
                                Spacer()
                            }
                        } else {
                            summaryStatsView
                                .padding(.top)
                            chartsView
                        }
                    }
                    .padding(.vertical)
                    // On iPad, cap the dashboard width so the line length
                    // stays comfortable to read; on iPhone (compact) we
                    // let the content stretch edge-to-edge as before.
                    .frame(maxWidth: horizontalSizeClass == .regular ? 1100 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - Navigation Bindings
    
    private var medicationBinding: Binding<Bool> {
        Binding(
            get: { selectedMedication != nil },
            set: { if !$0 { selectedMedication = nil } }
        )
    }
    
    private var triggerBinding: Binding<Bool> {
        Binding(
            get: { selectedTrigger != nil },
            set: { if !$0 {
                selectedTrigger = nil
                isNavigating = false
            }}
        )
    }
    
    private var timeOfDayBinding: Binding<Bool> {
        Binding(
            get: { selectedTimeOfDay != nil },
            set: { if !$0 { selectedTimeOfDay = nil } }
        )
    }
    
    private var impactBinding: Binding<Bool> {
        Binding(
            get: { selectedImpactType != nil },
            set: { if !$0 { selectedImpactType = nil } }
        )
    }
    
    private var painLevelBinding: Binding<Bool> {
        Binding(
            get: { selectedPainLevel != nil },
            set: { if !$0 { selectedPainLevel = nil } }
        )
    }
    
    // Computed properties for statistics
    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let earliestYear = viewModel.migraines.compactMap { migraine in
            guard let date = migraine.startTime else { return nil }
            return calendar.component(.year, from: date)
        }.min() ?? currentYear
        
        return Array(earliestYear...currentYear)
    }
    
    // Filtered migraines based on time filter
    private var filteredMigraines: [MigraineEvent] {
        let calendar = Calendar.current
        let now = Date()
        
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            
            switch timeFilter {
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
                return startTime >= weekAgo
            case .month:
                let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
                return startTime >= monthAgo
            case .year:
                return calendar.component(.year, from: startTime) == selectedYear
            case .range:
                return startTime >= customStartDate && startTime <= customEndDate
            }
        }
    }
    
    private var totalMigraines: Int {
        filteredMigraines.count
    }
    
    private var currentPeriodMigraines: Int {
        let calendar = Calendar.current
        let now = Date()
        
        return filteredMigraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            
            switch timeFilter {
            case .week:
                return calendar.isDate(startTime, equalTo: now, toGranularity: .weekOfYear)
            case .month:
                return calendar.isDate(startTime, equalTo: now, toGranularity: .month)
            case .year:
                return calendar.isDate(startTime, equalTo: now, toGranularity: .year)
            case .range:
                return startTime >= customStartDate && startTime <= customEndDate
            }
        }.count
    }
    
    private var previousPeriodMigraines: Int {
        let calendar = Calendar.current
        let now = Date()
        
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            
            switch timeFilter {
            case .week:
                let lastWeekStart = calendar.date(byAdding: .day, value: -14, to: now)!
                let lastWeekEnd = calendar.date(byAdding: .day, value: -7, to: now)!
                return startTime >= lastWeekStart && startTime < lastWeekEnd
            case .month:
                let lastMonthStart = calendar.date(byAdding: .month, value: -2, to: now)!
                let lastMonthEnd = calendar.date(byAdding: .month, value: -1, to: now)!
                return startTime >= lastMonthStart && startTime < lastMonthEnd
            case .year:
                let lastYearStart = calendar.date(byAdding: .year, value: -2, to: now)!
                let lastYearEnd = calendar.date(byAdding: .year, value: -1, to: now)!
                return startTime >= lastYearStart && startTime < lastYearEnd
            case .range:
                let interval = customEndDate.timeIntervalSince(customStartDate)
                let prevStart = customStartDate.addingTimeInterval(-interval)
                let prevEnd = customStartDate
                return startTime >= prevStart && startTime < prevEnd
            }
        }.count
    }
    
    private var averageDuration: TimeInterval? {
        // Only include completed migraine events (those with an explicit endTime)
        let completedDurations = filteredMigraines.compactMap { migraine -> TimeInterval? in
            // Ensure the migraine has both a start and end time
            guard let start = migraine.startTime,
                  let end = migraine.endTime else { return nil }
            return end.timeIntervalSince(start)
        }
        guard !completedDurations.isEmpty else { return nil }
        return completedDurations.reduce(0, +) / Double(completedDurations.count)
    }
    
    private var averageFrequency: Double {
        switch timeFilter {
        case .week:
            return Double(totalMigraines) / 7.0
        case .month:
            return Double(totalMigraines) / 30.0
        case .year:
            return Double(totalMigraines) / 12.0  // monthly average for the year
        case .range:
            let days = max(Calendar.current.dateComponents([.day], from: customStartDate, to: customEndDate).day ?? 1, 1)
            return Double(totalMigraines) / Double(days)
        }
    }
    
    private var averagePain: Double {
        guard !filteredMigraines.isEmpty else { return 0 }
        let sum = filteredMigraines.reduce(0.0) { $0 + Double($1.painLevel) }
        return sum / Double(filteredMigraines.count)
    }
    
    private var abortivesUsed: Int {
        filteredMigraines.reduce(0) { $0 + $1.medications.count }
    }
    
    private var painLevelData: [PainLevelPoint] {
        var counts: [Int: Int] = [:]
        for migraine in filteredMigraines {
            counts[Int(migraine.painLevel), default: 0] += 1
        }
        return (1...10).map { PainLevelPoint(level: $0, count: counts[$0] ?? 0) }
    }
    
    // MARK: - Severity / streak metrics
    
    /// Distribution across the four clinical severity buckets — replaces the
    /// previous 1-10 histogram on the dashboard. Always emits one entry per
    /// bucket so the chart layout stays stable regardless of dataset size.
    private var severityBucketData: [SeverityBucketPoint] {
        filteredMigraines.severityBucketDistribution
    }
    
    /// Days in the *currently filtered period* on which at least one
    /// migraine reached pain level 7+. Counts unique calendar days so a
    /// patient with two severe migraines on the same day sees "1", not "2".
    private var severePainDays: Int {
        filteredMigraines.severePainDays()
    }
    
    /// Days since the most recent migraine across the *full* history (not
    /// just the filtered window) — a streak resets the moment a migraine is
    /// logged regardless of which time filter is active.
    private var currentMigraineFreeStreak: Int? {
        viewModel.migraines.currentMigraineFreeStreak()
    }
    
    /// Big-number portion of the streak tile, e.g. "12" or "—" when the user
    /// has never logged a migraine.
    private var streakDisplayValue: String {
        guard let streak = currentMigraineFreeStreak else { return "—" }
        return String(streak)
    }
    
    /// Subtitle under the streak number, e.g. "days" or "no entries yet".
    private var streakDisplaySubtitle: String? {
        guard let streak = currentMigraineFreeStreak else { return "no entries yet" }
        return streak == 1 ? "day" : "days"
    }
    
    /// Top trigger across the filtered period, or `nil` when no triggers
    /// were logged. Computed once per redraw and reused by both the KPI
    /// tile and the upcoming insights cards.
    private var topTriggerInfo: (trigger: MigraineTrigger, count: Int)? {
        filteredMigraines.topTrigger
    }
    
    /// Big-number portion of the Top Trigger tile.
    private var topTriggerDisplayValue: String {
        topTriggerInfo?.trigger.displayName ?? "—"
    }
    
    /// Subtitle under the trigger name, e.g. "5 logs" or "no data yet".
    private var topTriggerDisplaySubtitle: String? {
        guard let info = topTriggerInfo else { return "no data yet" }
        return info.count == 1 ? "1 log" : "\(info.count) logs"
    }
    
    /// Cumulative life-impact days inside the filtered period — drives the
    /// "Days Missed" tile. Days are counted independently per category to
    /// match the existing Life Impact card decomposition.
    private var totalImpactDays: Int {
        filteredMigraines.totalImpactDays
    }
    
    /// `DateInterval` used by the HealthKit correlation fetchers. Mirrors
    /// the active filter, except the `.year` filter is widened to a
    /// rolling 12 months so HealthKit reads always have a meaningful
    /// baseline (years near the start of the calendar would otherwise
    /// have only a few weeks of HealthKit history).
    private var correlationWindow: DateInterval {
        let cal = Calendar.current
        let now = Date()
        let end = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let start: Date
        switch timeFilter {
        case .week:
            start = cal.date(byAdding: .day, value: -7, to: end) ?? end
        case .month:
            start = cal.date(byAdding: .month, value: -1, to: end) ?? end
        case .year:
            start = cal.date(byAdding: .year, value: -1, to: end) ?? end
        case .range:
            start = cal.startOfDay(for: customStartDate)
        }
        return DateInterval(start: start, end: end)
    }
    
    /// Kicks off (or no-ops on duplicate) a refresh of the HealthKit
    /// correlation stats for the active filter window.
    private func refreshHealthCorrelations() {
        healthCorrelationStore.load(
            window: correlationWindow,
            migraines: filteredMigraines
        )
    }
    
    /// Human-readable description of the active filter window. Surfaced
    /// in detail-screen headers so users always know which slice of data
    /// they're drilling into.
    private var periodLabel: String {
        switch timeFilter {
        case .week:  return "Past 7 days"
        case .month: return "Past 30 days"
        case .year:  return "Year \(selectedYear)"
        case .range:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "\(formatter.string(from: customStartDate)) – \(formatter.string(from: customEndDate))"
        }
    }
    
    private var timeOfDayData: [TimeOfDayPoint] {
        let timeSlots = ["Morning", "Afternoon", "Evening", "Night"]
        var counts: [String: Int] = [:]
        
        for migraine in filteredMigraines {
            guard let date = migraine.startTime else { continue }
            let hour = Calendar.current.component(.hour, from: date)
            let timeSlot: String
            
            switch hour {
            case 5..<12: timeSlot = "Morning"
            case 12..<17: timeSlot = "Afternoon"
            case 17..<22: timeSlot = "Evening"
            default: timeSlot = "Night"
            }
            
            counts[timeSlot, default: 0] += 1
        }
        
        return timeSlots.map { TimeOfDayPoint(timeOfDay: $0, count: counts[$0] ?? 0) }
    }
    
    private var qualityOfLifeData: [QualityOfLifePoint] {
        let missedWork = filteredMigraines.filter { $0.missedWork }.count
        let missedSchool = filteredMigraines.filter { $0.missedSchool }.count
        let missedEvents = filteredMigraines.filter { $0.missedEvents }.count
        
        return [
            QualityOfLifePoint(type: "Missed Work", count: missedWork),
            QualityOfLifePoint(type: "Missed School", count: missedSchool),
            QualityOfLifePoint(type: "Missed Events", count: missedEvents)
        ]
    }
    
    private var commonTriggersChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Triggers", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .padding(.horizontal)
                
                let triggerData = filteredMigraines
                    .reduce(into: [MigraineTrigger: Int]()) { counts, migraine in
                        for trigger in migraine.triggers {
                            counts[trigger, default: 0] += 1
                        }
                    }
                    .map { TriggerPoint(trigger: $0.key.displayName, count: $0.value) }
                    .sorted { $0.count > $1.count }
                    .filter { $0.count > 0 }
                
                if triggerData.isEmpty {
                    Text("No trigger data for selected period")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(triggerData.prefix(5)) { point in
                        BarMark(
                            x: .value("Count", point.count),
                            y: .value("Trigger", point.trigger)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(6)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisValueLabel()
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            AxisValueLabel()
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(12)
                    }
                    .frame(height: 220)
                    .onTapGesture { location in
                        guard !isNavigating else { return }
                        if let trigger = triggerData.first?.trigger {
                            isNavigating = true
                            selectedTrigger = trigger
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var medicationUsageChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Medications", systemImage: "pill.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
                    .padding(.horizontal)
                
                let medicationData = filteredMigraines
                    .reduce(into: [MigraineMedication: Int]()) { counts, migraine in
                        for medication in migraine.medications {
                            counts[medication, default: 0] += 1
                        }
                    }
                    .map { MedicationPoint(medication: $0.key.displayName, count: $0.value) }
                    .sorted { $0.count > $1.count }
                    .filter { $0.count > 0 }
                
                if medicationData.isEmpty {
                    Text("No medication data for selected period")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(medicationData.prefix(5)) { point in
                        SectorMark(
                            angle: .value("Count", point.count),
                            innerRadius: .ratio(0.618),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Medication", point.medication))
                        .cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .center, spacing: 12) {
                        HStack(spacing: 16) {
                            ForEach(medicationData.prefix(5)) { point in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.purple.opacity(0.7))
                                        .frame(width: 8, height: 8)
                                    Text(point.medication)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 240)
                    .onTapGesture { location in
                        guard !isNavigating else { return }
                        if let medication = medicationData.first?.medication {
                            isNavigating = true
                            selectedMedication = medication
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var timeOfDayDistributionChart: some View {
        ChartSection(title: "Time of Day Distribution") {
            Chart(timeOfDayData) { point in
                BarMark(
                    x: .value("Time", point.timeOfDay),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.pink],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(8)
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    AxisValueLabel()
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    AxisValueLabel()
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard !isNavigating,
                                  let (timeSlot, count) = proxy.value(at: location, as: (String, Int).self),
                                  count > 0 else { return }
                            isNavigating = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                            selectedTimeOfDay = timeSlot
                        }
                }
            }
            .frame(height: 220)
        }
    }
    
    private var qualityOfLifeImpactChart: some View {
        ChartSection(title: "Quality of Life Impact") {
            let data = qualityOfLifeData.filter { $0.count > 0 }
            
            if data.isEmpty {
                Text("No impact data for selected period")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("Count", point.count),
                        y: .value("Type", point.type)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard !isNavigating,
                                      let (impactType, count) = proxy.value(at: location, as: (String, Int).self),
                                      count > 0 else { return }
                                isNavigating = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    isNavigating = false
                                }
                                selectedImpactType = impactType
                            }
                    }
                }
                .frame(height: 220)
            }
        }
    }
    
    private func formatDuration(_ interval: TimeInterval?) -> String {
        guard let interval = interval else { return "N/A" }
        
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...7: return .yellow
        case 8...10: return .red
        default: return .gray
        }
    }
    
    /// New top-level severity chart for the dashboard. Replaces the old
    /// 10-bin histogram, which is now reachable via drill-down only.
    private var painLevelDistributionChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Severity Distribution", systemImage: "thermometer.medium")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer()
                    if severePainDays > 0 {
                        Text("\(severePainDays) severe day\(severePainDays == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                
                Chart(severityBucketData) { point in
                    BarMark(
                        x: .value("Severity", point.bucket.title),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(point.bucket.color.gradient)
                    .cornerRadius(8)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        if point.count > 0 {
                            Text(String(point.count))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel {
                            if let bucketTitle = value.as(String.self),
                               let bucket = SeverityBucket.allCases.first(where: { $0.title == bucketTitle }) {
                                VStack(spacing: 2) {
                                    Text(bucket.title)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.primary)
                                    Text(bucket.rangeDescription)
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .frame(height: 200)
                .accessibilityLabel("Severity distribution")
                .accessibilityValue(
                    severityBucketData
                        .filter { $0.count > 0 }
                        .map { "\($0.count) \($0.bucket.title.lowercased())" }
                        .joined(separator: ", ")
                )
            }
        }
    }
    
    /// Legacy 10-bin pain histogram, retained for the severity drill-down.
    private var painLevelHistogramChart: some View {
        ChartSection(title: "Pain Level Distribution (1-10)") {
            Chart(painLevelData) { point in
                BarMark(
                    x: .value("Pain Level", point.level),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(painLevelColor(point.level).gradient)
                .cornerRadius(8)
            }
            .chartXAxis {
                AxisMarks(values: Array(1...10)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    AxisValueLabel()
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    AxisValueLabel()
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard !isNavigating,
                                  let (level, count) = proxy.value(at: location, as: (Int, Int).self),
                                  count > 0 else { return }
                            isNavigating = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                            selectedPainLevel = level
                        }
                }
            }
            .frame(height: 220)
        }
    }
    
    // Add the missing monthlyDistributionChart view
    private var monthlyDistributionChart: some View {
        ChartSection(title: "Monthly Distribution") {
            if monthlyData.isEmpty {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart(monthlyData) { point in
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(monthlyBarColor(count: point.count).gradient)
                    .cornerRadius(8)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .frame(height: 220)
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
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
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 68/255, green: 130/255, blue: 180/255))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
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
                    .font(.system(size: 9, weight: .bold))
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
            .foregroundColor(.red)
        case .down(let detail):
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
            .foregroundColor(.green)
        case .same:
            HStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                Text("No change")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
            .foregroundColor(.secondary)
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

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return StatisticsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
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
                    .font(.system(size: 20))
                    .foregroundColor(color)
                
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
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

