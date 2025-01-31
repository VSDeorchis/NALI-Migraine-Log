import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var migraineStore: MigraineStore
    @State private var selectedTimeFrame: TimeFrame = .month
    @State private var selectedYear: Int
    
    init(migraineStore: MigraineStore) {
        self.migraineStore = migraineStore
        // Initialize with current year
        _selectedYear = State(initialValue: Calendar.current.component(.year, from: Date()))
    }
    
    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }
    
    // Add available years for picker
    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let oldestYear = migraineStore.migraines.map { calendar.component(.year, from: $0.startTime) }.min() ?? currentYear
        return Array(oldestYear...currentYear).reversed()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Time frame picker
                    Picker("Time Frame", selection: $selectedTimeFrame) {
                        ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                            Text(timeFrame.rawValue).tag(timeFrame)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Year picker for frequency chart
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    // Frequency Chart
                    ChartSection(title: "Monthly Migraine Frequency") {
                        Chart(frequencyData) { item in  // Show all months
                            BarMark(
                                x: .value("Month", item.month),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(item.color)
                            .annotation(position: .top) {
                                if item.count > 0 {  // Only show count annotation if there's data
                                    Text("\(item.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                    }
                    
                    // Pain Level Distribution
                    ChartSection(title: "Pain Level Distribution") {
                        Chart(painLevelData) { item in
                            BarMark(
                                x: .value("Pain Level", "\(item.level)"),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(painLevelColor(item.level).gradient)
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                if let level = value.as(String.self) {
                                    AxisValueLabel {
                                        Text(level)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .chartXAxisLabel("Pain Level")
                    }
                    
                    // Trigger Distribution
                    ChartSection(title: "Common Triggers") {
                        Chart(triggerData.prefix(5)) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Trigger", item.trigger)
                            )
                        }
                        .chartXAxis(.automatic)
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                    }
                    
                    // Medication Usage
                    ChartSection(title: "Medication Usage") {
                        Chart(medicationData) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("Medication", item.medication))
                        }
                    }
                    
                    // Time of Day Distribution
                    ChartSection(title: "Time of Day Distribution") {
                        Chart(timeOfDayData) { item in
                            BarMark(
                                x: .value("Time of Day", item.timeOfDay),
                                y: .value("Count", item.count)
                            )
                            .annotation(position: .top) {
                                Text("\(calculatePercentage(count: item.count, total: filteredMigraines.count))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Quality of Life Impact
                    ChartSection(title: "Quality of Life Impact") {
                        Chart(qualityOfLifeData.filter { $0.count > 0 }) { item in  // Only show items with counts > 0
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Impact", item.type)
                            )
                            .foregroundStyle(Color(.systemRed).opacity(0.7))
                            .annotation(position: .trailing) {
                                Text("\(item.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)  // Hide the x-axis since we show values in annotations
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                    }
                    
                    // Text Statistics
                    statisticsGrid
                }
            }
            .navigationTitle("Statistics")
        }
    }
    
    private var statisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            StatBox(title: totalTitle, value: "\(filteredMigraines.count)")
            StatBox(title: periodTitle, value: currentPeriodCount)
            StatBox(title: "Avg Duration", value: formatDuration(averageDuration))
            StatBox(title: averageTitle, value: String(format: "%.1f", averagePerPeriod))
        }
        .padding()
    }
    
    // Add these computed properties
    private var totalTitle: String {
        switch selectedTimeFrame {
        case .week: return "Week Total"
        case .month: return "Month Total"
        case .year: return "Year Total"
        }
    }
    
    private var periodTitle: String {
        switch selectedTimeFrame {
        case .week: return "Today"
        case .month: return "This Week"
        case .year: return "This Month"
        }
    }
    
    private var averageTitle: String {
        switch selectedTimeFrame {
        case .week: return "Weekly Avg"
        case .month: return "Monthly Avg"
        case .year: return "Yearly Avg"
        }
    }
    
    private var currentPeriodCount: String {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeFrame {
        case .week:
            let today = calendar.startOfDay(for: now)
            return "\(filteredMigraines.filter { calendar.isDate($0.startTime, inSameDayAs: today) }.count)"
        case .month:
            let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
            return "\(filteredMigraines.filter { $0.startTime >= weekStart }.count)"
        case .year:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return "\(filteredMigraines.filter { $0.startTime >= monthStart }.count)"
        }
    }
    
    private var averagePerPeriod: Double {
        let count = Double(filteredMigraines.count)
        
        switch selectedTimeFrame {
        case .week:
            return count
        case .month:
            return count
        case .year:
            return count
        }
    }
    
    private var averageDuration: TimeInterval? {
        let completedMigraines = filteredMigraines.filter { $0.endTime != nil }
        guard !completedMigraines.isEmpty else { return nil }
        
        let totalDuration = completedMigraines.reduce(0.0) { total, migraine in
            total + (migraine.endTime?.timeIntervalSince(migraine.startTime) ?? 0)
        }
        return totalDuration / Double(completedMigraines.count)
    }
    
    // Data Computation
    private var frequencyData: [FrequencyPoint] {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        
        var monthCounts: [String: Int] = [:]
        
        // Initialize all months with 0
        for month in 1...12 {
            if let date = calendar.date(from: DateComponents(year: selectedYear, month: month)) {
                let monthStr = monthFormatter.string(from: date)
                monthCounts[monthStr] = 0
            }
        }
        
        // Count migraines for selected year only
        for migraine in migraineStore.migraines {
            let year = calendar.component(.year, from: migraine.startTime)
            if year == selectedYear {
                let monthStr = monthFormatter.string(from: migraine.startTime)
                monthCounts[monthStr, default: 0] += 1
            }
        }
        
        // Convert to array and sort by month
        return monthCounts
            .map { FrequencyPoint(month: $0.key, count: $0.value) }
            .sorted { month1, month2 in
                let date1 = monthFormatter.date(from: month1.month) ?? Date()
                let date2 = monthFormatter.date(from: month2.month) ?? Date()
                return date1 < date2
            }
    }
    
    private var filteredMigraines: [MigraineEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch selectedTimeFrame {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)!
        }
        
        return migraineStore.migraines.filter { $0.startTime >= startDate }
    }
    
    private var painLevelData: [PainLevelPoint] {
        let counts = filteredMigraines.reduce(into: [Int: Int]()) { counts, migraine in
            counts[migraine.painLevel, default: 0] += 1
        }
        return (1...10).map { PainLevelPoint(level: $0, count: counts[$0] ?? 0) }
    }
    
    private var triggerData: [TriggerPoint] {
        filteredMigraines
            .flatMap { $0.triggers }
            .reduce(into: [:]) { counts, trigger in
                counts[trigger.rawValue, default: 0] += 1
            }
            .map { TriggerPoint(trigger: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private var medicationData: [MedicationPoint] {
        filteredMigraines
            .flatMap { $0.medications }
            .reduce(into: [:]) { counts, medication in
                counts[medication.rawValue, default: 0] += 1
            }
            .map { MedicationPoint(medication: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private var timeOfDayData: [TimeOfDayPoint] {
        var counts: [String: Int] = [
            "Morning": 0,     // Removed (6AM-12PM)
            "Afternoon": 0,   // Removed (12PM-6PM)
            "Evening": 0,     // Removed (6PM-12AM)
            "Night": 0        // Removed (12AM-6AM)
        ]
        
        for migraine in filteredMigraines {
            let hour = Calendar.current.component(.hour, from: migraine.startTime)
            switch hour {
            case 6..<12:
                counts["Morning"]! += 1
            case 12..<18:
                counts["Afternoon"]! += 1
            case 18..<24:
                counts["Evening"]! += 1
            default:
                counts["Night"]! += 1
            }
        }
        
        return counts.map { TimeOfDayPoint(timeOfDay: $0.key, count: $0.value) }
            .sorted { $0.timeOfDay < $1.timeOfDay }
    }
    
    private var qualityOfLifeData: [QualityOfLifePoint] {
        let impacts = [
            ("Missed Work", filteredMigraines.filter { $0.missedWork }.count),
            ("Missed School", filteredMigraines.filter { $0.missedSchool }.count),
            ("Missed Events", filteredMigraines.filter { $0.missedEvents }.count)
        ]
        
        return impacts.map { QualityOfLifePoint(type: $0.0, count: $0.1) }
            .sorted { $0.count > $1.count }  // Sort by count descending
    }
    
    // Helper Functions
    private func formatDate(_ date: Date) -> String {
        switch selectedTimeFrame {
        case .week:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .month:
            return date.formatted(.dateTime.day())
        case .year:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration = duration else { return "N/A" }
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
    
    private func calculatePercentage(count: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(round(Double(count) / Double(filteredMigraines.count) * 100))
    }
    
    private var totalMedications: Int {
        medicationData.reduce(0) { $0 + $1.count }
    }
}

// Supporting Views
struct ChartSection<Content: View>: View {
    let title: String
    let content: () -> Content
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            content()
                .frame(height: 200)
                .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
        .padding(.horizontal)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}

// Data Models
struct FrequencyPoint: Identifiable {
    let id = UUID()
    let month: String
    let count: Int
    let color: Color
    
    init(month: String, count: Int) {
        self.month = month
        self.count = count
        self.color = Self.getColor(for: count)
    }
    
    private static func getColor(for count: Int) -> Color {
        switch count {
        case 0...4: return .green
        case 5...8: return .yellow
        default: return .red
        }
    }
}

struct PainLevelPoint: Identifiable {
    let id = UUID()
    let level: Int
    let count: Int
}

struct TriggerPoint: Identifiable {
    let id = UUID()
    let trigger: String
    let count: Int
}

struct MedicationPoint: Identifiable {
    let id = UUID()
    let medication: String
    let count: Int
}

struct TimeOfDayPoint: Identifiable {
    let id = UUID()
    let timeOfDay: String
    let count: Int
}

struct QualityOfLifePoint: Identifiable {
    let id = UUID()
    let type: String
    let count: Int
}

#Preview {
    StatisticsView(migraineStore: MigraineStore())
} 