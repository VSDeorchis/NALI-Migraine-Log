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
    
    private var averagePainContent: some View {
        let pain = migraines.compactMap { migraine -> (Date, Int)? in
            guard let date = migraine.startTime else { return nil }
            return (date, Int(migraine.painLevel))
        }.sorted(by: { $0.0 < $1.0 })
        
        return Card(title: "Pain over time") {
            if pain.count < 2 {
                Text("Need at least 2 entries to plot a trend.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Chart(pain.indices, id: \.self) { i in
                    LineMark(
                        x: .value("Date", pain[i].0),
                        y: .value("Pain", pain[i].1)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metric.accent.gradient)
                    PointMark(
                        x: .value("Date", pain[i].0),
                        y: .value("Pain", pain[i].1)
                    )
                    .foregroundStyle(metric.accent)
                }
                .chartYScale(domain: 0...10)
                .frame(height: 240)
            }
        }
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
