import SwiftUI
import Charts
import TipKit

struct StatisticsView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var timeFilter: TimeFilter = .month
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedImpactType: String?
    @State private var patternDrillDown: PatternDrillDown?
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    
    /// Owns the cached HealthKit-derived correlation stats. The dashboard
    /// triggers `load(window:migraines:)` whenever the filter or migraine
    /// list changes; the section view + drill-downs read from the store.
    @StateObject private var healthCorrelationStore = HealthCorrelationStore()

    /// Drives the "Connect Apple Health" primer when the user taps the
    /// CTA on the Health Correlations card from the Analytics dashboard.
    /// We never auto-present this — only the explicit CTA does.
    @State private var showingHealthKitPrimer = false

    /// Invalidated the first time any drill-down opens, so users who have
    /// already found the navigation never see it again.
    private let drillDownTip = AnalyticsDrillDownTip()
    
    /// `.regular` ≈ iPad in any orientation + iPhone Plus/Pro Max in
    /// landscape. Drives the KPI grid column count and the dashboard's
    /// maximum content width.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var kpiGridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 6 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
    
    enum TimeFilter: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case range = "Range"
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            statisticsContent
                .navigationTitle("Overview")
                .toolbar { filterMenu }
                .navigationDestination(for: AnalyticsMetric.self) { metric in
                    AnalyticsMetricDetailView(
                        viewModel: viewModel,
                        healthStore: healthCorrelationStore,
                        metric: metric,
                        migraines: filteredMigraines,
                        periodLabel: periodLabel
                    )
                    .onAppear { drillDownTip.invalidate(reason: .actionPerformed) }
                }
                .navigationDestination(item: $patternDrillDown) { drillDown in
                    patternDrillDownView(drillDown)
                        .onAppear { drillDownTip.invalidate(reason: .actionPerformed) }
                }
                .navigationDestination(isPresented: impactBinding) {
                    impactNavigationView()
                }
                .onAppear {
                    viewModel.fetchMigraines()
                    refreshHealthCorrelations()
                }
                .onChange(of: viewModel.migraines) { refreshHealthCorrelations() }
                .onChange(of: timeFilter) { refreshHealthCorrelations() }
                .onChange(of: selectedYear) { refreshHealthCorrelations() }
                .onChange(of: customStartDate) { refreshHealthCorrelations() }
                .onChange(of: customEndDate) { refreshHealthCorrelations() }
        }
    }
    
    private var statisticsContent: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    periodHeader
                    if filteredMigraines.isEmpty {
                        emptyState
                    } else {
                        heroSection
                        kpiStrip
                        trendsSection
                        medicationSection
                        patternsSection
                        insightsSection
                        cycleSection
                        healthCorrelationsSection
                        impactSummaryView
                        weatherCorrelationButton
                        completenessFooter
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: horizontalSizeClass == .regular ? 1100 : .infinity)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.3), value: timeFilter)
            }
        }
    }
    
    // MARK: - Filter
    
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Period", selection: $timeFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Text(filter.menuTitle).tag(filter)
                    }
                }
                if timeFilter == .year {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                }
            } label: {
                Label(timeFilter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Filter period, currently \(periodLabel)")
        }
    }
    
    /// Period label + sample size under the title; date pickers appear
    /// inline only for the custom range.
    private var periodHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(periodLabel)
                    .scaledFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(filteredMigraines.count) \(filteredMigraines.count == 1 ? "entry" : "entries")")
                    .scaledFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if timeFilter == .range {
                HStack(spacing: 12) {
                    DatePicker("Start", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    DatePicker("End", selection: $customEndDate, in: customStartDate...Date(), displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Data for This Period", systemImage: "chart.bar.xaxis")
                .scaledFont(size: 20, weight: .semibold, design: .rounded)
        } description: {
            Text("Try a different period from the filter, or log a migraine to start seeing statistics.")
                .scaledFont(size: 14)
        } actions: {
            if viewModel.migraines.isEmpty == false, timeFilter != .year {
                Button("Show This Year") {
                    timeFilter = .year
                    selectedYear = Calendar.current.component(.year, from: Date())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 40)
    }
    
    // MARK: - Hero + KPIs
    
    private var heroSection: some View {
        NavigationLink(value: AnalyticsMetric.migraineDays) {
            HeroMetricCard(
                title: "Migraine days",
                value: String(headacheDays),
                unit: headacheDays == 1 ? "day" : "days",
                context: heroContext,
                trend: headacheDaysTrend,
                trendSentiment: sentiment(for: headacheDaysTrend, higherIsWorse: true),
                accent: AnalyticsDomain.frequency.accent
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .padding(.horizontal, 16)
        .popoverTip(drillDownTip, arrowEdge: .top)
        .accessibilityHint("Opens migraine days details")
    }
    
    private var heroContext: String {
        if let days = periodDayCount {
            return "of \(days) days · \(totalMigraines) \(totalMigraines == 1 ? "attack" : "attacks")"
        }
        return "\(totalMigraines) \(totalMigraines == 1 ? "attack" : "attacks")"
    }
    
    private var kpiStrip: some View {
        LazyVGrid(columns: kpiGridColumns, spacing: 10) {
            tileLink(
                metric: .total,
                KPIChip(
                    title: "Attacks",
                    value: String(totalMigraines),
                    trend: totalTrend,
                    trendSentiment: sentiment(for: totalTrend, higherIsWorse: true)
                )
            )
            tileLink(
                metric: .averagePain,
                KPIChip(
                    title: "Avg pain",
                    value: String(format: "%.1f", averagePain),
                    detail: "of 10",
                    trend: painTrend,
                    trendSentiment: sentiment(for: painTrend, higherIsWorse: true),
                    accent: AnalyticsDomain.severity.accent
                )
            )
            tileLink(
                metric: .averageDuration,
                KPIChip(
                    title: "Median duration",
                    value: durationSpread.map { formatDuration($0.median) } ?? "—",
                    detail: durationDetail
                )
            )
            tileLink(
                metric: .severeDays,
                KPIChip(
                    title: "Severe days",
                    value: String(severePainDays),
                    detail: "pain 7+",
                    accent: severePainDays > 0 ? AnalyticsDomain.severity.accent : .primary
                )
            )
            tileLink(
                metric: .streak,
                KPIChip(
                    title: "Migraine-free",
                    value: streakDisplayValue,
                    detail: streakDisplaySubtitle,
                    accent: .green
                )
            )
            tileLink(
                metric: .topTrigger,
                KPIChip(
                    title: "Top trigger",
                    value: topTriggerDisplayValue,
                    detail: topTriggerDisplaySubtitle
                )
            )
        }
        .padding(.horizontal, 16)
    }
    
    /// Wraps a tile in a `NavigationLink` whose value drives the
    /// per-metric drill-down handled by `AnalyticsMetricDetailView`.
    private func tileLink<Content: View>(metric: AnalyticsMetric, _ content: Content) -> some View {
        NavigationLink(value: metric) {
            content
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityHint("Opens \(metric.title) details")
    }
    
    // MARK: - Trends
    
    /// Heatmap (with period-start dots for eligible users) and the
    /// scrollable 12-month headache-day trend.
    private var trendsSection: some View {
        ChartSection(title: "Trends", systemImage: "chart.bar.fill", accent: AnalyticsDomain.frequency.accent) {
            VStack(alignment: .leading, spacing: 20) {
                SeverityHeatmapView(
                    cells: heatmapCells,
                    cycleStartDays: Set(healthCorrelationStore.cycleStartDays)
                )
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Migraine days per month")
                        .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    if monthlyHeadacheDays.allSatisfy({ $0.count == 0 }) {
                        Text("No migraine days in the past 12 months.")
                            .scaledFont(size: 13)
                            .foregroundStyle(.secondary)
                    } else {
                        MonthlyTrendChart(points: monthlyHeadacheDays, unit: "day")
                    }
                }
                AnalyticsFooter(text: "Past 12 months, all entries. Swipe the chart to scroll; tap a bar for that month.")
            }
        }
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
                return cal.date(byAdding: .day, value: -89, to: end) ?? end
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
    
    /// Rolling 12-month series from the *full* history so months in a
    /// prior calendar year still appear when the year filter is active.
    private var monthlyHeadacheDays: [MonthlyPoint] {
        viewModel.migraines.monthlyHeadacheDays(monthsBack: 11)
    }
    
    // MARK: - Medication
    
    private var medicationSection: some View {
        NavigationLink(value: AnalyticsMetric.medicationDays) {
            ChartSection(
                title: "Acute medication",
                systemImage: "pills.fill",
                accent: AnalyticsDomain.medication.accent,
                showsDetailsAffordance: true
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(acuteMedicationDays))
                            .scaledFont(size: 30, weight: .bold, design: .rounded)
                            .foregroundStyle(AnalyticsDomain.medication.accent)
                            .contentTransition(.numericText())
                        Text(acuteMedicationDays == 1 ? "day with acute medication" : "days with acute medication")
                            .scaledFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let trend = medicationDaysTrend {
                            TrendChip(direction: trend, sentiment: sentiment(for: trend, higherIsWorse: true))
                        }
                    }
                    if let perMonth = acuteMedicationDaysPerMonth {
                        MedicationDaysGauge(daysPerMonth: perMonth)
                        Text(medicationBandCopy(perMonth: perMonth))
                            .scaledFont(size: 12)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AnalyticsFooter(text: "\(abortivesUsed) \(abortivesUsed == 1 ? "dose" : "doses") logged across \(totalMigraines) \(totalMigraines == 1 ? "entry" : "entries"). Counts days, not tablets.")
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityHint("Opens acute medication days details")
    }
    
    private func medicationBandCopy(perMonth: Double) -> String {
        let rate = perMonth == perMonth.rounded() ? String(Int(perMonth)) : String(format: "%.1f", perMonth)
        switch AcuteMedicationBand.band(daysPerMonth: perMonth) {
        case .low:
            return "About \(rate) days per 30 — below the \(AcuteMedicationBand.moderateThreshold)-day mark clinicians often use as a reference."
        case .moderate:
            return "About \(rate) days per 30. Frequent acute-medication use (\(AcuteMedicationBand.moderateThreshold)+ days a month) is worth mentioning to your clinician."
        case .frequent:
            return "About \(rate) days per 30 — \(AcuteMedicationBand.frequentThreshold)+ days a month is a level clinicians usually want to discuss. This is context, not a diagnosis."
        }
    }
    
    // MARK: - Patterns / insights
    
    private var patternsSection: some View {
        AnalyticsPatternsCard(migraines: filteredMigraines) { drillDown in
            patternDrillDown = drillDown
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
    
    // MARK: - Cycle
    
    /// Shown only for users whose Health data makes cycle insights
    /// applicable and who have the toggle on; excluded users see nothing.
    @ViewBuilder
    private var cycleSection: some View {
        if healthCorrelationStore.cycleAvailability == .available {
            NavigationLink(value: AnalyticsMetric.cyclePhase) {
                CycleAssociationCard(association: healthCorrelationStore.cycleAssociation)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityHint("Opens cycle and migraine details")
        }
    }
    
    // MARK: - Health
    
    /// Sleep + HRV correlation cards, hidden entirely when HealthKit
    /// isn't available on the device. The CTA on this card opens our
    /// primer (which then opens Apple's permission sheet) rather than
    /// firing `requestAuthorization` directly — see
    /// `HealthKitPermissionPrimerView` for why.
    private var healthCorrelationsSection: some View {
        HealthCorrelationsSectionView(
            store: healthCorrelationStore,
            onConnectTapped: {
                showingHealthKitPrimer = true
            }
        )
        .sheet(isPresented: $showingHealthKitPrimer) {
            HealthKitPermissionPrimerView(
                onContinue: {
                    Task {
                        await HealthKitManager.shared.requestAuthorization()
                        refreshHealthCorrelations()
                    }
                },
                onSkip: {
                    HealthKitManager.shared.markAuthorizationRequested()
                    refreshHealthCorrelations()
                }
            )
        }
    }
    
    // MARK: - Impact
    
    private var impactSummaryView: some View {
        let missedWorkCount = filteredMigraines.filter { $0.missedWork }.count
        let missedSchoolCount = filteredMigraines.filter { $0.missedSchool }.count
        let missedEventsCount = filteredMigraines.filter { $0.missedEvents }.count
        let totalImpact = missedWorkCount + missedSchoolCount + missedEventsCount
        
        return Group {
            if totalImpact > 0 {
                ChartSection(title: "Life impact", systemImage: "heart.slash.fill", accent: .red) {
                    HStack(spacing: 12) {
                        if missedWorkCount > 0 {
                            ImpactBadge(icon: "briefcase.fill", count: missedWorkCount, label: "Work", color: .red) {
                                selectedImpactType = "Missed Work"
                            }
                        }
                        if missedSchoolCount > 0 {
                            ImpactBadge(icon: "graduationcap.fill", count: missedSchoolCount, label: "School", color: .orange) {
                                selectedImpactType = "Missed School"
                            }
                        }
                        if missedEventsCount > 0 {
                            ImpactBadge(icon: "calendar.badge.exclamationmark", count: missedEventsCount, label: "Events", color: .purple) {
                                selectedImpactType = "Missed Events"
                            }
                        }
                    }
                }
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
            HStack(spacing: 14) {
                Image(systemName: "cloud.sun.fill")
                    .scaledFont(size: 22)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AnalyticsDomain.weather.accent)
                    .frame(width: 44, height: 44)
                    .background(AnalyticsDomain.weather.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather correlation")
                        .scaledFont(size: 16, weight: .semibold, design: .rounded)
                        .foregroundStyle(.primary)
                    Text("Pressure, temperature and conditions on migraine days")
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .analyticsSurface()
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
    
    /// Data-completeness indicator so the user knows how much of the
    /// dashboard rests on fully detailed entries.
    private var completenessFooter: some View {
        let completeness = filteredMigraines.dataCompleteness
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text("Data completeness · \(Int((completeness.overallShare * 100).rounded()))%")
                    .scaledFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            Text(completenessDetail(completeness))
                .scaledFont(size: 11)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
    
    private func completenessDetail(_ completeness: DataCompleteness) -> String {
        func pct(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
        return "End time \(pct(completeness.endTimeShare)) · Weather \(pct(completeness.weatherShare)) · Triggers \(pct(completeness.triggerShare)) · Medication \(pct(completeness.medicationShare)). Adding these details sharpens every chart above."
    }
    
    // MARK: - Drill-downs
    
    @ViewBuilder
    private func patternDrillDownView(_ drillDown: PatternDrillDown) -> some View {
        switch drillDown {
        case .severity(let bucket):
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "\(bucket.title) migraines",
                migraines: filteredMigraines.filter { SeverityBucket.bucket(for: Int($0.painLevel)) == bucket }
            )
        case .timeOfDay(let slot):
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines in \(slot)",
                migraines: filteredMigraines.filter { migraine in
                    guard let date = migraine.startTime else { return false }
                    let hour = Calendar.current.component(.hour, from: date)
                    switch slot {
                    case "Morning": return (5..<12).contains(hour)
                    case "Afternoon": return (12..<17).contains(hour)
                    case "Evening": return (17..<22).contains(hour)
                    case "Night": return hour < 5 || hour >= 22
                    default: return false
                    }
                }
            )
        case .weekday(let weekday):
            let name = Calendar.current.weekdaySymbols[max(0, min(6, weekday - 1))]
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines on \(name)s",
                migraines: filteredMigraines.filter { migraine in
                    guard let date = migraine.startTime else { return false }
                    return Calendar.current.component(.weekday, from: date) == weekday
                }
            )
        case .symptom(let symptom):
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines with \(symptom.title.lowercased())",
                migraines: filteredMigraines.filter { $0.has(symptom) }
            )
        case .trigger(let triggerName):
            if let trigger = MigraineTrigger(displayName: triggerName) {
                FilteredMigraineListView(
                    viewModel: viewModel,
                    title: "Migraines with \(triggerName)",
                    migraines: filteredMigraines.filter { $0.triggers.contains(trigger) }
                )
            }
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
    
    private var impactBinding: Binding<Bool> {
        Binding(
            get: { selectedImpactType != nil },
            set: { if !$0 { selectedImpactType = nil } }
        )
    }
    
    // MARK: - Period windows
    
    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let earliestYear = viewModel.migraines.compactMap { migraine in
            guard let date = migraine.startTime else { return nil }
            return calendar.component(.year, from: date)
        }.min() ?? currentYear
        
        return Array(earliestYear...currentYear)
    }
    
    /// The active filter as a half-open interval, and the equally long
    /// interval immediately before it (for trend chips).
    private var currentPeriod: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        switch timeFilter {
        case .week:
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: now) ?? now, end: now)
        case .month:
            return DateInterval(start: calendar.date(byAdding: .month, value: -1, to: now) ?? now, end: now)
        case .year:
            let start = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .range:
            let end = customEndDate.addingTimeInterval(1)
            return DateInterval(start: min(customStartDate, end), end: end)
        }
    }
    
    private var previousPeriod: DateInterval {
        let calendar = Calendar.current
        let current = currentPeriod
        switch timeFilter {
        case .week:
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: current.start) ?? current.start, end: current.start)
        case .month:
            return DateInterval(start: calendar.date(byAdding: .month, value: -1, to: current.start) ?? current.start, end: current.start)
        case .year:
            return DateInterval(start: calendar.date(byAdding: .year, value: -1, to: current.start) ?? current.start, end: current.start)
        case .range:
            return DateInterval(start: current.start.addingTimeInterval(-current.duration), end: current.start)
        }
    }
    
    /// Calendar days covered by the filter, capped at today for the
    /// current year so "of N days" never counts the future.
    private var periodDayCount: Int? {
        let calendar = Calendar.current
        let end = min(currentPeriod.end, Date())
        guard end > currentPeriod.start else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: currentPeriod.start), to: calendar.startOfDay(for: end)).day ?? 0
        return max(1, days + (timeFilter == .range ? 1 : 0))
    }
    
    private func migraines(in interval: DateInterval) -> [MigraineEvent] {
        viewModel.migraines.filter { migraine in
            guard let start = migraine.startTime else { return false }
            return start >= interval.start && start < interval.end
        }
    }
    
    private var filteredMigraines: [MigraineEvent] {
        let calendar = Calendar.current
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            switch timeFilter {
            case .week, .month:
                return startTime >= currentPeriod.start
            case .year:
                return calendar.component(.year, from: startTime) == selectedYear
            case .range:
                return startTime >= customStartDate && startTime <= customEndDate
            }
        }
    }
    
    private var previousPeriodMigraines: [MigraineEvent] {
        migraines(in: previousPeriod)
    }
    
    // MARK: - Metrics
    
    private var totalMigraines: Int { filteredMigraines.count }
    private var headacheDays: Int { filteredMigraines.headacheDays() }
    private var acuteMedicationDays: Int { filteredMigraines.acuteMedicationDays() }
    private var abortivesUsed: Int { filteredMigraines.totalMedicationUses }
    private var averagePain: Double { filteredMigraines.averagePain }
    private var durationSpread: DurationSpread? { filteredMigraines.durationSpread }
    private var severePainDays: Int { filteredMigraines.severePainDays() }
    private var currentMigraineFreeStreak: Int? { viewModel.migraines.currentMigraineFreeStreak() }
    private var topTriggerInfo: (trigger: MigraineTrigger, count: Int)? { filteredMigraines.topTrigger }
    
    /// Acute-medication days normalised to a 30-day month so the gauge
    /// reads the same for a week, a month or a year.
    private var acuteMedicationDaysPerMonth: Double? {
        guard let days = periodDayCount, days > 0 else { return nil }
        return Double(acuteMedicationDays) / Double(days) * 30
    }
    
    private var durationDetail: String? {
        guard let spread = durationSpread else { return "no end times yet" }
        guard spread.sampleCount >= 4 else { return "\(spread.sampleCount) timed" }
        return "IQR \(formatDuration(spread.lowerQuartile))–\(formatDuration(spread.upperQuartile))"
    }
    
    private var streakDisplayValue: String {
        guard let streak = currentMigraineFreeStreak else { return "—" }
        return String(streak)
    }
    
    private var streakDisplaySubtitle: String? {
        guard let streak = currentMigraineFreeStreak else { return "no entries yet" }
        return streak == 1 ? "day" : "days"
    }
    
    private var topTriggerDisplayValue: String {
        topTriggerInfo?.trigger.displayName ?? "—"
    }
    
    private var topTriggerDisplaySubtitle: String? {
        guard let info = topTriggerInfo else { return "no data yet" }
        return info.count == 1 ? "1 log" : "\(info.count) logs"
    }
    
    // MARK: - Trends vs. previous period
    
    private var headacheDaysTrend: StatBox.TrendDirection? {
        countTrend(current: headacheDays, previous: previousPeriodMigraines.headacheDays())
    }
    
    private var totalTrend: StatBox.TrendDirection? {
        countTrend(current: totalMigraines, previous: previousPeriodMigraines.count)
    }
    
    private var medicationDaysTrend: StatBox.TrendDirection? {
        countTrend(current: acuteMedicationDays, previous: previousPeriodMigraines.acuteMedicationDays())
    }
    
    private var painTrend: StatBox.TrendDirection? {
        guard timeFilter != .range, !previousPeriodMigraines.isEmpty else { return nil }
        let diff = averagePain - previousPeriodMigraines.averagePain
        if abs(diff) < 0.2 { return .same }
        return diff > 0 ? .up(String(format: "+%.1f", diff)) : .down(String(format: "%.1f", diff))
    }
    
    private func countTrend(current: Int, previous: Int) -> StatBox.TrendDirection? {
        guard timeFilter != .range else { return nil }
        if current > previous { return .up("\(current - previous) more") }
        if current < previous { return .down("\(previous - current) fewer") }
        return .same
    }
    
    private func sentiment(for trend: StatBox.TrendDirection?, higherIsWorse: Bool) -> TrendSentiment {
        switch trend {
        case .up:   return higherIsWorse ? .unfavorable : .favorable
        case .down: return higherIsWorse ? .favorable : .unfavorable
        case .same, .none: return .neutral
        }
    }
    
    // MARK: - HealthKit window
    
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
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

private extension StatisticsView.TimeFilter {
    var menuTitle: String {
        switch self {
        case .week:  return "Past 7 days"
        case .month: return "Past 30 days"
        case .year:  return "Calendar year"
        case .range: return "Custom range"
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return StatisticsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
}
