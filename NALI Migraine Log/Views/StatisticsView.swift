import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var timeFilter: TimeFilter = .month
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Date?
    @State private var showingMonthDetail = false
    @State private var lastUpdateTime: Date = Date()
    @State private var selectedMedication: String?
    @State private var selectedTrigger: String?
    @State private var selectedTimeOfDay: String?
    @State private var selectedImpactType: String?
    @State private var selectedPainLevel: Int?
    @State private var lastTimeFilter: TimeFilter?
    @State private var cachedFilteredMigraines: [MigraineEvent]?
    @State private var cachedChartData: [String: Any] = [:]
    @State private var isNavigating = false
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate: Date = Date()
    
    enum TimeFilter: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case range = "Range"
    }
    
    @ViewBuilder
    private func medicationNavigationView() -> some View {
        if let medication = selectedMedication {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines with \(medication)",
                migraines: filteredMigraines.filter { migraine in
                    switch medication {
                    case "Ibuprofen": return migraine.tookIbuprofin
                    case "Excedrin": return migraine.tookExcedrin
                    case "Tylenol": return migraine.tookTylenol
                    case "Sumatriptan": return migraine.tookSumatriptan
                    case "Rizatriptan": return migraine.tookRizatriptan
                    case "Naproxen": return migraine.tookNaproxen
                    case "Frovatriptan": return migraine.tookFrovatriptan
                    case "Naratriptan": return migraine.tookNaratriptan
                    case "Nurtec": return migraine.tookNurtec
                    case "Ubrelvy": return migraine.tookUbrelvy
                    case "Reyvow": return migraine.tookReyvow
                    case "Trudhesa": return migraine.tookTrudhesa
                    case "Elyxyb": return migraine.tookElyxyb
                    case "Other": return migraine.tookOther
                    default: return false
                    }
                }
            )
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func triggerNavigationView() -> some View {
        if let trigger = selectedTrigger {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines with \(trigger)",
                migraines: filteredMigraines.filter { migraine in
                    switch trigger {
                    case "Stress": return migraine.isTriggerStress
                    case "Lack of Sleep": return migraine.isTriggerLackOfSleep
                    case "Dehydration": return migraine.isTriggerDehydration
                    case "Weather": return migraine.isTriggerWeather
                    case "Hormones": return migraine.isTriggerHormones
                    case "Alcohol": return migraine.isTriggerAlcohol
                    case "Caffeine": return migraine.isTriggerCaffeine
                    case "Food": return migraine.isTriggerFood
                    case "Exercise": return migraine.isTriggerExercise
                    case "Screen Time": return migraine.isTriggerScreenTime
                    case "Other": return migraine.isTriggerOther
                    default: return false
                    }
                }
            )
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func timeOfDayNavigationView() -> some View {
        if let timeSlot = selectedTimeOfDay {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Migraines in \(timeSlot)",
                migraines: filteredMigraines.filter { migraine in
                    guard let date = migraine.startTime else { return false }
                    let hour = Calendar.current.component(.hour, from: date)
                    switch timeSlot {
                    case "Morning": return (5..<12).contains(hour)
                    case "Afternoon": return (12..<17).contains(hour)
                    case "Evening": return (17..<22).contains(hour)
                    case "Night": return hour < 5 || hour >= 22
                    default: return false
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func impactNavigationView() -> some View {
        if let impactType = selectedImpactType {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: impactType,
                migraines: filteredMigraines.filter { migraine in
                    switch impactType {
                    case "Missed Work": return migraine.missedWork
                    case "Missed School": return migraine.missedSchool
                    case "Missed Events": return migraine.missedEvents
                    default: return false
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func painLevelNavigationView() -> some View {
        if let level = selectedPainLevel {
            FilteredMigraineListView(
                viewModel: viewModel,
                title: "Pain Level \(level)",
                migraines: filteredMigraines.filter { migraine in
                    migraine.painLevel == level
                }
            )
        }
    }
    
    private var timeFilterView: some View {
        VStack {
            Picker("Time Filter", selection: $timeFilter) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            if timeFilter == .year {
                Picker("Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            } else if timeFilter == .range {
                VStack {
                    DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker("End", selection: $customEndDate, in: customStartDate...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
        }
    }
    
    private var summaryStatsView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            StatBox(title: "\(timeFilter.rawValue) Total", value: String(totalMigraines))
            StatBox(
                title: "This vs Last \(timeFilter.rawValue)",
                value: "\(currentPeriodMigraines) vs \(previousPeriodMigraines)"
            )
            StatBox(title: "Avg Duration", value: formatDuration(averageDuration))
            StatBox(title: "\(timeFilter.rawValue)ly Average", value: String(format: "%.1f", averageFrequency))
            StatBox(title: "Avg Pain", value: String(format: "%.1f", averagePain))
            StatBox(title: "Abortives Used", value: String(abortivesUsed))
        }
        .padding(.horizontal)
    }
    
    private var chartsView: some View {
        LazyVStack(spacing: 20) {
            monthlyDistributionChart
            painLevelDistributionChart
            commonTriggersChart
            medicationUsageChart
            timeOfDayDistributionChart
            qualityOfLifeImpactChart
            weatherCorrelationButton
        }
    }
    
    private var weatherCorrelationButton: some View {
        NavigationLink(destination: WeatherCorrelationView(
            viewModel: viewModel,
            timeFilter: timeFilter,
            selectedYear: selectedYear,
            customStartDate: customStartDate,
            customEndDate: customEndDate
        )) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weather Correlation")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Analyze how weather patterns correlate with your migraines")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
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
            .shadow(color: Color.blue.opacity(0.1), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Add missing computed property for monthly data
    private var monthlyData: [MonthlyPoint] {
        let calendar = Calendar.current
        let now = Date()
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
        
        var counts: [Date: Int] = [:]
        let months = calendar.generateDates(
            inside: DateInterval(start: sixMonthsAgo, end: now),
            matching: DateComponents(day: 1)
        )
        
        // Initialize all months with zero
        for month in months {
            counts[month] = 0
        }
        
        // Count migraines per month
        for migraine in filteredMigraines {
            guard let date = migraine.startTime else { continue }
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
            counts[monthStart, default: 0] += 1
        }
        
        return counts.map { MonthlyPoint(month: $0.key, count: $0.value) }
            .sorted { $0.month < $1.month }
    }
    
    // Add helper function for monthly bar color
    private func monthlyBarColor(count: Int) -> Color {
        switch count {
        case 0...4: return .green
        case 5...8: return .yellow
        default: return .red
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    timeFilterView
                        .padding(.horizontal)
                        .padding(.top)
                        .background(Color(.systemGroupedBackground))
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            if filteredMigraines.isEmpty {
                                Text("No data for selected period")
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                summaryStatsView
                                    .padding(.top)
                                chartsView
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Statistics")
            .navigationDestination(isPresented: $showingMonthDetail) {
                if let month = selectedMonth {
                    MonthDetailView(viewModel: viewModel, month: month)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedMedication != nil },
                set: { if !$0 { selectedMedication = nil } }
            )) {
                medicationNavigationView()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTrigger != nil },
                set: { if !$0 { 
                    selectedTrigger = nil
                    isNavigating = false 
                }}
            )) {
                triggerNavigationView()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTimeOfDay != nil },
                set: { if !$0 { selectedTimeOfDay = nil } }
            )) {
                timeOfDayNavigationView()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedImpactType != nil },
                set: { if !$0 { selectedImpactType = nil } }
            )) {
                impactNavigationView()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedPainLevel != nil },
                set: { if !$0 { selectedPainLevel = nil } }
            )) {
                painLevelNavigationView()
            }
            .onAppear {
                // Refresh data when view appears
                viewModel.fetchMigraines()
                lastUpdateTime = Date()
            }
            .onChange(of: viewModel.migraines) { _ in
                // Refresh when migraines data changes
                lastUpdateTime = Date()
                cachedFilteredMigraines = nil
                cachedChartData = [:]
            }
            .onChange(of: timeFilter) { _ in
                // Clear caches when time filter changes
                cachedFilteredMigraines = nil
                cachedChartData = [:]
            }
            .onChange(of: customStartDate) { _ in
                cachedFilteredMigraines = nil
                cachedChartData = [:]
            }
            .onChange(of: customEndDate) { _ in
                cachedFilteredMigraines = nil
                cachedChartData = [:]
            }
        }
    }
    
    // Computed properties for statistics
    private var availableYears: [Int] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let earliestYear = viewModel.migraines.compactMap { migraine in
            guard let date = migraine.startTime else { return nil }
            return calendar.component(.year, from: date)
        }.min() ?? currentYear
        
        return Array(earliestYear...currentYear)
    }
    
    // Filtered migraines based on time filter
    private var filteredMigraines: [MigraineEvent] {
        // Cache this value when timeFilter changes instead of recomputing
        if lastTimeFilter == timeFilter && cachedFilteredMigraines != nil {
            return cachedFilteredMigraines!
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        let filtered = viewModel.migraines.filter { migraine in
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
        
        cachedFilteredMigraines = filtered
        lastTimeFilter = timeFilter
        return filtered
    }
    
    private var totalMigraines: Int {
        filteredMigraines.count
    }
    
    private var currentPeriodMigraines: Int {
        let calendar = Calendar.current
        let now = Date()
        
        return filteredMigraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            
            switch timeFilter {
            case .week:
                return calendar.isDate(startTime, equalTo: now, toGranularity: .weekOfYear)
            case .month:
                return calendar.isDate(startTime, equalTo: now, toGranularity: .month)
            case .year:
                return calendar.isDate(startTime, equalTo: now, toGranularity: .year)
            case .range:
                return startTime >= customStartDate && startTime <= customEndDate
            }
        }.count
    }
    
    private var previousPeriodMigraines: Int {
        let calendar = Calendar.current
        let now = Date()
        
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            
            switch timeFilter {
            case .week:
                let lastWeekStart = calendar.date(byAdding: .day, value: -14, to: now)!
                let lastWeekEnd = calendar.date(byAdding: .day, value: -7, to: now)!
                return startTime >= lastWeekStart && startTime < lastWeekEnd
            case .month:
                let lastMonthStart = calendar.date(byAdding: .month, value: -2, to: now)!
                let lastMonthEnd = calendar.date(byAdding: .month, value: -1, to: now)!
                return startTime >= lastMonthStart && startTime < lastMonthEnd
            case .year:
                let lastYearStart = calendar.date(byAdding: .year, value: -2, to: now)!
                let lastYearEnd = calendar.date(byAdding: .year, value: -1, to: now)!
                return startTime >= lastYearStart && startTime < lastYearEnd
            case .range:
                let interval = customEndDate.timeIntervalSince(customStartDate)
                let prevStart = customStartDate.addingTimeInterval(-interval)
                let prevEnd = customStartDate
                return startTime >= prevStart && startTime < prevEnd
            }
        }.count
    }
    
    private var averageDuration: TimeInterval? {
        // Only include completed migraine events (those with an explicit endTime)
        let completedDurations = filteredMigraines.compactMap { migraine -> TimeInterval? in
            // Ensure the migraine has both a start and end time
            guard let start = migraine.startTime,
                  let end = migraine.endTime else { return nil }
            return end.timeIntervalSince(start)
        }
        guard !completedDurations.isEmpty else { return nil }
        return completedDurations.reduce(0, +) / Double(completedDurations.count)
    }
    
    private var averageFrequency: Double {
        switch timeFilter {
        case .week:
            return Double(totalMigraines) / 7.0
        case .month:
            return Double(totalMigraines) / 30.0
        case .year:
            return Double(totalMigraines) / 12.0  // monthly average for the year
        case .range:
            let days = max(Calendar.current.dateComponents([.day], from: customStartDate, to: customEndDate).day ?? 1, 1)
            return Double(totalMigraines) / Double(days)
        }
    }
    
    private var averagePain: Double {
        guard !filteredMigraines.isEmpty else { return 0 }
        let sum = filteredMigraines.reduce(0.0) { $0 + Double($1.painLevel) }
        return sum / Double(filteredMigraines.count)
    }
    
    private var abortivesUsed: Int {
        filteredMigraines.reduce(0) { total, migraine in
            var count = 0
            if migraine.tookIbuprofin { count += 1 }
            if migraine.tookExcedrin { count += 1 }
            if migraine.tookTylenol { count += 1 }
            if migraine.tookSumatriptan { count += 1 }
            if migraine.tookRizatriptan { count += 1 }
            if migraine.tookNaproxen { count += 1 }
            if migraine.tookFrovatriptan { count += 1 }
            if migraine.tookNaratriptan { count += 1 }
            if migraine.tookNurtec { count += 1 }
            if migraine.tookUbrelvy { count += 1 }
            if migraine.tookReyvow { count += 1 }
            if migraine.tookTrudhesa { count += 1 }
            if migraine.tookElyxyb { count += 1 }
            if migraine.tookOther { count += 1 }
            return total + count
        }
    }
    
    private var painLevelData: [PainLevelPoint] {
        var counts: [Int: Int] = [:]
        for migraine in filteredMigraines {
            counts[Int(migraine.painLevel), default: 0] += 1
        }
        return (1...10).map { PainLevelPoint(level: $0, count: counts[$0] ?? 0) }
    }
    
    private var timeOfDayData: [TimeOfDayPoint] {
        // Use cached data if time filter hasn't changed
        if let cached = cachedChartData["timeOfDay"] as? [TimeOfDayPoint],
           lastTimeFilter == timeFilter {
            return cached
        }
        
        let timeSlots = ["Morning", "Afternoon", "Evening", "Night"]
        var counts: [String: Int] = [:]
        
        // Calculate new data
        for migraine in filteredMigraines {
            guard let date = migraine.startTime else { continue }
            let hour = Calendar.current.component(.hour, from: date)
            let timeSlot: String
            
            switch hour {
            case 5..<12: timeSlot = "Morning"
            case 12..<17: timeSlot = "Afternoon"
            case 17..<22: timeSlot = "Evening"
            default: timeSlot = "Night"
            }
            
            counts[timeSlot, default: 0] += 1
        }
        
        let data = timeSlots.map { TimeOfDayPoint(timeOfDay: $0, count: counts[$0] ?? 0) }
        cachedChartData["timeOfDay"] = data
        return data
    }
    
    private var qualityOfLifeData: [QualityOfLifePoint] {
        let missedWork = filteredMigraines.filter { $0.missedWork }.count
        let missedSchool = filteredMigraines.filter { $0.missedSchool }.count
        let missedEvents = filteredMigraines.filter { $0.missedEvents }.count
        
        return [
            QualityOfLifePoint(type: "Missed Work", count: missedWork),
            QualityOfLifePoint(type: "Missed School", count: missedSchool),
            QualityOfLifePoint(type: "Missed Events", count: missedEvents)
        ]
    }
    
    private var commonTriggersChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Triggers", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .padding(.horizontal)
                
                let triggerData = filteredMigraines.reduce(into: [String: Int]()) { counts, migraine in
                    if migraine.isTriggerStress { counts["Stress", default: 0] += 1 }
                    if migraine.isTriggerLackOfSleep { counts["Lack of Sleep", default: 0] += 1 }
                    if migraine.isTriggerDehydration { counts["Dehydration", default: 0] += 1 }
                    if migraine.isTriggerWeather { counts["Weather", default: 0] += 1 }
                    if migraine.isTriggerHormones { counts["Hormones", default: 0] += 1 }
                    if migraine.isTriggerAlcohol { counts["Alcohol", default: 0] += 1 }
                    if migraine.isTriggerCaffeine { counts["Caffeine", default: 0] += 1 }
                    if migraine.isTriggerFood { counts["Food", default: 0] += 1 }
                    if migraine.isTriggerExercise { counts["Exercise", default: 0] += 1 }
                    if migraine.isTriggerScreenTime { counts["Screen Time", default: 0] += 1 }
                    if migraine.isTriggerOther { counts["Other", default: 0] += 1 }
            }
            .map { TriggerPoint(trigger: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
                .filter { $0.count > 0 }
                
                if triggerData.isEmpty {
                    Text("No trigger data for selected period")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(triggerData.prefix(5)) { point in
                        BarMark(
                            x: .value("Count", point.count),
                            y: .value("Trigger", point.trigger)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(6)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisValueLabel()
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom) { value in
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
                    .onTapGesture { location in
                        guard !isNavigating else { return }
                        if let trigger = triggerData.first?.trigger {
                            isNavigating = true
                            selectedTrigger = trigger
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var medicationUsageChart: some View {
        ChartSection(title: "") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Medications", systemImage: "pill.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
                    .padding(.horizontal)
                
                let medicationData = filteredMigraines.reduce(into: [String: Int]()) { counts, migraine in
                    if migraine.tookIbuprofin { counts["Ibuprofen", default: 0] += 1 }
                    if migraine.tookExcedrin { counts["Excedrin", default: 0] += 1 }
                    if migraine.tookTylenol { counts["Tylenol", default: 0] += 1 }
                    if migraine.tookSumatriptan { counts["Sumatriptan", default: 0] += 1 }
                    if migraine.tookRizatriptan { counts["Rizatriptan", default: 0] += 1 }
                    if migraine.tookNaproxen { counts["Naproxen", default: 0] += 1 }
                    if migraine.tookFrovatriptan { counts["Frovatriptan", default: 0] += 1 }
                    if migraine.tookNaratriptan { counts["Naratriptan", default: 0] += 1 }
                    if migraine.tookNurtec { counts["Nurtec", default: 0] += 1 }
                    if migraine.tookUbrelvy { counts["Ubrelvy", default: 0] += 1 }
                    if migraine.tookReyvow { counts["Reyvow", default: 0] += 1 }
                    if migraine.tookTrudhesa { counts["Trudhesa", default: 0] += 1 }
                    if migraine.tookElyxyb { counts["Elyxyb", default: 0] += 1 }
                    if migraine.tookOther { counts["Other", default: 0] += 1 }
            }
            .map { MedicationPoint(medication: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
                .filter { $0.count > 0 }
                
                if medicationData.isEmpty {
                    Text("No medication data for selected period")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                } else {
                    Chart(medicationData.prefix(5)) { point in
                        SectorMark(
                            angle: .value("Count", point.count),
                            innerRadius: .ratio(0.618),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Medication", point.medication))
                        .cornerRadius(4)
                    }
                    .chartLegend(position: .bottom, alignment: .center, spacing: 12) {
                        HStack(spacing: 16) {
                            ForEach(medicationData.prefix(5)) { point in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.purple.opacity(0.7))
                                        .frame(width: 8, height: 8)
                                    Text(point.medication)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 240)
                    .onTapGesture { location in
                        guard !isNavigating else { return }
                        if let medication = medicationData.first?.medication {
                            isNavigating = true
                            selectedMedication = medication
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var timeOfDayDistributionChart: some View {
        ChartSection(title: "Time of Day Distribution") {
            Chart(timeOfDayData) { point in
                BarMark(
                    x: .value("Time", point.timeOfDay),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.pink],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(8)
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard !isNavigating,
                                  let (timeSlot, count) = proxy.value(at: location, as: (String, Int).self),
                                  count > 0 else { return }
                            isNavigating = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                            selectedTimeOfDay = timeSlot
                        }
                }
            }
            .frame(height: 220)
        }
    }
    
    private var qualityOfLifeImpactChart: some View {
        ChartSection(title: "Quality of Life Impact") {
            let data = qualityOfLifeData.filter { $0.count > 0 }
            
            if data.isEmpty {
                Text("No impact data for selected period")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("Count", point.count),
                        y: .value("Type", point.type)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
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
                        AxisValueLabel()
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard !isNavigating,
                                      let (impactType, count) = proxy.value(at: location, as: (String, Int).self),
                                      count > 0 else { return }
                                isNavigating = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    isNavigating = false
                                }
                                selectedImpactType = impactType
                            }
                    }
                }
                .frame(height: 220)
            }
        }
    }
    
    private func formatDuration(_ interval: TimeInterval?) -> String {
        guard let interval = interval else { return "N/A" }
        
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...7: return .yellow
        case 8...10: return .red
        default: return .gray
        }
    }
    
    private var painLevelDistributionChart: some View {
        ChartSection(title: "Pain Level Distribution") {
            Chart(painLevelData) { point in
                BarMark(
                    x: .value("Pain Level", point.level),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(painLevelColor(point.level).gradient)
                .cornerRadius(8)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard !isNavigating,
                                  let (level, count) = proxy.value(at: location, as: (Int, Int).self),
                                  count > 0 else { return }
                            isNavigating = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isNavigating = false
                            }
                            selectedPainLevel = level
                        }
                }
            }
            .frame(height: 220)
        }
    }
    
    // Add the missing monthlyDistributionChart view
    private var monthlyDistributionChart: some View {
        ChartSection(title: "Monthly Distribution") {
            if monthlyData.isEmpty {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart(monthlyData) { point in
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(monthlyBarColor(count: point.count).gradient)
                    .cornerRadius(8)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
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
                .frame(height: 220)
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// Data Models
struct FrequencyPoint: Identifiable {
    let id = UUID()
    let month: String
    let count: Int
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

struct MonthlyPoint: Identifiable {
    let id = UUID()
    let month: Date
    let count: Int
}

// Supporting Views
struct ChartSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            
            content()
                .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 68/255, green: 130/255, blue: 180/255))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 68/255, green: 130/255, blue: 180/255).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .shadow(color: Color(red: 68/255, green: 130/255, blue: 180/255).opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct MonthDetailView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) private var dismiss
    let month: Date
    
    private var migrainesForMonth: [MigraineEvent] {
        let calendar = Calendar.current
        return viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return calendar.isDate(startTime, equalTo: month, toGranularity: .month)
        }.sorted { ($0.startTime ?? Date()) > ($1.startTime ?? Date()) }
    }
    
    var body: some View {
        List(migrainesForMonth) { migraine in
            NavigationLink {
                MigraineDetailView(
                    migraine: migraine, 
                    viewModel: viewModel,
                    dismiss: { dismiss() }
                )
            } label: {
                MigraineRowView(viewModel: viewModel, migraine: migraine)
            }
        }
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return StatisticsView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
}

// Add extension to convert between TimeFrame types
extension StatisticsView.TimeFilter {
    var toViewModelTimeFrame: MigraineViewModel.TimeFrame {
        switch self {
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .range: return .week // Fallback mapping
        }
    }
}

// Add helper extension for date generation
extension Calendar {
    func generateDates(
        inside interval: DateInterval,
        matching components: DateComponents
    ) -> [Date] {
        var dates: [Date] = []
        dates.append(interval.start)
        
        enumerateDates(
            startingAfter: interval.start,
            matching: components,
            matchingPolicy: .nextTime
        ) { date, _, stop in
            if let date = date {
                if date < interval.end {
                    dates.append(date)
                } else {
                    stop = true
                }
            }
        }
        
        return dates
    }
} 

