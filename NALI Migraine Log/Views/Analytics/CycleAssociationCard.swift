//
//  CycleAssociationCard.swift
//  NALI Migraine Log
//
//  Dashboard card + cycle-aligned chart for the denominator-aware
//  perimenstrual association. Everything shown here is derived in
//  memory from the phone's HealthKit reads; nothing is persisted,
//  exported or sent to the Watch. Copy describes an observed
//  association only — it never labels the user with menstrual migraine.
//

import SwiftUI
import Charts

// MARK: - Confidence pill

struct CycleConfidenceBadge: View {
    let confidence: CycleConfidence

    private var tint: Color {
        switch confidence {
        case .insufficient: return .secondary
        case .early:        return .orange
        case .consistent:   return AnalyticsDomain.cycle.accent
        }
    }

    private var systemImage: String {
        switch confidence {
        case .insufficient: return "hourglass"
        case .early:        return "chart.line.uptrend.xyaxis"
        case .consistent:   return "checkmark.seal.fill"
        }
    }

    var body: some View {
        Label(confidence.title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .scaledFont(size: 11, weight: .semibold, design: .rounded)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Cycle-aligned chart

/// Share of observed days with a migraine at each offset from a logged
/// period start (day 0), −7…+7. Uses the user's own logged starts, so
/// no fixed 28-day assumption is baked in.
struct CycleAlignedChart: View {
    let points: [CycleAlignedPoint]
    var height: CGFloat = 170
    var accent: Color = AnalyticsDomain.cycle.accent

    @State private var selectedOffset: Int?

    private var plotted: [CycleAlignedPoint] { points.filter { $0.observedDays > 0 } }

    private var selectedPoint: CycleAlignedPoint? {
        guard let selectedOffset else { return nil }
        return plotted.first { $0.offset == selectedOffset }
    }

    private var maxRate: Double {
        max(0.1, plotted.compactMap(\.rate).max() ?? 0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(plotted) { point in
                    BarMark(
                        x: .value("Day", point.offset),
                        y: .value("Migraine days", (point.rate ?? 0) * 100),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(point.isPerimenstrual ? accent : accent.opacity(0.35))
                    .cornerRadius(4)
                    .opacity(selectedPoint == nil || selectedPoint?.offset == point.offset ? 1 : 0.5)
                }

                RuleMark(x: .value("Period start", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)

                if let selectedPoint {
                    RuleMark(x: .value("Selected", selectedPoint.offset))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(
                            position: .top,
                            alignment: .center,
                            spacing: 6,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            annotation(for: selectedPoint)
                        }
                }
            }
            .chartXScale(domain: (CycleAssociationAnalysis.alignedRange.lowerBound - 1)...(CycleAssociationAnalysis.alignedRange.upperBound + 1))
            .chartYScale(domain: 0...(maxRate * 100 * 1.15))
            .chartXAxis {
                AxisMarks(values: [-7, -2, 0, 2, 7]) { value in
                    AxisValueLabel {
                        if let offset = value.as(Int.self) {
                            Text(offsetLabel(offset))
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel {
                        if let pct = value.as(Double.self) {
                            Text("\(Int(pct.rounded()))%")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedOffset)
            .frame(height: height)

            HStack(spacing: 12) {
                legendSwatch(accent, "Perimenstrual window")
                legendSwatch(accent.opacity(0.35), "Other days")
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Migraine days by day of cycle")
        .accessibilityValue(accessibilityValue)
        .accessibilityChartDescriptor(audioGraph)
    }

    private func annotation(for point: CycleAlignedPoint) -> some View {
        VStack(spacing: 2) {
            Text(offsetLabel(point.offset, long: true))
                .scaledFont(size: 10, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
            Text("\(point.migraineDays) of \(point.observedDays) days")
                .scaledFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func offsetLabel(_ offset: Int, long: Bool = false) -> String {
        if offset == 0 { return long ? "Period start" : "Start" }
        if long {
            let days = abs(offset) == 1 ? "day" : "days"
            return offset < 0 ? "\(abs(offset)) \(days) before" : "\(offset) \(days) after"
        }
        return offset > 0 ? "+\(offset)" : "\(offset)"
    }

    private var accessibilityValue: String {
        guard !plotted.isEmpty else { return "No observed days" }
        return plotted.map { point in
            "\(offsetLabel(point.offset, long: true)): \(point.migraineDays) of \(point.observedDays) days"
        }.joined(separator: "; ")
    }

    private var audioGraph: BarChartAudioGraph {
        BarChartAudioGraph(
            title: "Migraine days by day of cycle",
            xAxisTitle: "Days from period start",
            yAxisTitle: "Share of days with a migraine",
            bars: plotted.map {
                .init(label: offsetLabel($0.offset, long: true), value: (($0.rate ?? 0) * 100).rounded())
            },
            valueUnit: "percent"
        )
    }
}

// MARK: - Dashboard card

struct CycleAssociationCard: View {
    let association: CycleAssociation?

    private var accent: Color { AnalyticsDomain.cycle.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsSectionHeader("Cycle & Migraines", systemImage: "drop.circle.fill", accent: accent) {
                if let association {
                    CycleConfidenceBadge(confidence: association.confidence)
                }
            }

            if let association {
                Text(association.headline)
                    .scaledFont(size: 17, weight: .semibold, design: .rounded)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if association.confidence != .insufficient, let recent = association.recentCyclesSummary {
                    Text(recent)
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if association.confidence == .insufficient {
                    Text(insufficientCopy(association))
                        .scaledFont(size: 13)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    CycleAlignedChart(points: association.aligned, height: 150)
                }

                AnalyticsFooter(text: footer(association))
            } else {
                Text("Log a few cycles in Apple Health and keep logging migraines to see whether attacks cluster around your period.")
                    .scaledFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .analyticsSurface()
        .padding(.horizontal, 16)
    }

    private func insufficientCopy(_ association: CycleAssociation) -> String {
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
            return "A comparison needs migraine days both inside and outside the window."
        }
        return "About \(parts.joined(separator: " and ")) in this period are needed before a comparison is shown."
    }

    private func footer(_ association: CycleAssociation) -> String {
        "Based on \(association.migraineDayCount) migraine day\(association.migraineDayCount == 1 ? "" : "s") across \(association.cycleCount) logged cycle\(association.cycleCount == 1 ? "" : "s"). Observed pattern, not a diagnosis."
    }
}
