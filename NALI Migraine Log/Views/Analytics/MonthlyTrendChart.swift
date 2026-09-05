//
//  MonthlyTrendChart.swift
//  NALI Migraine Log
//
//  Scrollable 12-month bar chart with the user's own average drawn as a
//  reference rule. Bars are tinted relative to that average (not to a
//  fixed "5 is fine, 9 is bad" scale), and tapping/dragging a bar shows
//  a marker + annotation for that month.
//

import SwiftUI
import Charts

struct MonthlyTrendChart: View {
    let points: [MonthlyPoint]
    /// Singular/plural noun used in annotations and VoiceOver, e.g. "day".
    let unit: String
    var accent: Color = AnalyticsDomain.frequency.accent
    /// Months visible at once before the chart scrolls.
    var visibleMonths: Int = 6
    var height: CGFloat = 180
    var averageLabel: String = "Your average"

    @State private var selectedMonth: Date?
    @State private var scrollPosition: Date = .distantPast

    private var calendar: Calendar { .current }
    private var average: Double { points.averageCount }

    private var selectedPoint: MonthlyPoint? {
        guard let selectedMonth else { return nil }
        return points.first {
            calendar.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var initialScrollDate: Date {
        guard let last = points.last?.month else { return Date() }
        return calendar.date(byAdding: .month, value: -(visibleMonths - 1), to: last) ?? last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chart
                .frame(height: height)
                .padding(.top, 6)
                .onAppear { scrollPosition = initialScrollDate }
                .onChange(of: points.count) { scrollPosition = initialScrollDate }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly \(unit) trend")
        .accessibilityValue(accessibilityValue)
        .accessibilityChartDescriptor(audioGraph)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(barColor(for: point))
                .cornerRadius(6)
                .opacity(selectedPoint == nil || selectedPoint?.month == point.month ? 1 : 0.45)
            }

            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("\(averageLabel) \(formattedAverage)")
                            .scaledFont(size: 10, weight: .medium, design: .rounded)
                            .foregroundStyle(.secondary)
                    }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.month, unit: .month))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        selectionAnnotation(selectedPoint)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(Color.gray.opacity(0.3))
                AxisValueLabel()
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartScrollPosition(x: $scrollPosition)
        .chartXSelection(value: $selectedMonth)
        .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(day: 1)))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendSwatch(toneColor(.below), "Below your average")
            legendSwatch(toneColor(.near), "Near")
            legendSwatch(toneColor(.above), "Above")
            Spacer(minLength: 0)
        }
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
                .scaledFont(size: 10, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func selectionAnnotation(_ point: MonthlyPoint) -> some View {
        VStack(spacing: 2) {
            Text(point.month.formatted(.dateTime.month(.abbreviated).year()))
                .scaledFont(size: 10, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
            Text("\(point.count) \(point.count == 1 ? unit : unit + "s")")
                .scaledFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Styling helpers

    private var visibleDomainLength: TimeInterval {
        TimeInterval(visibleMonths) * 30.5 * 86_400
    }

    /// Tallest bar plus ~25% headroom (at least one unit) so the top bar
    /// and its selection annotation don't sit flush against the title.
    private var yAxisUpperBound: Int {
        let peak = points.map(\.count).max() ?? 0
        return peak + max(1, Int((Double(peak) * 0.25).rounded(.up)))
    }

    private func barColor(for point: MonthlyPoint) -> Color {
        toneColor(MonthlyTone.tone(count: point.count, average: average))
    }

    private func toneColor(_ tone: MonthlyTone) -> Color {
        switch tone {
        case .below: return accent.opacity(0.45)
        case .near:  return accent.opacity(0.8)
        case .above: return AnalyticsDomain.severity.accent
        }
    }

    private var formattedAverage: String {
        average == average.rounded() ? String(Int(average)) : String(format: "%.1f", average)
    }

    // MARK: - Accessibility

    private var accessibilityValue: String {
        guard !points.isEmpty else { return "No data" }
        let series = points
            .map { "\($0.month.formatted(.dateTime.month(.abbreviated).year())), \($0.count)" }
            .joined(separator: "; ")
        return "Average \(formattedAverage) \(unit)s per month. \(series)"
    }

    private var audioGraph: BarChartAudioGraph {
        BarChartAudioGraph(
            title: "Monthly \(unit) trend",
            xAxisTitle: "Month",
            yAxisTitle: unit.capitalized + "s",
            counts: points.map {
                ($0.month.formatted(.dateTime.month(.abbreviated).year()), $0.count)
            },
            valueUnit: unit + "s"
        )
    }
}
