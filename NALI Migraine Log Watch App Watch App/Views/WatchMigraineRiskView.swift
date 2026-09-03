//
//  WatchMigraineRiskView.swift
//  NALI Migraine Log Watch App Watch App
//
//  Compact migraine risk prediction view for watchOS.
//

import SwiftUI

struct WatchMigraineRiskView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @StateObject private var predictionService = MigrainePredictionService.shared
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    @State private var isRefreshing = false
    @State private var lastRefresh: Date?
    
    /// iPhone-synced risk when it is recent (less than 30 min old); otherwise nil.
    private var freshSyncedRisk: WatchRiskPayload? {
        guard let synced = connectivity.syncedRisk,
              Date().timeIntervalSince(synced.timestamp) < 1800 else { return nil }
        return synced
    }
    
    /// Effective risk percentage to display (prefer iPhone-synced value)
    private var displayRiskPercentage: Int {
        freshSyncedRisk?.riskPercentage ?? predictionService.currentRisk?.riskPercentage ?? 0
    }
    
    /// Effective risk level string
    private var displayRiskLevel: String {
        freshSyncedRisk?.riskLevel ?? predictionService.currentRisk?.riskLevel.rawValue ?? "Low"
    }
    
    /// Effective risk color
    private var displayRiskColor: Color {
        switch displayRiskLevel {
        case "Very High": return .red
        case "High": return .orange
        case "Moderate": return .yellow
        default: return .green
        }
    }
    
    /// Effective recommendations
    private var displayRecommendations: [String] {
        if let recs = freshSyncedRisk?.recommendations, !recs.isEmpty {
            return Array(recs.prefix(2))
        }
        return Array((predictionService.currentRisk?.recommendations ?? []).prefix(2))
    }
    
    /// Effective factors for display
    private var displayFactors: [RiskFactor] {
        if let factors = freshSyncedRisk?.factors {
            return factors.map {
                RiskFactor(name: $0.name, contribution: $0.contribution, icon: $0.icon, color: .orange, detail: $0.detail)
            }
        }
        return Array((predictionService.currentRisk?.topFactors ?? []).prefix(3))
    }
    
    /// Last updated time
    private var displayLastUpdated: Date? {
        freshSyncedRisk?.timestamp ?? lastRefresh
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Risk gauge
                riskGauge
                
                // Top factors
                if !displayFactors.isEmpty {
                    topFactorsSection(displayFactors)
                }
                
                // Top recommendations
                if !displayRecommendations.isEmpty {
                    recommendationsSection(displayRecommendations)
                }
                
                // Refresh button
                Button {
                    Task { await refreshPrediction() }
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
                
                // Data source indicator
                if hasFreshSyncedRisk {
                    Label("Synced from iPhone", systemImage: "iphone")
                        .scaledFont(size: 9)
                        .foregroundStyle(.secondary)
                }
                
                // Last updated
                if let updated = displayLastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Risk")
        .task {
            await initialLoad()
        }
    }
    
    // MARK: - Risk Gauge
    
    private var riskGauge: some View {
        let hasData = hasFreshSyncedRisk || predictionService.currentRisk != nil
        let riskFraction = Double(displayRiskPercentage) / 100.0
        
        return VStack(spacing: 6) {
            if predictionService.isCalculating && !hasData {
                ProgressView("Analyzing...")
                    .frame(height: 100)
            } else if hasData {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        .frame(width: 100, height: 100)
                    
                    // Risk arc
                    Circle()
                        .trim(from: 0, to: riskFraction)
                        .stroke(
                            displayRiskColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: riskFraction)
                    
                    // Center content
                    VStack(spacing: 2) {
                        Text("\(displayRiskPercentage)%")
                            .scaledFont(size: 24, weight: .bold, design: .rounded)
                            .foregroundStyle(displayRiskColor)
                        
                        Text(displayRiskLevel)
                            .scaledFont(size: 10, weight: .semibold, design: .rounded)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                
                // Risk level label with icon
                HStack(spacing: 4) {
                    Image(systemName: iconForRiskLevel(displayRiskLevel))
                        .scaledFont(size: 12)
                        .foregroundStyle(displayRiskColor)
                    Text("Migraine Risk")
                        .scaledFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            } else {
                // No data yet
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .scaledFont(size: 28)
                        .foregroundStyle(.blue.opacity(0.6))
                    Text("No risk data")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(.secondary)
                    Text("Tap refresh to analyze")
                        .scaledFont(size: 10)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 100)
            }
        }
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
    
    private func initialLoad() async {
        if lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) > 300 {
            await refreshPrediction()
        }
    }
    
    private func refreshPrediction() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }
        
        // Request fresh risk data from the iPhone (which has weather + HealthKit)
        connectivity.requestFullSync()
        
        // Also compute a local fallback from migraine history alone,
        // used only if we don't have a fresh synced score from iPhone
        _ = await predictionService.calculateRiskScore(
            migraines: viewModel.migraines,
            currentWeather: nil,
            healthData: nil,
            dailyCheckIn: nil
        )
    }
}
