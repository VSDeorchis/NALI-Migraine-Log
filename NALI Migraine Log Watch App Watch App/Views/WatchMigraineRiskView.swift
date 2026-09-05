//
//  WatchMigraineRiskView.swift
//  NALI Migraine Log Watch App Watch App
//
//  Compact migraine risk view for watchOS. The score itself is computed on
//  the iPhone (which has weather + Health data); the Watch only displays
//  the last payload it received, with its age, and asks the phone for a
//  fresh one. It never invents a number from local history alone.
//

import SwiftUI

struct WatchMigraineRiskView: View {
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRefreshing = false
    
    /// How long a manual refresh waits for the phone before giving up.
    private let refreshTimeout: Duration = .seconds(8)
    /// A score younger than this is not re-requested just because the view appeared.
    private let autoRefreshAge: TimeInterval = 300
    
    private var syncedRisk: WatchRiskPayload? { connectivity.syncedRisk }
    
    private func riskColor(for level: String) -> Color {
        switch level {
        case "Very High": return .red
        case "High": return .orange
        case "Moderate": return .yellow
        default: return .green
        }
    }
    
    private func displayFactors(_ risk: WatchRiskPayload) -> [RiskFactor] {
        risk.factors.map {
            RiskFactor(name: $0.name, contribution: $0.contribution, icon: $0.icon, color: .orange, detail: $0.detail)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let risk = syncedRisk {
                    riskGauge(risk)
                    
                    let factors = displayFactors(risk)
                    if !factors.isEmpty {
                        topFactorsSection(factors)
                    }
                    
                    let recommendations = Array(risk.recommendations.prefix(2))
                    if !recommendations.isEmpty {
                        recommendationsSection(recommendations)
                    }
                } else {
                    noDataState
                }
                
                refreshButton
                
                if let risk = syncedRisk {
                    Label("Synced from iPhone", systemImage: "iphone")
                        .scaledFont(size: 9)
                        .foregroundStyle(.secondary)
                    
                    Text("Updated \(risk.timestamp, style: .relative) ago")
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                    
                    if risk.isStale() {
                        Label("May be out of date — open Headway on iPhone", systemImage: "clock.badge.exclamationmark")
                            .scaledFont(size: 9)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Risk")
        .task {
            if let risk = syncedRisk, Date().timeIntervalSince(risk.timestamp) < autoRefreshAge {
                return
            }
            await refreshFromPhone()
        }
    }
    
    // MARK: - Risk Gauge
    
    private func riskGauge(_ risk: WatchRiskPayload) -> some View {
        let color = riskColor(for: risk.riskLevel)
        let riskFraction = Double(risk.riskPercentage) / 100.0
        
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: riskFraction)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: riskFraction)
                
                VStack(spacing: 2) {
                    Text("\(risk.riskPercentage)%")
                        .scaledFont(size: 24, weight: .bold, design: .rounded)
                        .foregroundStyle(color)
                    
                    Text(risk.riskLevel)
                        .scaledFont(size: 10, weight: .semibold, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            
            HStack(spacing: 4) {
                Image(systemName: iconForRiskLevel(risk.riskLevel))
                    .scaledFont(size: 12)
                    .foregroundStyle(color)
                Text("Migraine Risk")
                    .scaledFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Migraine risk")
        .accessibilityValue("\(risk.riskPercentage) percent, \(risk.riskLevel)")
    }
    
    // MARK: - No data
    
    private var noDataState: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .scaledFont(size: 28)
                .foregroundStyle(.blue.opacity(0.7))
            Text("No risk score yet")
                .scaledFont(size: 13, weight: .medium)
            Text(isRefreshing
                 ? "Asking your iPhone…"
                 : (connectivity.isReachable
                    ? "Tap Refresh to get today's score from your iPhone."
                    : "Open Headway on your iPhone to calculate today's score."))
                .scaledFont(size: 10)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 100)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
    
    private var refreshButton: some View {
        Button {
            Task { await refreshFromPhone() }
        } label: {
            HStack {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(isRefreshing ? "Updating..." : "Refresh")
            }
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(isRefreshing)
        .padding(.top, 4)
    }
    
    private func iconForRiskLevel(_ level: String) -> String {
        switch level {
        case "Very High": return "xmark.shield.fill"
        case "High": return "exclamationmark.triangle.fill"
        case "Moderate": return "exclamationmark.shield.fill"
        default: return "checkmark.shield.fill"
        }
    }
    
    // MARK: - Top Factors
    
    private func topFactorsSection(_ factors: [RiskFactor]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Factors")
                .scaledFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundStyle(.secondary)
            
            ForEach(factors.prefix(3)) { factor in
                HStack(spacing: 8) {
                    Image(systemName: factor.icon)
                        .scaledFont(size: 12)
                        .foregroundStyle(factor.color)
                        .frame(width: 16)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(factor.name)
                            .scaledFont(size: 12, weight: .medium, design: .rounded)
                            .lineLimit(1)
                        
                        // Mini contribution bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 3)
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(factor.color)
                                    .frame(width: geo.size.width * factor.contribution, height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.darkGray).opacity(0.3))
        )
    }
    
    // MARK: - Recommendations
    
    private func recommendationsSection(_ recommendations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recommendations")
                .scaledFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundStyle(.secondary)
            
            ForEach(recommendations, id: \.self) { rec in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .scaledFont(size: 10)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                    
                    Text(rec)
                        .scaledFont(size: 11, design: .rounded)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.darkGray).opacity(0.3))
        )
    }
    
    // MARK: - Helpers
    
    /// Asks the phone for a fresh score and keeps the spinner up until a
    /// newer payload lands or the timeout passes. The phone recomputes on
    /// every sync request, so no local estimate is needed.
    private func refreshFromPhone() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let previousTimestamp = syncedRisk?.timestamp
        connectivity.requestFullSync()
        
        let deadline = ContinuousClock.now + refreshTimeout
        while ContinuousClock.now < deadline {
            if let current = syncedRisk?.timestamp, current != previousTimestamp {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
        }
    }
}
