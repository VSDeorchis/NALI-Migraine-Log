//
//  AnalyticsMetricDetailView.swift
//  NALI Migraine Log
//
//  Drill-down detail screen reached by tapping a KPI tile on the Analytics
//  Overview. Each metric switches to a focused detail layout: e.g. tapping
//  "Severe Days" drops into the legacy 1-10 histogram + a filtered list of
//  the offending entries; tapping "Top Trigger" opens the full triggers
//  bar chart with tap-to-filter behaviour.
//
//  This view is intentionally read-only — interaction with individual
//  migraine entries is delegated back to `FilteredMigraineListView` and
//  `MigraineDetailView`.
//

import SwiftUI
import Charts

struct AnalyticsMetricDetailView: View {
    @ObservedObject var viewModel: MigraineViewModel
    /// Optional — only the HealthKit-backed metrics consult it. The
    /// dashboard always passes one through; legacy callers can omit.
    var healthStore: HealthCorrelationStore? = nil
    let metric: AnalyticsMetric
    let migraines: [MigraineEvent]
    let periodLabel: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: metric.systemImage)
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(metric.accent)
                Text(metric.title)
                    .scaledFont(size: 22, weight: .bold, design: .rounded)
                Spacer()
            }
            Text(periodLabel)
                .scaledFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Per-metric content
    
    @ViewBuilder
    private var content: some View {
        switch metric {
        case .migraineDays:
            migraineDaysContent
        case .medicationDays:
            medicationDaysContent
        case .total:
            totalContent
        case .averagePain:
            averagePainContent
        case .severeDays:
            severeContent
        case .averageDuration:
            averageDurationContent
        case .streak:
            streakContent
        case .topTrigger:
            triggerContent
        case .topMedication:
            medicationContent
        case .missedDays:
            impactContent
        case .sleepCorrelation:
            sleepCorrelationContent
        case .hrvCorrelation:
            hrvCorrelationContent
        case .cyclePhase:
            cyclePhaseContent
        }
    }
    
    // MARK: - Reusable card
    
    private struct Card<Content: View>: View {
        let title: String
        @ViewBuilder let content: () -> Content
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if !title.isEmpty {
                    Text(title)
                        .scaledFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundStyle(.secondary)
                }
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .analyticsSurface()
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Metric: Migraine days
    
    /// Unique days with at least one attack — the burden measure clinicians
    /// track (monthly headache days) rather than the raw attack count.
    private var migraineDaysContent: some View {
        let days = migraines.headacheDays()
        let attacks = migraines.count
        let multiAttackDays = attacks - days
        let monthly = viewModel.migraines.monthlyHeadacheDays(monthsBack: 11)
        let recentAverage = Array(monthly.suffix(3)).averageCount
        
        return VStack(spacing: 16) {
            Card(title: "This period") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(days))
                        .scaledFont(size: 36, weight: .bold, design: .rounded)
                        .foregroundStyle(metric.accent)
                    Text(days == 1 ? "migraine day" : "migraine days")
                        .scaledFont(size: 15, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
                Text(multiAttackDays > 0
                     ? "\(attacks) attacks, \(multiAttackDays) of them on a day that already had one. Days are what most headache diaries and clinicians count."
                     : "\(attacks) \(attacks == 1 ? "attack" : "attacks"), each on a separate day.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Card(title: "Migraine days per month") {
                if monthly.allSatisfy({ $0.count == 0 }) {
                    emptyState
                } else {
                    MonthlyTrendChart(points: monthly, unit: "day", accent: metric.accent, height: 220)
                    Text(monthlyDaysCopy(recentAverage: recentAverage))
                        .scaledFont(size: 12)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Card(title: "") {
                NavigationLink {
                    FilteredMigraineListView(
                        viewModel: viewModel,
                        title: "All Migraines",
                        migraines: migraines.sorted {
                            ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast)
                        }
                    )
                } label: {
                    listLink(text: "See \(attacks) entries")
                }
            }
        }
    }
    
    private func monthlyDaysCopy(recentAverage: Double) -> String {
        let rounded = (recentAverage * 10).rounded() / 10
        let value = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "Past 3 months: about \(value) migraine days a month. Headache diaries often note whether this sits above or below 15 days a month; that context is worth discussing with your clinician, not a diagnosis."
    }
    
    // MARK: - Metric: Acute medication days
    
    private var medicationDaysContent: some View {
        let days = migraines.acuteMedicationDays()
        let doses = migraines.totalMedicationUses
        let monthly = viewModel.migraines.monthlyAcuteMedicationDays(monthsBack: 11)
        let medData = migraines.medicationDistribution
        
        return VStack(spacing: 16) {
            Card(title: "This period") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(days))
                        .scaledFont(size: 36, weight: .bold, design: .rounded)
                        .foregroundStyle(metric.accent)
                    Text(days == 1 ? "day with acute medication" : "days with acute medication")
                        .scaledFont(size: 15, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
                Text("\(doses) \(doses == 1 ? "dose" : "doses") logged. Guidance about acute medication is usually framed in days per month — taking two medications on one day counts as one day.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Card(title: "Medication days per month") {
                if monthly.allSatisfy({ $0.count == 0 }) {
                    emptyState
                } else {
                    MonthlyTrendChart(points: monthly, unit: "day", accent: metric.accent, height: 220)
                    Text("Reference points many clinicians use: \(AcuteMedicationBand.moderateThreshold) or more days a month for simple pain relievers, \(AcuteMedicationBand.frequentThreshold) or more for triptans and combination products. Months at or above those levels are worth raising at your next visit — this app reports them, it does not diagnose medication overuse.")
                        .scaledFont(size: 12)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Card(title: "Which medications") {
                if medData.isEmpty {
                    ChartEmptyState(title: "No Medications Logged", systemImage: "pills",
                                    message: "Add medications when logging an entry to see usage here.", height: 160)
                } else {
                    Chart(medData) { point in
                        BarMark(
                            x: .value("Count", point.count),
                            y: .value("Medication", point.medication)
                        )
                        .foregroundStyle(metric.accent.gradient)
                        .cornerRadius(6)
                    }
                    .frame(height: max(160, CGFloat(medData.count) * 32))
                }
            }
        }
    }
    
    // MARK: - Metric: Total
    
    private var totalContent: some View {
        let monthly = monthlySeries(from: migraines)
        return Card(title: "Migraines per month") {
            if monthly.isEmpty {
                emptyState
            } else {
                Chart(monthly) { point in
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(metric.accent.gradient)
                    .cornerRadius(8)
                }
                .frame(height: 240)
                
                NavigationLink {
                    FilteredMigraineListView(
                        viewModel: viewModel,
                        title: "All Migraines",
                        migraines: migraines.sorted {
                            ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast)
                        }
                    )
                } label: {
                    listLink(text: "See \(migraines.count) entries")
                }
            }
        }
    }
    
    // MARK: - Metric: Average pain
    
    /// Daily aggregate used by the Avg Pain detail. Days with multiple
    /// migraines collapse to a single point (the mean), with `count`
    /// retained so the chart can hint at multi-event days.
    private struct DailyPainPoint: Identifiable {
        let id: Date
        let date: Date
        let mean: Double
        let count: Int
    }
    
    private var averagePainContent: some View {
        let cal = Calendar.current
        var bucket: [Date: [Int]] = [:]
        for migraine in migraines {
            guard let start = migraine.startTime else { continue }
            let day = cal.startOfDay(for: start)
            bucket[day, default: []].append(Int(migraine.painLevel))
        }
        let series: [DailyPainPoint] = bucket
            .map { day, levels in
                let mean = Double(levels.reduce(0, +)) / Double(levels.count)
                return DailyPainPoint(id: day, date: day, mean: mean, count: levels.count)
            }
            .sorted { $0.date < $1.date }
        
        let multiEventDays = series.filter { $0.count > 1 }.count
        
        return Card(title: "Pain over time") {
            if series.count < 2 {
                Text("Need at least 2 days with logged migraines to plot a trend.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Chart(series) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Mean pain", point.mean)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(metric.accent.gradient)
                        
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Mean pain", point.mean)
                        )
                        .symbolSize(point.count > 1 ? 90 : 50)
                        .foregroundStyle(metric.accent)
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            if point.count > 1 {
                                Text("×\(point.count)")
                                    .scaledFont(size: 9, weight: .semibold, design: .rounded)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .chartYScale(domain: 0...10)
                    .frame(height: 240)
                    
                    Text(captionText(dayCount: series.count, multiEventDays: multiEventDays))
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    /// Footer copy for the Avg Pain chart — explains the aggregation so
    /// users aren't surprised by the gap between this view and the Total /
    /// Severe Days numbers (which are per-migraine, not per-day).
    private func captionText(dayCount: Int, multiEventDays: Int) -> String {
        if multiEventDays == 0 {
            return "One point per day. \(dayCount) day\(dayCount == 1 ? "" : "s") plotted."
        }
        return "One point per day (mean). " +
               "\(multiEventDays) day\(multiEventDays == 1 ? "" : "s") had multiple migraines, marked ×n."
    }
    
    // MARK: - Metric: Severe days
    
    private var severeContent: some View {
        let severe = migraines
            .filter { $0.painLevel >= 7 }
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
        
        return VStack(spacing: 16) {
            // Severity bucket bar chart at the top.
            Card(title: "Severity buckets") {
                Chart(migraines.severityBucketDistribution) { point in
                    BarMark(
                        x: .value("Severity", point.bucket.title),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(point.bucket.color.gradient)
                    .cornerRadius(8)
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        if point.count > 0 {
                            Text(String(point.count))
                                .scaledFont(size: 11, weight: .semibold, design: .rounded)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 200)
            }
            
            // Legacy 1-10 histogram for the curious.
            Card(title: "Pain level histogram (1-10)") {
                let histogram: [PainLevelPoint] = {
                    var counts: [Int: Int] = [:]
                    for migraine in migraines {
                        counts[Int(migraine.painLevel), default: 0] += 1
                    }
                    return (1...10).map { PainLevelPoint(level: $0, count: counts[$0] ?? 0) }
                }()
                Chart(histogram) { point in
                    BarMark(
                        x: .value("Level", point.level),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(painLevelColor(point.level).gradient)
                    .cornerRadius(6)
                }
                .frame(height: 200)
            }
            
            Card(title: "Severe migraines (pain ≥ 7)") {
                if severe.isEmpty {
                    Text("None this period.")
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        FilteredMigraineListView(
                            viewModel: viewModel,
                            title: "Severe Migraines",
                            migraines: severe
                        )
                    } label: {
                        listLink(text: "See \(severe.count) entries")
                    }
                }
            }
        }
    }
    
    // MARK: - Metric: Average duration
    
    private var averageDurationContent: some View {
        let durations = migraines.compactMap { migraine -> (Date, TimeInterval)? in
            guard let start = migraine.startTime,
                  let end = migraine.endTime else { return nil }
            return (start, end.timeIntervalSince(start))
        }.sorted(by: { $0.0 < $1.0 })
        
        return Card(title: "Duration over time") {
            if durations.count < 2 {
                Text("Need at least 2 completed migraines (with a recorded end time) to plot.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
            } else {
                Chart(durations.indices, id: \.self) { i in
                    BarMark(
                        x: .value("Date", durations[i].0, unit: .day),
                        y: .value("Hours", durations[i].1 / 3600)
                    )
                    .foregroundStyle(metric.accent.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 240)
            }
        }
    }
    
    // MARK: - Metric: Streak
    
    private var streakContent: some View {
        let streak = viewModel.migraines.currentMigraineFreeStreak()
        return Card(title: "Migraine-free streak") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .scaledFont(size: 28, weight: .semibold)
                        .foregroundStyle(metric.accent)
                    Text(streak.map(String.init) ?? "—")
                        .scaledFont(size: 36, weight: .bold, design: .rounded)
                        .foregroundStyle(.primary)
                    Text(streak.map { $0 == 1 ? "day" : "days" } ?? "no entries")
                        .scaledFont(size: 15, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Counted across all of your data, not just the selected period.")
                    .scaledFont(size: 12)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Metric: Top trigger
    
    private var triggerContent: some View {
        let triggerData = migraines.triggerDistribution
        
        return Card(title: "Trigger frequency") {
            if triggerData.isEmpty {
                ChartEmptyState(title: "No Triggers Logged", systemImage: "bolt.slash",
                                message: "Add triggers when logging an entry to see patterns here.", height: 160)
            } else {
                Chart(triggerData) { point in
                    BarMark(
                        x: .value("Count", point.count),
                        y: .value("Trigger", point.trigger)
                    )
                    .foregroundStyle(metric.accent.gradient)
                    .cornerRadius(6)
                }
                .frame(height: max(220, CGFloat(triggerData.count) * 32))
            }
        }
    }
    
    // MARK: - Metric: Top medication
    
    private var medicationContent: some View {
        let medData = migraines.medicationDistribution
        
        return Card(title: "Medication usage") {
            if medData.isEmpty {
                ChartEmptyState(title: "No Medications Logged", systemImage: "pills",
                                message: "Add medications when logging an entry to see usage here.", height: 160)
            } else {
                Chart(medData) { point in
                    BarMark(
                        x: .value("Count", point.count),
                        y: .value("Medication", point.medication)
                    )
                    .foregroundStyle(metric.accent.gradient)
                    .cornerRadius(6)
                }
                .frame(height: max(220, CGFloat(medData.count) * 32))
            }
        }
    }
    
    // MARK: - Metric: Missed days
    
    private var impactContent: some View {
        let work = migraines.filter { $0.missedWork }
        let school = migraines.filter { $0.missedSchool }
        let events = migraines.filter { $0.missedEvents }
        
        return VStack(spacing: 16) {
            Card(title: "Cumulative impact") {
                Text("Each migraine that disrupted your day is counted once per category.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
            }
            
            if !work.isEmpty {
                Card(title: "Missed work — \(work.count)") {
                    NavigationLink {
                        FilteredMigraineListView(
                            viewModel: viewModel, title: "Missed Work", migraines: work
                        )
                    } label: { listLink(text: "See entries") }
                }
            }
            if !school.isEmpty {
                Card(title: "Missed school — \(school.count)") {
                    NavigationLink {
                        FilteredMigraineListView(
                            viewModel: viewModel, title: "Missed School", migraines: school
                        )
                    } label: { listLink(text: "See entries") }
                }
            }
            if !events.isEmpty {
                Card(title: "Missed events — \(events.count)") {
                    NavigationLink {
                        FilteredMigraineListView(
                            viewModel: viewModel, title: "Missed Events", migraines: events
                        )
                    } label: { listLink(text: "See entries") }
                }
            }
            if work.isEmpty && school.isEmpty && events.isEmpty {
                Card(title: "") {
                    ChartEmptyState(title: "No Life Impact Recorded", systemImage: "calendar.badge.checkmark",
                                    message: "No missed work, school or events were logged in this period.", height: 160)
                }
            }
        }
    }
    
    // MARK: - Metric: Sleep correlation
    
    @ViewBuilder
    private var sleepCorrelationContent: some View {
        if let store = healthStore {
            switch store.status {
            case .unavailable:
                healthUnavailable
            case .notDetermined:
                healthConnectCard
            case .denied:
                healthSettingsCard
            default:
                sleepCorrelationLayout(store: store)
            }
        } else {
            healthUnavailable
        }
    }
    
    private func sleepCorrelationLayout(store: HealthCorrelationStore) -> some View {
        let summary = store.sleepSummary
        let onsetSet = Set(store.migraineOnsets.map { Calendar.current.startOfDay(for: $0) })
        
        return VStack(spacing: 16) {
            Card(title: "Sleep on migraine eves vs. baseline") {
                if let summary, summary.isReliable {
                    sleepHeadline(summary)
                } else {
                    Text(notEnoughDataCopy(for: summary, label: "migraine days"))
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                }
            }
            
            Card(title: "Nightly sleep · \(store.sleepNights.count) night\(store.sleepNights.count == 1 ? "" : "s")") {
                if store.sleepNights.isEmpty {
                    missingDataHint(
                        category: "sleep",
                        capturedBy: "Apple Watch (overnight) or your iPhone's Sleep schedule"
                    )
                } else {
                    Chart {
                        ForEach(store.sleepNights) { sample in
                            BarMark(
                                x: .value("Night", sample.night, unit: .day),
                                y: .value("Hours", sample.hours)
                            )
                            .foregroundStyle(
                                onsetSet.contains(Calendar.current.startOfDay(for: sample.night))
                                    ? Color.pink.gradient
                                    : metric.accent.gradient
                            )
                            .cornerRadius(3)
                        }
                        if let baseline = summary?.baselineMean {
                            RuleMark(y: .value("Baseline", baseline))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.secondary)
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Baseline avg")
                                        .scaledFont(size: 10, weight: .medium, design: .rounded)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 240)
                    
                    HStack(spacing: 14) {
                        legendDot(metric.accent, "Other nights")
                        legendDot(.pink, "Migraine eves")
                    }
                    .scaledFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
                }
            }
            
            Card(title: "Why this matters") {
                Text("Sleep deprivation is one of the most consistent migraine triggers in clinical literature. A persistent gap between migraine-eve sleep and your baseline can suggest a modifiable risk factor — and a useful talking point with your physician.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func sleepHeadline(_ summary: HealthCorrelationSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatHours(summary.migraineMean))
                    .scaledFont(size: 32, weight: .bold, design: .rounded)
                    .foregroundStyle(.primary)
                Text("on migraine eves")
                    .scaledFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatHours(summary.baselineMean))
                    .scaledFont(size: 17, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
                Text("baseline")
                    .scaledFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            if let delta = summary.delta {
                deltaPill(value: delta, formatter: { String(format: "%.1f h", abs($0)) }, lowerIsAdverse: true)
            }
            sampleSizeNote(summary)
        }
    }
    
    // MARK: - Metric: HRV correlation
    
    @ViewBuilder
    private var hrvCorrelationContent: some View {
        if let store = healthStore {
            switch store.status {
            case .unavailable:
                healthUnavailable
            case .notDetermined:
                healthConnectCard
            case .denied:
                healthSettingsCard
            default:
                hrvCorrelationLayout(store: store)
            }
        } else {
            healthUnavailable
        }
    }
    
    private func hrvCorrelationLayout(store: HealthCorrelationStore) -> some View {
        let summary = store.hrvSummary
        let dailyHRV = dailyAverages(store.hrvSamples)
        let onsets = store.migraineOnsets
        
        return VStack(spacing: 16) {
            Card(title: "HRV in the 72 h before a migraine") {
                if let summary, summary.isReliable {
                    hrvHeadline(summary)
                } else {
                    Text(notEnoughDataCopy(for: summary, label: "pre-migraine windows"))
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                }
            }
            
            Card(title: "HRV over time · \(store.hrvSamples.count) reading\(store.hrvSamples.count == 1 ? "" : "s")") {
                if dailyHRV.isEmpty {
                    missingDataHint(
                        category: "heart-rate variability",
                        capturedBy: "Apple Watch overnight"
                    )
                } else {
                    Chart {
                        ForEach(dailyHRV) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("HRV", point.value)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(metric.accent.gradient)
                        }
                        ForEach(onsets, id: \.self) { onset in
                            RuleMark(x: .value("Migraine", onset))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .foregroundStyle(.pink.opacity(0.7))
                        }
                        if let baseline = summary?.baselineMean {
                            RuleMark(y: .value("Baseline", baseline))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.secondary)
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Baseline avg")
                                        .scaledFont(size: 10, weight: .medium, design: .rounded)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 240)
                    
                    HStack(spacing: 14) {
                        legendLine(metric.accent, "Daily HRV")
                        legendLine(.pink, "Migraine onset")
                    }
                    .scaledFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
                }
            }
            
            Card(title: "Why this matters") {
                Text("Heart-rate variability tends to drop in the prodromal (pre-attack) phase, often 24–72 hours before a migraine — a marker of reduced parasympathetic tone. Persistent dips below your baseline before attacks are useful signals to share with your physician.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func hrvHeadline(_ summary: HealthCorrelationSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatMs(summary.migraineMean))
                    .scaledFont(size: 32, weight: .bold, design: .rounded)
                    .foregroundStyle(.primary)
                Text("pre-migraine avg")
                    .scaledFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatMs(summary.baselineMean))
                    .scaledFont(size: 17, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
                Text("baseline")
                    .scaledFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            if let delta = summary.delta {
                deltaPill(value: delta, formatter: { String(format: "%.0f ms", abs($0)) }, lowerIsAdverse: true)
            }
            sampleSizeNote(summary)
        }
    }
    
    // MARK: - Metric: Cycle phase correlation
    
    @ViewBuilder
    private var cyclePhaseContent: some View {
        if let store = healthStore {
            switch store.status {
            case .unavailable:
                healthUnavailable
            case .notDetermined:
                healthConnectCard
            case .denied:
                healthSettingsCard
            default:
                cyclePhaseLayout(store: store)
            }
        } else {
            healthUnavailable
        }
    }
    
    private func cyclePhaseLayout(store: HealthCorrelationStore) -> some View {
        let association = store.cycleAssociation
        let anchored = store.cycleAnchoredMigraines
        
        return VStack(spacing: 16) {
            Card(title: "Around your period") {
                if store.cycleAvailability != .available {
                    // Also reached when Cycle-Aware Insights is off in
                    // Settings or the sex gate excludes the user; the
                    // dashboard hides the card in those cases, so this
                    // copy only matters for the "no data" path.
                    missingDataHint(
                        category: "menstrual cycle",
                        capturedBy: "Apple Health's Cycle Tracking, your iPhone Health app, or a third-party app like Flo"
                    )
                } else if let association {
                    cycleAssociationHeadline(association)
                } else {
                    Text("No logged period starts fall inside this window. Try widening the time filter, or log cycles in Apple Health closer to your migraine days.")
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            if let association, association.confidence != .insufficient {
                Card(title: "Migraine days by day of cycle") {
                    CycleAlignedChart(points: association.aligned, height: 200)
                    Text("Each bar is the share of observed days at that distance from a logged period start on which you had a migraine. Day 0 is the first day of flow; the window is \(PerimenstrualWindow.daysBefore) days before to \(PerimenstrualWindow.daysAfter) days after.")
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Card(title: "Rate comparison") {
                    rateComparison(association)
                }
                
                if association.hasSeverityComparison {
                    Card(title: "Severity") {
                        severityComparison(association)
                    }
                }
            }
            
            if !anchored.isEmpty {
                Card(title: "Phase breakdown") {
                    phaseBreakdownTable(anchored: anchored)
                    Text("Phases use typical day ranges after each logged start and are approximate; the comparison above relies only on logged starts.")
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Card(title: "About this view") {
                Text("Based on your logged entries and the period starts recorded in Apple Health. Hormone changes around menstruation are a well-studied migraine trigger, and many people see attacks cluster in the days around the start of a period. What you see here is an observed pattern, not a diagnosis — the app cannot tell whether a migraine is menstrually related. Discuss patterns with your clinician; a consistent pattern can inform options such as short-term preventive treatment around your period.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Cycle data stays on this iPhone: it is never stored in the log, synced to iCloud or your Watch, or included in exports.")
                    .scaledFont(size: 11)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func cycleAssociationHeadline(_ association: CycleAssociation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                CycleConfidenceBadge(confidence: association.confidence)
                Spacer()
            }
            Text(association.headline)
                .scaledFont(size: 18, weight: .semibold, design: .rounded)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if association.confidence != .insufficient, let recent = association.recentCyclesSummary {
                Text(recent)
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if association.confidence == .insufficient {
                Text(cycleInsufficientCopy(association))
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Based on \(association.migraineDayCount) migraine day\(association.migraineDayCount == 1 ? "" : "s") across \(association.cycleCount) logged cycle\(association.cycleCount == 1 ? "" : "s") in this period. Observed pattern, not a diagnosis.")
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
    
    private func cycleInsufficientCopy(_ association: CycleAssociation) -> String {
        let cyclesNeeded = max(0, CycleAssociationAnalysis.minimumCycles - association.cycleCount)
        let daysNeeded = max(0, CycleAssociationAnalysis.minimumMigraineDays - association.migraineDayCount)
        var parts: [String] = []
        if cyclesNeeded > 0 {
            parts.append("\(cyclesNeeded) more logged cycle\(cyclesNeeded == 1 ? "" : "s")")
        }
        if daysNeeded > 0 {
            parts.append("\(daysNeeded) more migraine day\(daysNeeded == 1 ? "" : "s")")
        }
        guard !parts.isEmpty else {
            return "A comparison needs migraine days both inside and outside the perimenstrual window."
        }
        return "A comparison needs at least \(CycleAssociationAnalysis.minimumCycles) logged cycles and \(CycleAssociationAnalysis.minimumMigraineDays) migraine days in the selected period — about \(parts.joined(separator: " and ")) to go. Widening the time filter often helps."
    }
    
    /// Migraine-day rate inside vs. outside the perimenstrual window,
    /// each shown with its own denominator so the ratio is auditable.
    private func rateComparison(_ association: CycleAssociation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                rateColumn(
                    title: "Perimenstrual days",
                    migraineDays: association.perimenstrualMigraineDays,
                    observedDays: association.perimenstrualDaysObserved,
                    tint: metric.accent
                )
                rateColumn(
                    title: "Other days",
                    migraineDays: association.otherMigraineDays,
                    observedDays: association.otherDaysObserved,
                    tint: .secondary
                )
            }
            if let ratio = association.rateRatio {
                let rounded = (ratio * 10).rounded() / 10
                let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
                Text("Rate ratio \(text)×. A ratio near 1 means migraines were about as likely around your period as at other times.")
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
    
    private func rateColumn(title: String, migraineDays: Int, observedDays: Int, tint: Color) -> some View {
        let rate = observedDays > 0 ? Double(migraineDays) / Double(observedDays) : nil
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
            Text(rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .scaledFont(size: 26, weight: .bold, design: .rounded)
                .foregroundStyle(tint)
            Text("\(migraineDays) of \(observedDays) days")
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    /// Mean pain of attacks inside vs. outside the window; only shown
    /// when both groups have enough attacks to compare.
    private func severityComparison(_ association: CycleAssociation) -> some View {
        let peri = association.perimenstrualMeanPain ?? 0
        let other = association.otherMeanPain ?? 0
        let delta = peri - other
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                painColumn(title: "Perimenstrual", mean: peri, count: association.perimenstrualAttackCount, tint: metric.accent)
                painColumn(title: "Other days", mean: other, count: association.otherAttackCount, tint: .secondary)
            }
            Text(severityCopy(delta: delta))
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
    
    private func painColumn(title: String, mean: Double, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", mean))
                .scaledFont(size: 26, weight: .bold, design: .rounded)
                .foregroundStyle(tint)
            Text("mean pain · \(count) \(count == 1 ? "attack" : "attacks")")
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func severityCopy(delta: Double) -> String {
        if abs(delta) < 0.5 {
            return "Attacks around your period were about as intense as at other times."
        }
        let amount = String(format: "%.1f", abs(delta))
        return delta > 0
            ? "Attacks around your period averaged \(amount) points higher on the pain scale."
            : "Attacks around your period averaged \(amount) points lower on the pain scale."
    }

    private func phaseBreakdownTable(anchored: [CycleAnchoredMigraine]) -> some View {
        let total = max(1, anchored.count)
        var counts: [CyclePhase: Int] = [:]
        for m in anchored { counts[m.phase, default: 0] += 1 }
        return VStack(spacing: 8) {
            ForEach(CyclePhase.allCases) { phase in
                let count = counts[phase] ?? 0
                let pct = Double(count) / Double(total)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(phaseColor(phase))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(phase.title)
                            .scaledFont(size: 13, weight: .semibold, design: .rounded)
                            .foregroundStyle(.primary)
                        Text(phase.dayRange)
                            .scaledFont(size: 11)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(count)")
                        .scaledFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundStyle(.primary)
                    Text("(\(Int((pct * 100).rounded()))%)")
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
    
    private func phaseColor(_ phase: CyclePhase) -> Color {
        switch phase {
        case .menses:     return Color(red: 220/255, green: 80/255, blue: 100/255)
        case .follicular: return Color(red: 110/255, green: 180/255, blue: 130/255)
        case .ovulatory:  return Color(red: 240/255, green: 190/255, blue: 90/255)
        case .luteal:     return Color(red: 110/255, green: 130/255, blue: 200/255)
        }
    }
    
    // MARK: - Health correlation helpers
    
    private struct DailyHRVAverage: Identifiable {
        let id: Date
        let date: Date
        let value: Double
    }
    
    /// Collapses raw HRV samples to one value per day. Charting per-
    /// reading produces a noisy fence; daily mean reads much cleaner
    /// and matches how clinicians look at HRV trends.
    private func dailyAverages(_ samples: [HRVPoint]) -> [DailyHRVAverage] {
        let cal = Calendar.current
        var bucket: [Date: [Double]] = [:]
        for sample in samples {
            let day = cal.startOfDay(for: sample.date)
            bucket[day, default: []].append(sample.valueMs)
        }
        return bucket
            .map { day, values in
                let mean = values.reduce(0, +) / Double(values.count)
                return DailyHRVAverage(id: day, date: day, value: mean)
            }
            .sorted { $0.date < $1.date }
    }
    
    /// Inline hint shown next to an empty per-category chart. Apple
    /// **intentionally does not tell** us whether a missing read
    /// reflects "no data exists" or "the user denied this category"
    /// — so we hedge the copy and offer the Settings deep-link as a
    /// best-effort remedy.
    private func missingDataHint(category: String, capturedBy: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No \(category) data was found inside this window. Either there's no data in Apple Health for these dates, or this category isn't shared with Headway.")
                .scaledFont(size: 13)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(category.capitalized) is typically captured by \(capturedBy).")
                .scaledFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                    Text("Check Permissions")
                        .scaledFont(size: 13, weight: .semibold, design: .rounded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(metric.accent.opacity(0.12))
                )
                .foregroundStyle(metric.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens iOS Settings → Headway. Tap Health to confirm Sleep and HRV are enabled.")
        }
    }

    /// Shown when HealthKit isn't available on this device at all
    /// (Mac, iPad without Health, etc.). No CTA — there's nothing the
    /// user can do from inside the app.
    private var healthUnavailable: some View {
        Card(title: "Apple Health unavailable") {
            Text("Apple Health isn't available on this device, so we can't load sleep, HRV, or menstrual-cycle correlations here. Open Headway on iPhone to view this view.")
                .scaledFont(size: 13)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown when we've never asked for HealthKit permission. Offers a
    /// button that fires the primer + Apple's permission sheet.
    private var healthConnectCard: some View {
        Card(title: "Connect Apple Health") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This view compares your migraines against samples from Apple Health. Grant access to Sleep, HRV, and (optionally) menstrual cycle data to populate it.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        // Direct call here: by the time the user has
                        // navigated this deep into the analytics, the
                        // dashboard's primer has already been shown
                        // (or skipped) once. Showing it again would be
                        // redundant; just trigger the system sheet.
                        // The parent dashboard's `onChange` listener on
                        // `isAuthorized` picks up the change and
                        // reloads the store; we don't reload here
                        // because the detail view doesn't own the
                        // window.
                        await HealthKitManager.shared.requestAuthorization()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                        Text("Connect Health")
                            .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(metric.accent.opacity(0.12))
                    )
                    .foregroundStyle(metric.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Shown when we've already asked but the user denied (or
    /// dismissed Apple's sheet before scrolling). Apple does not
    /// permit re-prompting; deep-link to iOS Settings instead.
    private var healthSettingsCard: some View {
        Card(title: "Apple Health permissions needed") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Health isn't sharing the data needed for this view. You may have dismissed Apple's permission sheet before scrolling through every category. Apple doesn't let apps re-open that sheet — you'll need to flip the toggles in iOS Settings.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                        Text("Open Settings")
                            .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(metric.accent.opacity(0.12))
                    )
                    .foregroundStyle(metric.accent)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens iOS Settings. Tap Health to enable Sleep, HRV, and other categories for Headway.")
            }
        }
    }
    
    private func notEnoughDataCopy(for summary: HealthCorrelationSummary?, label: String) -> String {
        guard let summary else {
            return "No samples in this period yet."
        }
        if summary.migraineSampleCount == 0 {
            return "No data on \(label) inside this window."
        }
        if summary.baselineSampleCount < 3 {
            return "Need at least three baseline days for a confident comparison."
        }
        return "More entries will refine this comparison."
    }
    
    private func sampleSizeNote(_ summary: HealthCorrelationSummary) -> some View {
        Text("Based on \(summary.migraineSampleCount) migraine sample\(summary.migraineSampleCount == 1 ? "" : "s") and \(summary.baselineSampleCount) baseline sample\(summary.baselineSampleCount == 1 ? "" : "s").")
            .scaledFont(size: 11)
            .foregroundStyle(.secondary)
    }
    
    private func deltaPill(
        value: Double,
        formatter: (Double) -> String,
        lowerIsAdverse: Bool
    ) -> some View {
        let absValue = abs(value)
        let color: Color = {
            if absValue < 0.01 { return .secondary }
            let isLower = value < 0
            let isAdverse = lowerIsAdverse ? isLower : !isLower
            return isAdverse ? .orange : .green
        }()
        let arrow: String = {
            if absValue < 0.01 { return "arrow.right" }
            return value < 0 ? "arrow.down.right" : "arrow.up.right"
        }()
        let phrase: String = {
            if absValue < 0.01 { return "On par with baseline" }
            return value < 0 ? "\(formatter(value)) below baseline" : "\(formatter(value)) above baseline"
        }()
        return HStack(spacing: 4) {
            Image(systemName: arrow)
                .scaledFont(size: 10, weight: .bold)
            Text(phrase)
                .scaledFont(size: 12, weight: .semibold, design: .rounded)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(color.opacity(0.15))
        )
        .foregroundStyle(color)
    }
    
    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
    
    private func legendLine(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 14, height: 2)
            Text(label)
        }
    }
    
    private func formatHours(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f h", value)
    }
    
    private func formatMs(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value)
    }
    
    // MARK: - Helpers
    
    private func monthlySeries(from migraines: [MigraineEvent]) -> [MonthlyPoint] {
        guard !migraines.isEmpty else { return [] }
        let cal = Calendar.current
        var counts: [Date: Int] = [:]
        for migraine in migraines {
            guard let start = migraine.startTime else { continue }
            guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) else { continue }
            counts[monthStart, default: 0] += 1
        }
        return counts.map { MonthlyPoint(month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...7: return .yellow
        case 8...10: return .red
        default:    return .gray
        }
    }
    
    private var emptyState: some View {
        ChartEmptyState(title: "No Data for This Period", height: 160)
    }
    
    private func listLink(text: String) -> some View {
        HStack {
            Text(text)
                .scaledFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(.secondary)
        }
    }
}
