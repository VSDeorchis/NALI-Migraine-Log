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
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(metric.accent)
                Text(metric.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
            }
            Text(periodLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Per-metric content
    
    @ViewBuilder
    private var content: some View {
        switch metric {
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .chartYScale(domain: 0...10)
                    .frame(height: 240)
                    
                    Text(captionText(dayCount: series.count, multiEventDays: multiEventDays))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
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
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(metric.accent)
                    Text(streak.map(String.init) ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(streak.map { $0 == 1 ? "day" : "days" } ?? "no entries")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Text("Counted across all of your data, not just the selected period.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Metric: Top trigger
    
    private var triggerContent: some View {
        let triggerData = migraines
            .reduce(into: [MigraineTrigger: Int]()) { counts, migraine in
                for trigger in migraine.triggers {
                    counts[trigger, default: 0] += 1
                }
            }
            .map { TriggerPoint(trigger: $0.key.displayName, count: $0.value) }
            .sorted { $0.count > $1.count }
            .filter { $0.count > 0 }
        
        return Card(title: "Trigger frequency") {
            if triggerData.isEmpty {
                Text("No triggers logged this period.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
        let medData = migraines
            .reduce(into: [MigraineMedication: Int]()) { counts, migraine in
                for medication in migraine.medications {
                    counts[medication, default: 0] += 1
                }
            }
            .map { MedicationPoint(medication: $0.key.displayName, count: $0.value) }
            .sorted { $0.count > $1.count }
            .filter { $0.count > 0 }
        
        return Card(title: "Medication usage") {
            if medData.isEmpty {
                Text("No medications logged this period.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                    Text("No life-impact days this period.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Metric: Sleep correlation
    
    @ViewBuilder
    private var sleepCorrelationContent: some View {
        if let store = healthStore {
            sleepCorrelationLayout(store: store)
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
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Card(title: "Nightly sleep · \(store.sleepNights.count) night\(store.sleepNights.count == 1 ? "" : "s")") {
                if store.sleepNights.isEmpty {
                    Text("No sleep data was recorded inside this window.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                        }
                    }
                    .frame(height: 240)
                    
                    HStack(spacing: 14) {
                        legendDot(metric.accent, "Other nights")
                        legendDot(.pink, "Migraine eves")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                }
            }
            
            Card(title: "Why this matters") {
                Text("Sleep deprivation is one of the most consistent migraine triggers in clinical literature. A persistent gap between migraine-eve sleep and your baseline can suggest a modifiable risk factor — and a useful talking point with your physician.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func sleepHeadline(_ summary: HealthCorrelationSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatHours(summary.migraineMean))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("on migraine eves")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatHours(summary.baselineMean))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text("baseline")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
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
            hrvCorrelationLayout(store: store)
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
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Card(title: "HRV over time · \(store.hrvSamples.count) reading\(store.hrvSamples.count == 1 ? "" : "s")") {
                if dailyHRV.isEmpty {
                    Text("No HRV data was recorded inside this window. HRV is captured automatically by Apple Watch overnight.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                        }
                    }
                    .frame(height: 240)
                    
                    HStack(spacing: 14) {
                        legendLine(metric.accent, "Daily HRV")
                        legendLine(.pink, "Migraine onset")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                }
            }
            
            Card(title: "Why this matters") {
                Text("Heart-rate variability tends to drop in the prodromal (pre-attack) phase, often 24–72 hours before a migraine — a marker of reduced parasympathetic tone. Persistent dips below your baseline before attacks are useful signals to share with your physician.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func hrvHeadline(_ summary: HealthCorrelationSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatMs(summary.migraineMean))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("pre-migraine avg")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatMs(summary.baselineMean))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text("baseline")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
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
            cyclePhaseLayout(store: store)
        } else {
            healthUnavailable
        }
    }
    
    private func cyclePhaseLayout(store: HealthCorrelationStore) -> some View {
        let distribution = store.cyclePhaseSummary
        let anchored = store.cycleAnchoredMigraines
        
        return VStack(spacing: 16) {
            Card(title: "Migraines by cycle phase") {
                if store.cycleAvailability != .available {
                    Text("Once you log menstrual flow in Apple Health, your migraines will be grouped by cycle phase here automatically.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let distribution, distribution.totalAnchored > 0 {
                    cycleHeadline(distribution)
                } else {
                    Text("No migraines in this window could be anchored to a recent flow start. Try widening the time filter or logging cycles closer to migraine days.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            if !anchored.isEmpty {
                Card(title: "Distribution by cycle day") {
                    cycleDayHistogram(anchored: anchored)
                    HStack(spacing: 14) {
                        legendDot(perimenstrualBand, "Perimenstrual (days 26-3)")
                        legendDot(metric.accent, "Other days")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                }
                
                Card(title: "Phase breakdown") {
                    phaseBreakdownTable(anchored: anchored)
                }
            }
            
            if let distribution, distribution.unanchoredCount > 0 {
                Card(title: "About missing days") {
                    Text("\(distribution.unanchoredCount) migraine\(distribution.unanchoredCount == 1 ? "" : "s") in this period couldn't be matched to a recent flow start (more than 45 days since the last logged cycle). Logging cycles consistently in Apple Health improves this view's accuracy.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Card(title: "Why this matters") {
                Text("Estrogen withdrawal in the days surrounding menstruation is one of the most studied migraine triggers. Many people see their attacks cluster around days 26 of one cycle through day 3 of the next — the perimenstrual window. A pattern here is often actionable with your physician (e.g. mini-prophylaxis, hormonal strategies).")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func cycleHeadline(_ distribution: CyclePhaseDistribution) -> some View {
        let topPhase = distribution.counts.max(by: { $0.value < $1.value })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(distribution.totalAnchored)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("migraines anchored to a cycle")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            if let topPhase {
                let pct = Int((Double(topPhase.value) / Double(max(1, distribution.totalAnchored)) * 100).rounded())
                Text("\(pct)% in your \(topPhase.key.title.lowercased()) phase (\(topPhase.key.dayRange))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            if let perimenPct = distribution.perimenstrualPercentage {
                let pct = Int((perimenPct * 100).rounded())
                Text("\(pct)% in the perimenstrual window (days 26-3)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.pink)
            }
            Text("Based on \(distribution.totalAnchored) anchored migraine\(distribution.totalAnchored == 1 ? "" : "s") in this period.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    /// Datapoint for the per-cycle-day histogram. Owning a real type
    /// (rather than a tuple) keeps `Chart(_:)` and `id:` stable across
    /// Swift versions.
    private struct CycleDayBucket: Identifiable {
        let id: Int
        var day: Int { id }
        let count: Int
        let isPerimenstrual: Bool
    }
    
    /// Bar chart of migraine counts per cycle day (1-35). Bars in the
    /// perimenstrual band (days 26+ and 1-3) are tinted pink to match
    /// the "estrogen withdrawal" framing in clinical literature.
    private func cycleDayHistogram(anchored: [CycleAnchoredMigraine]) -> some View {
        let maxDay = max(28, anchored.map(\.cycleDay).max() ?? 28)
        var counts: [Int: Int] = [:]
        for m in anchored { counts[m.cycleDay, default: 0] += 1 }
        let series: [CycleDayBucket] = (1...maxDay).map { day in
            CycleDayBucket(
                id: day,
                count: counts[day] ?? 0,
                isPerimenstrual: day >= 26 || day <= 3
            )
        }
        
        return Chart(series) { row in
            BarMark(
                x: .value("Cycle day", row.day),
                y: .value("Migraines", row.count)
            )
            .foregroundStyle(row.isPerimenstrual ? perimenstrualBand : metric.accent)
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 1, through: maxDay, by: 5))) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text("\(day)").font(.system(size: 10))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 200)
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
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(phase.dayRange)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("(\(Int((pct * 100).rounded()))%)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
    
    /// Colour shared between the cycle-day histogram band and the
    /// "perimenstrual" headline copy.
    private var perimenstrualBand: Color {
        Color(red: 220/255, green: 80/255, blue: 100/255)
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
    
    private var healthUnavailable: some View {
        Card(title: "Apple Health required") {
            Text("Health correlations need access to your sleep and heart-rate variability samples. Open Settings → Privacy → Health and grant access to enable this view.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            .font(.system(size: 11))
            .foregroundColor(.secondary)
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
                .font(.system(size: 10, weight: .bold))
            Text(phrase)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: start))!
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
        Text("No data for this period.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
    }
    
    private func listLink(text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}
