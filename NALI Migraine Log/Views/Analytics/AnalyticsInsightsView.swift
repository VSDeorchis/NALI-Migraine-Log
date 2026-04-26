//
//  AnalyticsInsightsView.swift
//  NALI Migraine Log
//
//  Generates a small set of human-readable observations from the filtered
//  migraine data, then renders them as compact cards. The generator is
//  deliberately conservative — it only emits a card when the underlying
//  signal is strong enough to be useful (e.g. the same trigger present in
//  ≥ 30% of entries, a streak of ≥ 7 days). Cards never make medical
//  claims; copy is observational and matches the disclaimer language used
//  elsewhere in the app.
//

import SwiftUI

// MARK: - Generator

enum AnalyticsInsightGenerator {
    
    /// Returns the curated list of insight cards for the given filtered set.
    /// At most 4 cards are returned so the section never dominates the
    /// scroll view; ordered from strongest to weakest signal.
    static func generate(
        for migraines: [MigraineEvent],
        currentStreak: Int?
    ) -> [AnalyticsInsight] {
        guard !migraines.isEmpty else { return [] }
        
        var insights: [AnalyticsInsight] = []
        
        // Migraine-free streak (positive reinforcement).
        if let streak = currentStreak, streak >= 7 {
            insights.append(
                AnalyticsInsight(
                    title: "\(streak)-day streak",
                    detail: "It's been \(streak) days since your last logged migraine — keep it up.",
                    systemImage: "flame.fill",
                    tone: .positive
                )
            )
        }
        
        // Top trigger ≥ 30% share.
        if let top = migraines.topTrigger {
            let share = Double(top.count) / Double(migraines.count)
            if share >= 0.30 {
                let percent = Int((share * 100).rounded())
                insights.append(
                    AnalyticsInsight(
                        title: "Recurring trigger",
                        detail: "\(top.trigger.displayName) appears in \(percent)% of your migraines this period.",
                        systemImage: "bolt.fill",
                        tone: .alert
                    )
                )
            }
        }
        
        // Most common day-of-week (only if it accounts for ≥ 25%).
        if let dow = migraines.mostCommonWeekday(), dow.share >= 0.25 {
            let percent = Int((dow.share * 100).rounded())
            insights.append(
                AnalyticsInsight(
                    title: "\(dow.name) pattern",
                    detail: "\(percent)% of migraines this period started on \(dow.name).",
                    systemImage: "calendar",
                    tone: .neutral
                )
            )
        }
        
        // Severe-pain proportion.
        let severeCount = migraines.filter { $0.painLevel >= 7 }.count
        if migraines.count >= 3 {
            let severeShare = Double(severeCount) / Double(migraines.count)
            if severeShare >= 0.5 {
                let percent = Int((severeShare * 100).rounded())
                insights.append(
                    AnalyticsInsight(
                        title: "High severity",
                        detail: "\(percent)% of this period's migraines reached pain 7 or higher.",
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .alert
                    )
                )
            } else if severeShare == 0 {
                insights.append(
                    AnalyticsInsight(
                        title: "No severe migraines",
                        detail: "None of this period's migraines reached pain 7 or higher.",
                        systemImage: "checkmark.shield.fill",
                        tone: .positive
                    )
                )
            }
        }
        
        // Aura prevalence.
        let auraCount = migraines.filter { $0.hasAura }.count
        if migraines.count >= 3 {
            let auraShare = Double(auraCount) / Double(migraines.count)
            if auraShare >= 0.5 {
                let percent = Int((auraShare * 100).rounded())
                insights.append(
                    AnalyticsInsight(
                        title: "Aura common",
                        detail: "\(percent)% of this period's migraines included aura symptoms.",
                        systemImage: "sparkles",
                        tone: .neutral
                    )
                )
            }
        }
        
        return Array(insights.prefix(4))
    }
}

// MARK: - View

struct AnalyticsInsightsView: View {
    let insights: [AnalyticsInsight]
    
    var body: some View {
        if insights.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Insights", systemImage: "lightbulb.fill")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 4)
                
                VStack(spacing: 12) {
                    ForEach(insights) { insight in
                        InsightCardView(insight: insight)
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

private struct InsightCardView: View {
    let insight: AnalyticsInsight
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(insight.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: insight.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(insight.tint)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(insight.detail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.title). \(insight.detail)")
    }
}
