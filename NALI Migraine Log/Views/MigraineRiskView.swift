//
//  MigraineRiskView.swift
//  NALI Migraine Log
//
//  Risk prediction dashboard showing current migraine risk,
//  contributing factors, 24-hour forecast, and recommendations.
//

import SwiftUI
import Charts

struct MigraineRiskView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @StateObject private var predictionService = MigrainePredictionService.shared
    @StateObject private var forecastService = WeatherForecastService.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var isRefreshing = false
    @State private var showingDailyCheckIn = false
    @State private var showingHealthKitSetup = false
    @State private var lastRefresh: Date?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.migraines.isEmpty {
                        // No data state
                        insufficientDataCard
                    } else {
                        // Risk gauge
                        riskGaugeCard
                        
                        // Data source badges
                        dataSourceBadges
                        
                        // Contributing factors
                        if let risk = predictionService.currentRisk,
                           !risk.topFactors.isEmpty {
                            contributingFactorsCard(risk.topFactors)
                        }
                        
                        // 24-hour forecast
                        if !predictionService.hourlyForecast.isEmpty {
                            hourlyForecastChart
                        }
                        
                        // Recommendations
                        if let risk = predictionService.currentRisk,
                           !risk.recommendations.isEmpty {
                            recommendationsCard(risk.recommendations)
                        }
                        
                        // Quick actions
                        quickActionsRow
                        
                        // Model status
                        modelStatusCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Risk Prediction")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshPrediction() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .task {
                await initialLoad()
            }
            .sheet(isPresented: $showingDailyCheckIn) {
                DailyCheckInView {
                    Task { await refreshPrediction() }
                }
            }
            .sheet(isPresented: $showingHealthKitSetup) {
                healthKitSetupSheet
            }
        }
    }
    
    // MARK: - Risk Gauge
    
    private var riskGaugeCard: some View {
        VStack(spacing: 16) {
            if let risk = predictionService.currentRisk {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 20)
                        .frame(width: 200, height: 200)
                    
                    // Risk arc — gradient stops are anchored to fixed positions on
                    // the full circle (0% green → 25% yellow → 50% orange → >50% red),
                    // so the leading edge of the visible arc shows the color that
                    // actually corresponds to the current risk percentage.
                    //
                    // We use `.butt` here (instead of `.round`) so the stroke
                    // doesn't extend past the path's start angle. The rounded
                    // "caps" are drawn as separate filled circles below, each
                    // in the exact color it should be — otherwise the
                    // AngularGradient's 0°/360° wraparound (red→green) would
                    // bleed a red sliver into the start cap at the top.
                    Circle()
                        .trim(from: 0, to: risk.overallRisk)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .green,  location: 0.00),
                                    .init(color: .yellow, location: 0.25),
                                    .init(color: .orange, location: 0.50),
                                    .init(color: .red,    location: 0.55),
                                    .init(color: .red,    location: 1.00)
                                ]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 20, lineCap: .butt)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 1.0), value: risk.overallRisk)

                    // Rounded end caps — drawn separately so each can use the
                    // exact color it should be (always green at the low-risk
                    // start; riskLevel.color at the leading edge). This sidesteps
                    // the angular gradient's wraparound discontinuity.
                    if risk.overallRisk > 0 {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 20, height: 20)
                            .offset(y: -100)

                        Circle()
                            .fill(risk.arcLeadingColor)
                            .frame(width: 20, height: 20)
                            .offset(y: -100)
                            .rotationEffect(.degrees(360 * risk.overallRisk))
                            .animation(.easeInOut(duration: 1.0), value: risk.overallRisk)
                    }
                    
                    // Center content
                    VStack(spacing: 4) {
                        Text("\(risk.riskPercentage)%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(risk.riskLevel.color)
                        
                        Text(risk.riskLevel.rawValue)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Label(risk.predictionSource.description, systemImage: risk.predictionSource.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
                
                // Confidence bar
                VStack(spacing: 4) {
                    HStack {
                        Text("Confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(risk.confidence * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemGray5))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: geo.size.width * risk.confidence, height: 6)
                                .animation(.easeInOut, value: risk.confidence)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal)
                
            } else if predictionService.isCalculating {
                ProgressView("Analyzing your data...")
                    .frame(height: 240)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Tap refresh to analyze your risk")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 240)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
    }
    
    // MARK: - Data Source Badges
    
    private var dataSourceBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                dataBadge(
                    icon: "list.bullet",
                    label: "\(viewModel.migraines.count) Entries",
                    isActive: !viewModel.migraines.isEmpty,
                    color: .blue
                )
                
                dataBadge(
                    icon: "cloud.sun.fill",
                    label: "Weather",
                    isActive: forecastService.lastFetchTime != nil,
                    color: .cyan
                )
                
                dataBadge(
                    icon: "heart.fill",
                    label: "HealthKit",
                    isActive: healthKit.isAuthorized,
                    color: .red
                ) {
                    // Three states:
                    //   • already authorized → no-op (badge is
                    //     informational)
                    //   • never asked → show our primer + system sheet
                    //   • asked-and-declined → Apple won't re-prompt;
                    //     deep-link to iOS Settings instead
                    if healthKit.isAuthorized {
                        return
                    }
                    if healthKit.hasRequestedAuthorization {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        showingHealthKitSetup = true
                    }
                }
                
                dataBadge(
                    icon: "pencil.and.list.clipboard",
                    label: "Check-in",
                    isActive: DailyCheckInData.loadToday() != nil,
                    color: .green
                ) {
                    showingDailyCheckIn = true
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func dataBadge(
        icon: String,
        label: String,
        isActive: Bool,
        color: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isActive ? color.opacity(0.15) : Color(.systemGray5))
            )
            .foregroundStyle(isActive ? color : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isActive ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(action == nil)
    }
    
    // MARK: - Contributing Factors
    
    private func contributingFactorsCard(_ factors: [RiskFactor]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Contributing Factors", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
            
            ForEach(factors) { factor in
                HStack(spacing: 12) {
                    Image(systemName: factor.icon)
                        .font(.title3)
                        .foregroundStyle(factor.color)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(factor.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(factor.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    // Contribution bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5))
                            .frame(width: 50, height: 8)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(factor.color)
                            .frame(width: 50 * factor.contribution / 0.30, height: 8)  // scaled to max single weight
                    }
                }
                .padding(.vertical, 4)
                
                if factor.id != factors.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Insufficient Data
    
    private var insufficientDataCard: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 40)
            
            Image(systemName: "chart.line.text.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Not Enough Data")
                .font(.title2.weight(.semibold))
            
            Text("Log your first migraine to start building your personal risk profile. The prediction engine learns from your history to identify patterns and forecast risk.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Log at least 1 migraine to see basic risk", systemImage: "1.circle")
                Label("5+ entries unlock pattern detection", systemImage: "5.circle")
                Label("15+ entries enable machine learning", systemImage: "15.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 24-Hour Forecast Chart
    
    private struct TimePeriodRisk: Identifiable {
        let id = UUID()
        let label: String
        let risk: Double
        
        var color: Color {
            switch risk {
            case 0..<0.25: return .green
            case 0.25..<0.50: return .yellow
            case 0.50..<0.75: return .orange
            default: return .red
            }
        }
    }
    
    private var timePeriodRisks: [TimePeriodRisk] {
        let hours = predictionService.hourlyForecast
        guard !hours.isEmpty else { return [] }
        
        let periods: [(label: String, range: ClosedRange<Int>)] = [
            ("Night",      0...3),
            ("Early AM",   4...7),
            ("Morning",    8...11),
            ("Afternoon",  12...15),
            ("Evening",    16...19),
            ("Late Night", 20...23),
        ]
        
        return periods.compactMap { period in
            let matching = hours.filter { period.range.contains($0.hour) }
            guard !matching.isEmpty else { return nil }
            let avgRisk = matching.map(\.risk).reduce(0, +) / Double(matching.count)
            return TimePeriodRisk(label: period.label, risk: avgRisk)
        }
    }
    
    private var hourlyForecastChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("24-Hour Risk Forecast", systemImage: "chart.bar.fill")
                .font(.headline)
            
            Chart(timePeriodRisks) { period in
                BarMark(
                    x: .value("Period", period.label),
                    y: .value("Risk", period.risk * 100)
                )
                .foregroundStyle(period.color.gradient)
                .cornerRadius(6)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 180)
            .accessibilityLabel("24-hour migraine risk forecast")
            .accessibilityValue(
                timePeriodRisks
                    .map { "\($0.label), \(Int(($0.risk * 100).rounded())) percent" }
                    .joined(separator: "; ")
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Recommendations
    
    private func recommendationsCard(_ recommendations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recommendations", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            
            ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                        .padding(.top, 2)
                    
                    Text(rec)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            quickActionButton(
                icon: "pencil.and.list.clipboard",
                label: "Daily Check-in",
                color: .green
            ) {
                showingDailyCheckIn = true
            }
            
            quickActionButton(
                icon: "arrow.clockwise",
                label: "Refresh",
                color: .blue
            ) {
                Task { await refreshPrediction() }
            }
        }
    }
    
    private func quickActionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.1))
            )
            .foregroundStyle(color)
        }
    }
    
    // MARK: - Model Status
    
    private var modelStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: modelStatusIcon)
                .font(.title3)
                .foregroundStyle(modelStatusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(modelStatusTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(modelStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if case .trainingML(let progress) = predictionService.modelStatus {
                ProgressView(value: progress)
                    .frame(width: 60)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
    
    // MARK: - HealthKit Setup Sheet
    
    private var healthKitSetupSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                
                Text("Connect HealthKit")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Improve prediction accuracy by sharing health data. We'll read sleep, heart rate variability, resting heart rate, step count, and menstrual cycle data.\n\nAll data stays on your device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Apple's permission sheet lists every category as a
                // separate toggle in a scrollable list. On smaller
                // iPhones the bottom toggles fall below the fold,
                // which is the #1 reason users end up missing
                // permissions. Set that expectation up-front so the
                // user knows to scroll.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("On the next screen, **scroll all the way down** and turn on every category you're comfortable sharing.")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    healthBenefit(icon: "moon.zzz.fill", text: "Sleep duration & quality")
                    healthBenefit(icon: "heart.text.square", text: "Heart rate variability (HRV)")
                    healthBenefit(icon: "heart.fill", text: "Resting heart rate")
                    healthBenefit(icon: "figure.walk", text: "Daily step count")
                    healthBenefit(icon: "drop.fill", text: "Menstrual cycle data")
                }
                .padding()
                
                Button {
                    Task {
                        await healthKit.requestAuthorization()
                        showingHealthKitSetup = false
                        await refreshPrediction()
                    }
                } label: {
                    Text("Connect HealthKit")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                
                Button("Not Now") {
                    showingHealthKitSetup = false
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Health Data")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func healthBenefit(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.red)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
    
    // MARK: - Helpers
    
    private func initialLoad() async {
        // Only auto-refresh if we haven't done so recently
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
        
        // 1. Fetch weather forecast
        var weatherSnapshot: WeatherSnapshot?
        if let coords = locationManager.currentCoordinates {
            do {
                let forecast = try await forecastService.fetchForecast(
                    latitude: coords.latitude,
                    longitude: coords.longitude
                )
                weatherSnapshot = forecastService.currentWeatherSnapshot()
                
                // Generate 24h forecast
                _ = predictionService.generate24HourForecast(
                    migraines: viewModel.migraines,
                    forecastHours: forecast,
                    healthData: healthKit.latestSnapshot,
                    dailyCheckIn: DailyCheckInData.loadToday()
                )
            } catch {
                AppLogger.prediction.error("Forecast fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // 2. Fetch HealthKit data. `isAuthorized` is in-memory only and
        // resets on cold launch, so for users who previously granted we
        // first rehydrate (no UI; Apple no-ops the call once the user
        // has decided) before deciding to skip the fetch.
        var healthData: HealthKitSnapshot?
        if !healthKit.isAuthorized && healthKit.hasRequestedAuthorization {
            await healthKit.rehydrateAuthorizationStatus()
        }
        if healthKit.isAuthorized {
            healthData = await healthKit.fetchSnapshot()
        }
        
        // 3. Calculate risk
        let riskScore = await predictionService.calculateRiskScore(
            migraines: viewModel.migraines,
            currentWeather: weatherSnapshot,
            healthData: healthData,
            dailyCheckIn: DailyCheckInData.loadToday()
        )
        
        // 4. Send computed risk to Apple Watch so both show the same value
        WatchConnectivityManager.shared.sendRiskScore(riskScore)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "a" : "p"
        return "\(h)\(ampm)"
    }
    
    private func riskColor(for risk: Double) -> Color {
        switch risk {
        case 0..<0.25: return .green
        case 0.25..<0.50: return .yellow
        case 0.50..<0.75: return .orange
        default: return .red
        }
    }
    
    private var modelStatusIcon: String {
        switch predictionService.modelStatus {
        case .ruleBased: return "brain"
        case .trainingML: return "cpu"
        case .mlActive: return "cpu"
        case .mlFailed: return "exclamationmark.triangle"
        }
    }
    
    private var modelStatusColor: Color {
        switch predictionService.modelStatus {
        case .ruleBased: return .blue
        case .trainingML: return .orange
        case .mlActive: return .green
        case .mlFailed: return .red
        }
    }
    
    private var modelStatusTitle: String {
        switch predictionService.modelStatus {
        case .ruleBased:
            return "Pattern Analysis Active"
        case .trainingML:
            return "Training ML Model..."
        case .mlActive(let confidence):
            return "ML Model Active (\(Int(confidence * 100))%)"
        case .mlFailed:
            return "ML Model Unavailable"
        }
    }
    
    private var modelStatusDetail: String {
        let count = viewModel.migraines.count
        switch predictionService.modelStatus {
        case .ruleBased:
            if count < 20 {
                return "Personalized ML model requires \(20 - count) more entries to activate."
            } else {
                return "Using evidence-based pattern analysis."
            }
        case .trainingML:
            return "Learning from your \(count) migraine entries..."
        case .mlActive:
            return "Personalized predictions based on \(count) entries."
        case .mlFailed:
            return "Falling back to pattern analysis. ML will retry automatically."
        }
    }
}
