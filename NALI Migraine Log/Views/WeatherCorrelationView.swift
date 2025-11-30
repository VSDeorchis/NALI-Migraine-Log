//
//  WeatherCorrelationView.swift
//  NALI Migraine Log
//
//  Weather correlation analytics view
//

import SwiftUI
import Charts

struct WeatherCorrelationView: View {
    @ObservedObject var viewModel: MigraineViewModel
    let timeFilter: StatisticsView.TimeFilter
    let selectedYear: Int
    let customStartDate: Date
    let customEndDate: Date
    
    @State private var selectedWeatherCondition: String?
    
    private var filteredMigraines: [MigraineEvent] {
        let calendar = Calendar.current
        let now = Date()
        
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            
            switch timeFilter {
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
                return startTime >= weekAgo
            case .month:
                let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
                return startTime >= monthAgo
            case .year:
                return calendar.component(.year, from: startTime) == selectedYear
            case .range:
                return startTime >= customStartDate && startTime <= customEndDate
            }
        }
    }
    
    private var migrainesWithWeather: [MigraineEvent] {
        filteredMigraines.filter { $0.hasWeatherData }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header with stats
                    weatherDataAvailability
                    
                    if !migrainesWithWeather.isEmpty {
                        // Pressure change correlation
                        pressureChangeChart
                        
                        // Weather condition distribution
                        weatherConditionChart
                        
                        // Temperature correlation
                        temperatureChart
                        
                        // Precipitation correlation
                        precipitationChart
                        
                        // Correlation insights
                        correlationInsights
                    } else {
                        noWeatherDataView
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Weather Correlation")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Weather Data Availability
    
    private var weatherDataAvailability: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                
                Text("Weather Data Coverage")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
            }
            
            HStack(spacing: 12) {
                StatBox(
                    title: "Total Migraines",
                    value: "\(filteredMigraines.count)"
                )
                
                StatBox(
                    title: "With Weather",
                    value: "\(migrainesWithWeather.count)"
                )
                
                StatBox(
                    title: "Coverage",
                    value: coveragePercentage
                )
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
    }
    
    private var coveragePercentage: String {
        guard !filteredMigraines.isEmpty else { return "0%" }
        let percentage = (Double(migrainesWithWeather.count) / Double(filteredMigraines.count)) * 100
        return String(format: "%.0f%%", percentage)
    }
    
    // MARK: - Pressure Change Chart
    
    private var pressureChangeChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Barometric Pressure Changes", systemImage: "gauge.high")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .padding(.horizontal)
                
                Text("24-hour pressure change before migraine onset")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                let pressureData = migrainesWithWeather.map { migraine in
                    PressurePoint(
                        id: migraine.id ?? UUID(),
                        date: migraine.startTime ?? Date(),
                        change: migraine.weatherPressureChange24h,
                        painLevel: Int(migraine.painLevel)
                    )
                }
                .sorted { $0.date < $1.date }
                
                if pressureData.isEmpty {
                    Text("No pressure data available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(pressureData) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Pressure Change (hPa)", point.change)
                        )
                        .foregroundStyle(pressureChangeGradient(point.change))
                        .cornerRadius(6)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            AxisValueLabel()
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            AxisValueLabel(format: .dateTime.month().day())
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(12)
                    }
                    .frame(height: 260)
                    
                    // Pressure change legend
                    HStack(spacing: 20) {
                        LegendItem(color: .green, text: "Stable (< 2 hPa)")
                        LegendItem(color: .orange, text: "Moderate (2-5 hPa)")
                        LegendItem(color: .red, text: "Significant (> 5 hPa)")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private func pressureChangeGradient(_ change: Double) -> Color {
        let absChange = abs(change)
        if absChange < 2 {
            return .green
        } else if absChange < 5 {
            return .orange
        } else {
            return .red
        }
    }
    
    // MARK: - Weather Condition Chart
    
    private var weatherConditionChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Weather Conditions", systemImage: "cloud.sun.rain.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
                    .padding(.horizontal)
                
                let conditionData = Dictionary(grouping: migrainesWithWeather) { $0.weatherCondition ?? "Unknown" }
                    .map { WeatherConditionPoint(condition: $0.key, count: $0.value.count) }
                    .sorted { $0.count > $1.count }
                
                if conditionData.isEmpty {
                    Text("No weather condition data available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(conditionData) { point in
                        SectorMark(
                            angle: .value("Count", point.count),
                            innerRadius: .ratio(0.618),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Condition", point.condition))
                        .cornerRadius(4)
                    }
                    .frame(height: 260)
                    .chartLegend(position: .bottom, alignment: .center, spacing: 12)
                }
            }
        }
    }
    
    // MARK: - Temperature Chart
    
    private var temperatureChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Temperature During Migraines", systemImage: "thermometer.medium")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                
                let tempData = migrainesWithWeather.map { migraine in
                    TemperaturePoint(
                        id: migraine.id ?? UUID(),
                        temperature: migraine.weatherTemperature,
                        count: 1
                    )
                }
                
                // Group by temperature ranges
                let tempRanges = Dictionary(grouping: tempData) { point -> String in
                    let temp = Int(point.temperature)
                    switch temp {
                    case ..<32: return "< 32°F"
                    case 32..<50: return "32-49°F"
                    case 50..<70: return "50-69°F"
                    case 70..<85: return "70-84°F"
                    default: return "≥ 85°F"
                    }
                }
                .map { TempRangePoint(range: $0.key, count: $0.value.count) }
                .sorted { $0.range < $1.range }
                
                if tempRanges.isEmpty {
                    Text("No temperature data available")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(tempRanges) { point in
                        BarMark(
                            x: .value("Temperature Range", point.range),
                            y: .value("Count", point.count)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(8)
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            AxisValueLabel()
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            AxisValueLabel()
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(12)
                    }
                    .frame(height: 220)
                }
            }
        }
    }
    
    // MARK: - Precipitation Chart
    
    private var precipitationChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Precipitation Correlation", systemImage: "cloud.rain.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .padding(.horizontal)
                
                let withPrecip = migrainesWithWeather.filter { $0.weatherPrecipitation > 0 }.count
                let withoutPrecip = migrainesWithWeather.count - withPrecip
                
                let precipData = [
                    PrecipitationPoint(category: "With Rain", count: withPrecip),
                    PrecipitationPoint(category: "No Rain", count: withoutPrecip)
                ]
                
                Chart(precipData) { point in
                    BarMark(
                        x: .value("Category", point.category),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(
                        point.category == "With Rain" ?
                        LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .bottom, endPoint: .top) :
                        LinearGradient(colors: [Color.gray, Color(.systemGray3)], startPoint: .bottom, endPoint: .top)
                    )
                    .cornerRadius(8)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .frame(height: 180)
            }
        }
    }
    
    // MARK: - Correlation Insights
    
    private var correlationInsights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Insights")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Pressure correlation
                if let pressureInsight = calculatePressureCorrelation() {
                    InsightCard(
                        icon: "gauge.high",
                        color: pressureInsight.severity,
                        title: "Pressure Sensitivity",
                        description: pressureInsight.message
                    )
                }
                
                // Most common weather
                if let commonWeather = mostCommonWeatherCondition() {
                    InsightCard(
                        icon: commonWeather.icon,
                        color: .blue,
                        title: "Most Common Weather",
                        description: "\(commonWeather.condition) was present during \(commonWeather.percentage)% of your migraines"
                    )
                }
                
                // Temperature insight
                if let tempInsight = calculateTemperatureInsight() {
                    InsightCard(
                        icon: "thermometer.medium",
                        color: .orange,
                        title: "Temperature Pattern",
                        description: tempInsight
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    private func calculatePressureCorrelation() -> (message: String, severity: Color)? {
        guard !migrainesWithWeather.isEmpty else { return nil }
        
        let significantChanges = migrainesWithWeather.filter { abs($0.weatherPressureChange24h) >= 5 }.count
        let percentage = (Double(significantChanges) / Double(migrainesWithWeather.count)) * 100
        
        if percentage >= 50 {
            return ("High correlation: \(Int(percentage))% of your migraines occurred with significant pressure changes (≥5 hPa)", .red)
        } else if percentage >= 30 {
            return ("Moderate correlation: \(Int(percentage))% of your migraines occurred with significant pressure changes", .orange)
        } else {
            return ("Low correlation: Only \(Int(percentage))% of your migraines occurred with significant pressure changes", .green)
        }
    }
    
    private func mostCommonWeatherCondition() -> (condition: String, percentage: Int, icon: String)? {
        guard !migrainesWithWeather.isEmpty else { return nil }
        
        let conditions = Dictionary(grouping: migrainesWithWeather) { $0.weatherCondition ?? "Unknown" }
        guard let mostCommon = conditions.max(by: { $0.value.count < $1.value.count }) else { return nil }
        
        let percentage = (Double(mostCommon.value.count) / Double(migrainesWithWeather.count)) * 100
        let icon = mostCommon.value.first?.weatherIcon ?? "cloud.fill"
        
        return (mostCommon.key, Int(percentage), icon)
    }
    
    private func calculateTemperatureInsight() -> String? {
        guard !migrainesWithWeather.isEmpty else { return nil }
        
        let avgTemp = migrainesWithWeather.reduce(0.0) { $0 + $1.weatherTemperature } / Double(migrainesWithWeather.count)
        
        return "Average temperature during migraines: \(Int(avgTemp))°F"
    }
    
    // MARK: - No Data View
    
    private var noWeatherDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Weather Data Available")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Weather data will be automatically collected for new migraine entries. Make sure location services are enabled.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                Task {
                    await LocationManager.shared.requestPermission()
                }
            }) {
                Label("Enable Location Services", systemImage: "location.fill")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

// MARK: - Data Models

struct PressurePoint: Identifiable {
    let id: UUID
    let date: Date
    let change: Double
    let painLevel: Int
}

struct WeatherConditionPoint: Identifiable {
    let id = UUID()
    let condition: String
    let count: Int
}

struct TemperaturePoint: Identifiable {
    let id: UUID
    let temperature: Double
    let count: Int
}

struct TempRangePoint: Identifiable {
    let id = UUID()
    let range: String
    let count: Int
}

struct PrecipitationPoint: Identifiable {
    let id = UUID()
    let category: String
    let count: Int
}

// MARK: - Helper Views

struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
        }
    }
}

struct InsightCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}


