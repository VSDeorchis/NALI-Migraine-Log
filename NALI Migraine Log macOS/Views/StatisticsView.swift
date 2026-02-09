import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var selectedTimeFrame: TimeFrame = .month
    @State private var selectedYear: Int
    // Custom range dates
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate: Date = Date()
    
    init(viewModel: MigraineViewModel) {
        self.viewModel = viewModel
        _selectedYear = State(initialValue: Calendar.current.component(.year, from: Date()))
    }
    
    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case range = "Range"
    }
    
    var body: some View {
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
                
                // Year picker (only show for year view)
                if selectedTimeFrame == .year {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                } else if selectedTimeFrame == .range {
                    VStack {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End", selection: $customEndDate, in: customStartDate...Date(), displayedComponents: .date)
                    }
                }
                
                // Statistics Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    StatBox(title: "Total Migraines", value: "\(filteredMigraines.count)")
                    StatBox(title: "Average Pain", value: String(format: "%.1f", averagePain))
                    StatBox(title: "Average Duration", value: formatDuration(averageDuration))
                    StatBox(title: "Abortive Meds Used", value: "\(abortiveMedsCount)")
                }
                .padding()
                
                // Charts
                Group {
                    // Frequency Chart
                    ChartSection(title: "Monthly Frequency") {
                        Chart(frequencyData, id: \.month) { item in
                            BarMark(
                                x: .value("Month", item.month),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(by: .value("Count", item.count))
                        }
                    }
                    
                    // Pain Level Distribution
                    ChartSection(title: "Pain Level Distribution") {
                        Chart(painLevelData, id: \.level) { item in
                            BarMark(
                                x: .value("Level", item.level),
                                y: .value("Count", item.count)
                            )
                        }
                    }
                    
                    // Common Triggers
                    ChartSection(title: "Common Triggers") {
                        Chart(triggerData.prefix(5), id: \.trigger) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Trigger", item.trigger)
                            )
                        }
                    }
                    
                    // Medication Usage
                    ChartSection(title: "Medication Usage") {
                        Chart(medicationData, id: \.medication) { item in
                            SectorMark(
                                angle: .value("Count", item.count),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("Medication", item.medication))
                        }
                    }
                }
                .frame(height: 300)
                .padding()
            }
        }
        .navigationTitle("Statistics")
    }
    
    // Add computed properties for data processing
    private var filteredMigraines: [MigraineEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch selectedTimeFrame {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
            return viewModel.migraines.filter { migraine in
                guard let startTime = migraine.startTime else { return false }
                return startTime >= startDate
            }
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)!
            return viewModel.migraines.filter { migraine in
                guard let startTime = migraine.startTime else { return false }
                return startTime >= startDate
            }
        case .year:
            return viewModel.migraines.filter { migraine in
                guard let startTime = migraine.startTime else { return false }
                return calendar.component(.year, from: startTime) == selectedYear
            }
        case .range:
            return viewModel.migraines.filter { migraine in
                guard let startTime = migraine.startTime else { return false }
                return startTime >= customStartDate && startTime <= customEndDate
            }
        }
        
        return []
    }
    
    private var averagePain: Double {
        guard !filteredMigraines.isEmpty else { return 0 }
        let total = filteredMigraines.reduce(0) { $0 + Int($1.painLevel) }
        return Double(total) / Double(filteredMigraines.count)
    }
    
    private var averageDuration: TimeInterval? {
        let completedMigraines = filteredMigraines.filter { $0.endTime != nil }
        guard !completedMigraines.isEmpty else { return nil }
        
        let totalDuration = completedMigraines.reduce(0.0) { total, migraine in
            guard let endTime = migraine.endTime,
                  let startTime = migraine.startTime else { return total }
            return total + endTime.timeIntervalSince(startTime)
        }
        return totalDuration / Double(completedMigraines.count)
    }
    
    private var abortiveMedsCount: Int {
        return filteredMigraines.reduce(0) { count, migraine in
            var abortiveCount = 0
            if migraine.tookSumatriptan { abortiveCount += 1 }
            if migraine.tookRizatriptan { abortiveCount += 1 }
            if migraine.tookFrovatriptan { abortiveCount += 1 }
            if migraine.tookNaratriptan { abortiveCount += 1 }
            if migraine.tookEletriptan { abortiveCount += 1 }
            if migraine.tookUbrelvy { abortiveCount += 1 }
            if migraine.tookNurtec { abortiveCount += 1 }
            if migraine.tookReyvow { abortiveCount += 1 }
            if migraine.tookTrudhesa { abortiveCount += 1 }
            return count + abortiveCount
        }
    }
    
    // Chart Data Models
    private struct FrequencyPoint {
        let month: String
        let count: Int
    }
    
    private struct PainLevelPoint {
        let level: Int
        let count: Int
    }
    
    private struct TriggerPoint {
        let trigger: String
        let count: Int
    }
    
    private struct MedicationPoint {
        let medication: String
        let count: Int
    }
    
    // Chart Data
    private var frequencyData: [FrequencyPoint] {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        
        var monthCounts: [String: Int] = [:]
        
        // Initialize all months with 0
        for month in 1...12 {
            if let date = calendar.date(from: DateComponents(year: selectedYear, month: month)) {
                monthCounts[monthFormatter.string(from: date)] = 0
            }
        }
        
        // Count migraines
        for migraine in filteredMigraines {
            guard let startTime = migraine.startTime else { continue }
            let monthStr = monthFormatter.string(from: startTime)
            monthCounts[monthStr, default: 0] += 1
        }
        
        return monthCounts.map { FrequencyPoint(month: $0.key, count: $0.value) }
            .sorted { month1, month2 in
                let date1 = monthFormatter.date(from: month1.month) ?? Date()
                let date2 = monthFormatter.date(from: month2.month) ?? Date()
                return date1 < date2
            }
    }
    
    private var painLevelData: [PainLevelPoint] {
        var counts: [Int: Int] = [:]
        for migraine in filteredMigraines {
            counts[Int(migraine.painLevel), default: 0] += 1
        }
        return (1...10).map { PainLevelPoint(level: $0, count: counts[$0] ?? 0) }
    }
    
    private var triggerData: [TriggerPoint] {
        var counts: [String: Int] = [:]
        for migraine in filteredMigraines {
            for name in migraine.selectedTriggerNames {
                counts[name, default: 0] += 1
            }
        }
        return counts.map { TriggerPoint(trigger: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private var medicationData: [MedicationPoint] {
        var counts: [String: Int] = [:]
        for migraine in filteredMigraines {
            for name in migraine.selectedMedicationNames {
                counts[name, default: 0] += 1
            }
        }
        return counts.map { MedicationPoint(medication: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration = duration else { return "N/A" }
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
    
    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let oldestYear = viewModel.migraines
            .map { calendar.component(.year, from: $0.startTime!) }
            .min() ?? currentYear
        return Array(oldestYear...currentYear).reversed()
    }
}

struct ChartSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            content
                .padding(.vertical)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
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
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }
} 
