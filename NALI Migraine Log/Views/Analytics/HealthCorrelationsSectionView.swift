//
//  HealthCorrelationsSectionView.swift
//  NALI Migraine Log
//
//  Dashboard section that surfaces the headline numbers from
//  `HealthCorrelationStore`. Two compact cards (Sleep + HRV) live
//  side-by-side; each is a `NavigationLink(value: AnalyticsMetric)`
//  into the full drill-down chart.
//
//  The whole section hides on devices without HealthKit, and degrades
//  gracefully when:
//    • the user hasn't authorized → "Connect Health" CTA
//    • there's no data in the window → soft empty state
//
//  Card copy is intentionally hedged ("Sleep was a little shorter on
//  migraine days") because n is usually small early on; we only
//  surface a confident comparison via `summary.isReliable`.
//

import SwiftUI
import Charts

struct HealthCorrelationsSectionView: View {
    @ObservedObject var store: HealthCorrelationStore
    /// Triggered by the "Connect Health" CTA — defers the actual
    /// authorization call to the parent so the whole view tree shares
    /// a single `requestAuthorization()` path.
    var onConnectTapped: () -> Void = {}
    
    var body: some View {
        switch store.status {
        case .unavailable:
            EmptyView()
        case .idle, .loading:
            sectionContainer {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        case .unauthorized:
            sectionContainer { connectCTA }
        case .empty:
            sectionContainer { emptyState }
        case .loaded:
            sectionContainer {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        sleepCard
                        hrvCard
                    }
                    // Cycle card lives below the sleep/HRV pair and only
                    // appears for users who actually log menstrual flow
                    // in Apple Health (data-driven gate, not gender-gated).
                    if store.cycleAvailability == .available {
                        cycleCard
                    }
                    Text("Tap a card for the full chart and clinical-grade comparison.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    // MARK: - Sleep card
    
    private var sleepCard: some View {
        NavigationLink(value: AnalyticsMetric.sleepCorrelation) {
            CorrelationCard(
                metric: .sleepCorrelation,
                summary: store.sleepSummary,
                formatter: { hours in String(format: "%.1f h", hours) },
                spark: sleepSparkline,
                lowerIsAdverse: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens sleep correlation details")
    }
    
    private var sleepSparkline: AnyView {
        AnyView(
            Chart(store.sleepNights) { sample in
                BarMark(
                    x: .value("Date", sample.night, unit: .day),
                    y: .value("Hours", sample.hours)
                )
                .foregroundStyle(AnalyticsMetric.sleepCorrelation.accent.opacity(0.65))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 32)
        )
    }
    
    // MARK: - HRV card
    
    private var hrvCard: some View {
        NavigationLink(value: AnalyticsMetric.hrvCorrelation) {
            CorrelationCard(
                metric: .hrvCorrelation,
                summary: store.hrvSummary,
                formatter: { ms in String(format: "%.0f ms", ms) },
                spark: hrvSparkline,
                lowerIsAdverse: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens HRV correlation details")
    }
    
    private var hrvSparkline: AnyView {
        AnyView(
            Chart(store.hrvSamples) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("HRV", point.valueMs)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(AnalyticsMetric.hrvCorrelation.accent)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 32)
        )
    }
    
    // MARK: - Cycle card
    
    /// Full-width card showing the per-phase distribution of migraines
    /// for users who track menstrual flow in HealthKit. Hidden entirely
    /// on devices/users without that data.
    private var cycleCard: some View {
        NavigationLink(value: AnalyticsMetric.cyclePhase) {
            CycleCorrelationCard(distribution: store.cyclePhaseSummary)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens cycle correlation details")
    }
    
    // MARK: - Wrapper container so all states share the same chrome
    
    @ViewBuilder
    private func sectionContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Health Correlations", systemImage: "heart.text.square.fill")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.teal)
                .padding(.horizontal, 4)
            content()
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
    
    // MARK: - Connect-Health CTA
    
    private var connectCTA: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Apple Health to see how your sleep and HRV correlate with your migraines.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onConnectTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                    Text("Connect Health")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.teal.opacity(0.12))
                )
                .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var emptyState: some View {
        Text("No sleep or HRV data was found in this window. Once your Apple Watch records data here, correlations will appear automatically.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Reusable correlation card

/// Single sleep- or HRV-style correlation card. Shows the migraine-day
/// mean, the baseline mean, the delta, and a tiny sparkline for
/// at-a-glance shape.
private struct CorrelationCard: View {
    let metric: AnalyticsMetric
    let summary: HealthCorrelationSummary?
    /// Converts a raw value (hours, ms, …) into a UI-ready string.
    let formatter: (Double) -> String
    /// Sparkline content rendered along the bottom of the card.
    let spark: AnyView
    /// True when *lower* values are adverse (sleep, HRV both qualify).
    /// Drives the trend chip's red/green colour and arrow direction.
    let lowerIsAdverse: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(metric.accent)
                Text(headline)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            
            Text(primaryValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            if let detail = deltaDescription {
                trendChip(detail)
            } else {
                Text(subtleNote)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            spark
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(metric.accent.opacity(0.25), lineWidth: 1)
        )
    }
    
    // MARK: - Card copy helpers
    
    private var headline: String {
        switch metric {
        case .sleepCorrelation: return "Sleep · migraine days"
        case .hrvCorrelation:   return "HRV · pre-migraine"
        default:                return metric.title
        }
    }
    
    private var primaryValue: String {
        if let mean = summary?.migraineMean {
            return formatter(mean)
        }
        return "—"
    }
    
    /// Subtitle when we can't yet compute a delta. Keeps the card from
    /// looking broken when the user simply has too few migraine days
    /// in the window for a comparison.
    private var subtleNote: String {
        guard let summary else { return "Not enough data yet" }
        if summary.migraineMean == nil { return "No data on migraine days yet" }
        if summary.baselineMean == nil { return "No baseline data yet" }
        return "Logging more events will refine this"
    }
    
    private var deltaDescription: String? {
        guard let summary, summary.isReliable, let delta = summary.delta else { return nil }
        let absDelta = abs(delta)
        let signed = formatter(absDelta)
        if abs(delta) < (metric == .sleepCorrelation ? 0.2 : 1.5) {
            return "Similar to baseline"
        }
        if metric == .sleepCorrelation {
            return delta < 0
                ? "\(signed) less on migraine eves"
                : "\(signed) more on migraine eves"
        } else {
            return delta < 0
                ? "\(signed) lower before migraines"
                : "\(signed) higher before migraines"
        }
    }
    
    private func trendChip(_ detail: String) -> some View {
        let isAdverse: Bool = {
            guard let delta = summary?.delta else { return false }
            return lowerIsAdverse ? delta < -0.01 : delta > 0.01
        }()
        let isBenign: Bool = {
            guard let delta = summary?.delta else { return false }
            return lowerIsAdverse ? delta > 0.01 : delta < -0.01
        }()
        let arrow: String = {
            guard let delta = summary?.delta else { return "arrow.right" }
            if abs(delta) < 0.01 { return "arrow.right" }
            return delta > 0 ? "arrow.up.right" : "arrow.down.right"
        }()
        let color: Color = isAdverse ? .orange : (isBenign ? .green : .secondary)
        return HStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.system(size: 9, weight: .bold))
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Cycle correlation card

/// Full-width card summarizing how this window's migraines were
/// distributed across the cycle. Stacked phase bar visualises
/// proportion at-a-glance; a perimenstrual headline numbers the days
/// most associated with estrogen-withdrawal migraine.
private struct CycleCorrelationCard: View {
    let distribution: CyclePhaseDistribution?
    
    private static let phaseColors: [CyclePhase: Color] = [
        .menses:     Color(red: 220/255, green: 80/255, blue: 100/255),
        .follicular: Color(red: 110/255, green: 180/255, blue: 130/255),
        .ovulatory:  Color(red: 240/255, green: 190/255, blue: 90/255),
        .luteal:     Color(red: 110/255, green: 130/255, blue: 200/255)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: AnalyticsMetric.cyclePhase.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AnalyticsMetric.cyclePhase.accent)
                Text("Cycle phase distribution")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            Text(headline)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let distribution, distribution.totalAnchored > 0 {
                phaseBar(distribution: distribution)
                phaseLegend(distribution: distribution)
            } else {
                Text("Log a few cycles in Apple Health to see how migraines line up with your phases.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AnalyticsMetric.cyclePhase.accent.opacity(0.25), lineWidth: 1)
        )
    }
    
    private var headline: String {
        guard let distribution, distribution.totalAnchored > 0 else {
            return "Cycle data is being collected"
        }
        if distribution.isReliable, let pct = distribution.perimenstrualPercentage {
            let percentString = "\(Int((pct * 100).rounded()))%"
            if pct >= 0.5 {
                return "\(percentString) of migraines fell in the perimenstrual window"
            } else if pct >= 0.3 {
                return "\(percentString) of migraines were perimenstrual"
            } else if let topPhase = topPhase(distribution) {
                return "Most migraines occurred in your \(topPhase.title.lowercased()) phase"
            }
        }
        return "Tracking migraines across your cycle"
    }
    
    private func topPhase(_ distribution: CyclePhaseDistribution) -> CyclePhase? {
        distribution.counts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Horizontal stacked bar with one segment per phase, sized in
    /// proportion to that phase's share of the migraines.
    private func phaseBar(distribution: CyclePhaseDistribution) -> some View {
        let total = max(1, distribution.totalAnchored)
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(CyclePhase.allCases) { phase in
                    let count = distribution.counts[phase] ?? 0
                    if count > 0 {
                        let width = geo.size.width * CGFloat(count) / CGFloat(total)
                        Rectangle()
                            .fill(Self.phaseColors[phase] ?? .gray)
                            .frame(width: max(2, width))
                    }
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    
    private func phaseLegend(distribution: CyclePhaseDistribution) -> some View {
        let total = max(1, distribution.totalAnchored)
        return HStack(spacing: 10) {
            ForEach(CyclePhase.allCases) { phase in
                let count = distribution.counts[phase] ?? 0
                let pct = Int((Double(count) / Double(total) * 100).rounded())
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.phaseColors[phase] ?? .gray)
                        .frame(width: 8, height: 8)
                    Text("\(phase.title) \(pct)%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}
