//
//  HealthCorrelationsSectionView.swift
//  NALI Migraine Log
//
//  Dashboard section that surfaces the headline numbers from
//  `HealthCorrelationStore`. Two compact cards (Sleep + HRV) live
//  side-by-side; each is a `NavigationLink(value: AnalyticsMetric)`
//  into the full drill-down chart. Cycle association has its own
//  card (`CycleAssociationCard`) higher up the dashboard.
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
        case .notDetermined:
            sectionContainer { connectCTA }
        case .denied:
            sectionContainer { reconnectCTA }
        case .empty:
            sectionContainer { emptyState }
        case .loaded:
            sectionContainer {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        sleepCard
                        hrvCard
                    }
                    AnalyticsFooter(text: "Source: Apple Health. Tap a card for the full comparison.")
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
        .hoverEffect(.lift)
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
        .hoverEffect(.lift)
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
    
    // MARK: - Wrapper container so all states share the same chrome
    
    @ViewBuilder
    private func sectionContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsSectionHeader(
                "Health Correlations",
                systemImage: "heart.text.square.fill",
                accent: AnalyticsDomain.health.accent
            )
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .analyticsSurface()
        .padding(.horizontal, 16)
    }
    
    // MARK: - Connect-Health CTA
    
    /// Shown when the user has NEVER been asked for HealthKit
    /// permission. We can still trigger Apple's permission sheet from
    /// here — the parent routes the tap through the
    /// `HealthKitPermissionPrimerView`.
    private var connectCTA: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Apple Health to see how your sleep and HRV correlate with your migraines.")
                .scaledFont(size: 13)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onConnectTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                    Text("Connect Health")
                        .scaledFont(size: 14, weight: .semibold, design: .rounded)
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

    /// Shown when we've already asked but reads aren't flowing — most
    /// commonly because the user dismissed Apple's permission sheet
    /// without scrolling to the read toggles, or explicitly denied
    /// them. Apple does not allow us to re-prompt the system sheet, so
    /// we deep-link straight into iOS Settings → Headway, where the
    /// user can tap into Health and flip the toggles individually.
    private var reconnectCTA: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Health isn't sharing sleep, HRV, or other samples with Headway. You may have dismissed Apple's permission sheet before scrolling through every category.")
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
                        .fill(Color.teal.opacity(0.12))
                )
                .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens iOS Settings. Tap Health to enable Sleep, HRV, and other categories for Headway.")
        }
    }
    
    /// `.empty` means we have authorization but no samples returned.
    /// Apple deliberately can't tell us *which* read permissions were
    /// denied, so empty is ambiguous — either the device truly has
    /// nothing in this window (no Apple Watch, no sleep schedule,
    /// etc.) or the user denied Sleep/HRV in the system sheet. Offer a
    /// Settings deep-link so they can check.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No sleep or HRV data was found in this window. Either Apple Health has nothing recorded for these dates, or Sleep and HRV aren't shared with Headway.")
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
                    Text("Check Permissions")
                        .scaledFont(size: 14, weight: .semibold, design: .rounded)
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
            .accessibilityHint("Opens iOS Settings. Tap Health to confirm Sleep and HRV are enabled for Headway.")
        }
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
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(metric.accent)
                Text(headline)
                    .scaledFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            
            Text(primaryValue)
                .scaledFont(size: 22, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            if let detail = deltaDescription {
                trendChip(detail)
            } else {
                Text(subtleNote)
                    .scaledFont(size: 10, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
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
                .scaledFont(size: 9, weight: .bold)
            Text(detail)
                .scaledFont(size: 10, weight: .medium, design: .rounded)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }
}
