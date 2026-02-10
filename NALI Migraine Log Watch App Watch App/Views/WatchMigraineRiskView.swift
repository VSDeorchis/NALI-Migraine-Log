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
    @State private var isRefreshing = false
    @State private var lastRefresh: Date?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Risk gauge
                riskGauge
                
                // Top factors
                if let risk = predictionService.currentRisk,
                   !risk.topFactors.isEmpty {
                    topFactorsSection(risk.topFactors)
                }
                
                // Top recommendations
                if let risk = predictionService.currentRisk,
                   !risk.recommendations.isEmpty {
                    recommendationsSection(Array(risk.recommendations.prefix(2)))
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
                
                // Last updated
                if let lastRefresh = lastRefresh {
                    Text("Updated \(lastRefresh, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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
        VStack(spacing: 6) {
            if predictionService.isCalculating && predictionService.currentRisk == nil {
                ProgressView("Analyzing...")
                    .frame(height: 100)
            } else if let risk = predictionService.currentRisk {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        .frame(width: 100, height: 100)
                    
                    // Risk arc
                    Circle()
                        .trim(from: 0, to: risk.overallRisk)
                        .stroke(
                            risk.riskLevel.color,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: risk.overallRisk)
                    
                    // Center content
                    VStack(spacing: 2) {
                        Text("\(risk.riskPercentage)%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(risk.riskLevel.color)
                        
                        Text(risk.riskLevel.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
                
                // Risk level label with icon
                HStack(spacing: 4) {
                    Image(systemName: risk.riskLevel.icon)
                        .font(.system(size: 12))
                        .foregroundColor(risk.riskLevel.color)
                    Text("Migraine Risk")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else {
                // No data yet
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28))
                        .foregroundColor(.blue.opacity(0.6))
                    Text("No risk data")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Tap refresh to analyze")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            }
        }
    }
    
    // MARK: - Top Factors
    
    private func topFactorsSection(_ factors: [RiskFactor]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Factors")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            
            ForEach(factors.prefix(3)) { factor in
                HStack(spacing: 8) {
                    Image(systemName: factor.icon)
                        .font(.system(size: 12))
                        .foregroundColor(factor.color)
                        .frame(width: 16)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(factor.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
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
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            
            ForEach(recommendations, id: \.self) { rec in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                        .padding(.top, 2)
                    
                    Text(rec)
                        .font(.system(size: 11, design: .rounded))
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
        
        // On watchOS, we skip weather forecast and HealthKit for simplicity
        // and use rule-based prediction from migraine history alone
        _ = await predictionService.calculateRiskScore(
            migraines: viewModel.migraines,
            currentWeather: nil,
            healthData: nil,
            dailyCheckIn: nil
        )
    }
}
