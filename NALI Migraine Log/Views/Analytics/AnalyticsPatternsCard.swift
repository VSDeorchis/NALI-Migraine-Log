//
//  AnalyticsPatternsCard.swift
//  NALI Migraine Log
//
//  One card, five views: severity buckets, time of day, weekday,
//  associated symptoms and top triggers, switched with a chip row
//  instead of five stacked cards. Tapping a bar drills into the
//  matching entries via `PatternDrillDown`.
//

import SwiftUI
import Charts

/// Which bar the user tapped inside the patterns card. The dashboard
/// turns each case into a `FilteredMigraineListView`.
enum PatternDrillDown: Hashable, Identifiable {
    case severity(SeverityBucket)
    case timeOfDay(String)
    /// 1 = Sunday, matching `Calendar.Component.weekday`.
    case weekday(Int)
    case symptom(MigraineSymptom)
    case trigger(String)

    var id: Self { self }
}

struct AnalyticsPatternsCard: View {
    let migraines: [MigraineEvent]
    let onDrillDown: (PatternDrillDown) -> Void

    enum Pattern: String, CaseIterable, Identifiable {
        case severity = "Severity"
        case timeOfDay = "Time of day"
        case weekday = "Weekday"
        case symptoms = "Symptoms"
        case triggers = "Triggers"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .severity:  return "thermometer.medium"
            case .timeOfDay: return "clock"
            case .weekday:   return "calendar"
            case .symptoms:  return "sparkles"
            case .triggers:  return "bolt.fill"
            }
        }

        var accent: Color {
            switch self {
            case .severity:  return AnalyticsDomain.severity.accent
            case .timeOfDay: return AnalyticsDomain.frequency.accent
            case .weekday:   return AnalyticsDomain.frequency.accent
            case .symptoms:  return AnalyticsDomain.health.accent
            case .triggers:  return AnalyticsDomain.frequency.accent
            }
        }
    }

    @State private var pattern: Pattern = .severity

    private var severity: [SeverityBucketPoint] { migraines.severityBucketDistribution }
    private var timeOfDay: [TimeOfDayPoint] { migraines.timeOfDayDistribution() }
    private var weekdays: [WeekdayPoint] { migraines.weekdayDistribution() }
    private var symptoms: [SymptomPrevalencePoint] { migraines.symptomPrevalence }
    private var triggers: [TriggerPoint] { Array(migraines.triggerDistribution.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsSectionHeader("Patterns", systemImage: "chart.bar.xaxis", accent: pattern.accent)
            chipRow
            content
                .frame(minHeight: 200)
                .motionSafeAnimation(.snappy(duration: 0.25), value: pattern)
            SampleSizeLabel(count: migraines.count, suffix: "in this period. Tap a bar to see those entries.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .analyticsSurface()
        .padding(.horizontal, 16)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Pattern.allCases) { candidate in
                    let isSelected = candidate == pattern
                    Button {
                        pattern = candidate
                    } label: {
                        Label(candidate.rawValue, systemImage: candidate.systemImage)
                            .labelStyle(.titleAndIcon)
                            .scaledFont(size: 12, weight: .semibold, design: .rounded)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? candidate.accent.opacity(0.16) : Color(.tertiarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? candidate.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pattern")
    }

    @ViewBuilder
    private var content: some View {
        switch pattern {
        case .severity:  severityChart
        case .timeOfDay: timeOfDayChart
        case .weekday:   weekdayChart
        case .symptoms:  symptomsChart
        case .triggers:  triggersChart
        }
    }

    // MARK: - Severity

    private var severityChart: some View {
        Chart(severity) { point in
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
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisValueLabel {
                    if let bucketTitle = value.as(String.self),
                       let bucket = SeverityBucket.allCases.first(where: { $0.title == bucketTitle }) {
                        VStack(spacing: 2) {
                            Text(bucket.title)
                                .scaledFont(size: 12, weight: .semibold, design: .rounded)
                                .foregroundStyle(Color.primary)
                            Text(bucket.rangeDescription)
                                .scaledFont(size: 10, weight: .regular, design: .rounded)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis { leadingAxis }
        .chartOverlay { proxy in
            tapOverlay { location in
                guard let title = proxy.value(atX: location.x, as: String.self),
                      let point = severity.first(where: { $0.bucket.title == title }),
                      point.count > 0 else { return }
                onDrillDown(.severity(point.bucket))
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Severity distribution")
        .accessibilityValue(
            severity.filter { $0.count > 0 }
                .map { "\($0.count) \($0.bucket.title.lowercased())" }
                .joined(separator: ", ")
        )
        .accessibilityChartDescriptor(
            BarChartAudioGraph(
                title: "Severity distribution",
                xAxisTitle: "Severity",
                yAxisTitle: "Migraines",
                counts: severity.map { ($0.bucket.title, $0.count) }
            )
        )
    }

    // MARK: - Time of day

    private var timeOfDayChart: some View {
        Chart(timeOfDay) { point in
            BarMark(
                x: .value("Time", point.timeOfDay),
                y: .value("Count", point.count)
            )
            .foregroundStyle(Pattern.timeOfDay.accent.gradient)
            .cornerRadius(8)
        }
        .chartXAxis { bottomAxis }
        .chartYAxis { leadingAxis }
        .chartOverlay { proxy in
            tapOverlay { location in
                guard let slot = proxy.value(atX: location.x, as: String.self),
                      let point = timeOfDay.first(where: { $0.timeOfDay == slot }),
                      point.count > 0 else { return }
                onDrillDown(.timeOfDay(slot))
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Migraines by time of day")
        .accessibilityValue(
            timeOfDay.filter { $0.count > 0 }
                .map { "\($0.timeOfDay), \($0.count)" }
                .joined(separator: "; ")
        )
        .accessibilityChartDescriptor(
            BarChartAudioGraph(
                title: "Migraines by time of day",
                xAxisTitle: "Time of day",
                yAxisTitle: "Migraines",
                counts: timeOfDay.map { ($0.timeOfDay, $0.count) }
            )
        )
    }

    // MARK: - Weekday

    private var weekdayChart: some View {
        let peak = weekdays.map(\.count).max() ?? 0
        return Chart(weekdays) { point in
            BarMark(
                x: .value("Weekday", point.name),
                y: .value("Count", point.count)
            )
            .foregroundStyle(
                point.count == peak && peak > 0
                    ? Pattern.weekday.accent
                    : Pattern.weekday.accent.opacity(0.55)
            )
            .cornerRadius(8)
        }
        .chartXScale(domain: weekdays.map(\.name))
        .chartXAxis { bottomAxis }
        .chartYAxis { leadingAxis }
        .chartOverlay { proxy in
            tapOverlay { location in
                guard let name = proxy.value(atX: location.x, as: String.self),
                      let point = weekdays.first(where: { $0.name == name }),
                      point.count > 0 else { return }
                onDrillDown(.weekday(point.weekday))
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Migraines by weekday")
        .accessibilityValue(
            weekdays.filter { $0.count > 0 }
                .map { "\($0.name), \($0.count)" }
                .joined(separator: "; ")
        )
        .accessibilityChartDescriptor(
            BarChartAudioGraph(
                title: "Migraines by weekday",
                xAxisTitle: "Weekday",
                yAxisTitle: "Migraines",
                counts: weekdays.map { ($0.name, $0.count) }
            )
        )
    }

    // MARK: - Symptoms

    @ViewBuilder
    private var symptomsChart: some View {
        if symptoms.allSatisfy({ $0.count == 0 }) {
            ChartEmptyState(title: "No Symptoms Logged", systemImage: "sparkles", height: 200)
        } else {
            Chart(symptoms) { point in
                BarMark(
                    x: .value("Share", point.share * 100),
                    y: .value("Symptom", point.symptom.title)
                )
                .foregroundStyle(Pattern.symptoms.accent.gradient)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    if point.count > 0 {
                        Text("\(Int((point.share * 100).rounded()))%")
                            .scaledFont(size: 10, weight: .semibold, design: .rounded)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXScale(domain: 0...100)
            .chartYScale(domain: symptoms.map(\.symptom.title))
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel {
                        if let share = value.as(Int.self) {
                            Text("\(share)%")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.primary)
                }
            }
            .chartOverlay { proxy in
                tapOverlay { location in
                    guard let title = proxy.value(atY: location.y, as: String.self),
                          let point = symptoms.first(where: { $0.symptom.title == title }),
                          point.count > 0 else { return }
                    onDrillDown(.symptom(point.symptom))
                }
            }
            .frame(height: CGFloat(symptoms.count) * 30 + 30)
            .accessibilityLabel("Associated symptoms")
            .accessibilityValue(
                symptoms.filter { $0.count > 0 }
                    .map { "\($0.symptom.title), \(Int(($0.share * 100).rounded())) percent" }
                    .joined(separator: "; ")
            )
            .accessibilityChartDescriptor(
                BarChartAudioGraph(
                    title: "Associated symptoms",
                    xAxisTitle: "Symptom",
                    yAxisTitle: "Share of entries",
                    bars: symptoms.map { .init(label: $0.symptom.title, value: ($0.share * 100).rounded()) },
                    valueUnit: "percent"
                )
            )
        }
    }

    // MARK: - Triggers

    @ViewBuilder
    private var triggersChart: some View {
        if triggers.isEmpty {
            ChartEmptyState(title: "No Triggers Logged", systemImage: "bolt.slash", height: 200)
        } else {
            Chart(triggers) { point in
                BarMark(
                    x: .value("Count", point.count),
                    y: .value("Trigger", point.trigger)
                )
                .foregroundStyle(Pattern.triggers.accent.gradient)
                .cornerRadius(6)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(String(point.count))
                        .scaledFont(size: 10, weight: .semibold, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: triggers.map(\.trigger))
            .chartXAxis {
                AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel()
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.primary)
                }
            }
            .chartOverlay { proxy in
                tapOverlay { location in
                    guard let name = proxy.value(atY: location.y, as: String.self),
                          triggers.contains(where: { $0.trigger == name }) else { return }
                    onDrillDown(.trigger(name))
                }
            }
            .frame(height: CGFloat(triggers.count) * 36 + 30)
            .accessibilityLabel("Most common triggers")
            .accessibilityValue(
                triggers.map { "\($0.trigger), \($0.count)" }.joined(separator: "; ")
            )
            .accessibilityChartDescriptor(
                BarChartAudioGraph(
                    title: "Most common triggers",
                    xAxisTitle: "Trigger",
                    yAxisTitle: "Migraines",
                    counts: triggers.map { ($0.trigger, $0.count) }
                )
            )
        }
    }

    // MARK: - Shared axis + overlay helpers

    private var bottomAxis: some AxisContent {
        AxisMarks(position: .bottom) { _ in
            AxisValueLabel()
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
    }

    private var leadingAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                .foregroundStyle(Color.gray.opacity(0.3))
            AxisValueLabel()
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
    }

    private func tapOverlay(_ handler: @escaping (CGPoint) -> Void) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onTapGesture { location in handler(location) }
    }
}
