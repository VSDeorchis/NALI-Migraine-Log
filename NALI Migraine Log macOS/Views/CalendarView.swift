import SwiftUI

struct CalendarView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var selectedDate = Date()
    @State private var selectedMigraine: MigraineEvent?
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        HSplitView {
            // Calendar View
            VStack(spacing: 20) {
                // Month selector
                HStack {
                    Button(action: { moveMonth(by: -1) }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .help("Previous Month")
                    
                    Spacer()
                    
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2.weight(.semibold))
                    
                    Spacer()
                    
                    Button("Today") {
                        withAnimation {
                            selectedDate = Date()
                        }
                    }
                    .controlSize(.small)
                    .help("Go to Today")
                    
                    Button(action: { moveMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .help("Next Month")
                }
                .padding(.horizontal)
                
                // Days of week header
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }
                
                // Calendar grid with heat map
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(daysInMonth()) { day in
                        if let date = day.date {
                            HeatMapDayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                migraines: migrainesForDate(date)
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedDate = date
                                }
                            }
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                
                // Heat map legend
                heatMapLegend
                    .padding(.top, 8)
                
                // Monthly summary
                monthlySummary
                    .padding(.top, 4)
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 350)
            
            // Detail View
            let selectedDateMigraines = migrainesForDate(selectedDate)
            if !selectedDateMigraines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(selectedDate, style: .date)
                            .font(.headline)
                        Spacer()
                        Text("\(selectedDateMigraines.count) migraine\(selectedDateMigraines.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    Divider()
                    
                    List(selectedDateMigraines) { migraine in
                        CalendarMigraineRow(migraine: migraine)
                            .onTapGesture(count: 2) {
                                selectedMigraine = migraine
                            }
                    }
                }
                .frame(minWidth: 300)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No migraines on this date")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(selectedDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Calendar")
        .sheet(item: $selectedMigraine) { migraine in
            MigraineDetailView(migraine: migraine, viewModel: viewModel)
        }
    }
    
    // MARK: - Heat Map Legend
    
    private var heatMapLegend: some View {
        HStack(spacing: 16) {
            Text("Pain Intensity:")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                ForEach([
                    ("None", Color.clear),
                    ("Mild", Color.green),
                    ("Moderate", Color.yellow),
                    ("Severe", Color.orange),
                    ("Extreme", Color.red)
                ], id: \.0) { label, color in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color == .clear ? Color.secondary.opacity(0.1) : color.opacity(0.5))
                            .frame(width: 14, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(color == .clear ? Color.secondary.opacity(0.3) : color.opacity(0.8), lineWidth: 0.5)
                            )
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Monthly Summary
    
    private var monthlySummary: some View {
        let monthMigraines = migrainesForMonth(selectedDate)
        let avgPain = monthMigraines.isEmpty ? 0 : monthMigraines.reduce(0) { $0 + Int($1.painLevel) } / monthMigraines.count
        let daysWithMigraines = Set(monthMigraines.compactMap { $0.startTime.map { calendar.startOfDay(for: $0) } }).count
        
        return HStack(spacing: 24) {
            VStack(spacing: 2) {
                Text("\(monthMigraines.count)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("Entries")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 2) {
                Text("\(daysWithMigraines)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("Days")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 2) {
                Text("\(avgPain)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(painColor(for: Int16(avgPain)))
                Text("Avg Pain")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helpers
    
    private func moveMonth(by months: Int) {
        if let newDate = calendar.date(byAdding: .month, value: months, to: selectedDate) {
            withAnimation {
                selectedDate = newDate
            }
        }
    }
    
    private func daysInMonth() -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: selectedDate),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var days: [CalendarDay] = []
        
        for index in 0..<(firstWeekday - 1) {
            days.append(CalendarDay(id: -index - 1, date: nil))
        }
        
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(CalendarDay(id: day, date: date))
            }
        }
        
        return days
    }
    
    private func migrainesForDate(_ date: Date) -> [MigraineEvent] {
        viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return calendar.isDate(startTime, inSameDayAs: date)
        }
    }
    
    private func migrainesForMonth(_ date: Date) -> [MigraineEvent] {
        viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return calendar.isDate(startTime, equalTo: date, toGranularity: .month)
        }
    }
    
    private func painColor(for level: Int16) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .secondary
        }
    }
}

// MARK: - Calendar Day Model

private struct CalendarDay: Identifiable {
    let id: Int
    let date: Date?
}

// MARK: - Heat Map Day Cell

private struct HeatMapDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let migraines: [MigraineEvent]
    private let calendar = Calendar.current
    
    private var maxPainLevel: Int16 {
        migraines.map(\.painLevel).max() ?? 0
    }
    
    private var heatColor: Color {
        if migraines.isEmpty { return .clear }
        switch maxPainLevel {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .clear
        }
    }
    
    var body: some View {
        ZStack {
            // Heat map background
            RoundedRectangle(cornerRadius: 6)
                .fill(migraines.isEmpty ? Color.secondary.opacity(0.04) : heatColor.opacity(0.3))
            
            // Selection ring
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            
            // Today indicator
            if isToday && !isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            }
            
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded).weight(isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .accentColor : (isToday ? .accentColor : .primary))
                
                if !migraines.isEmpty {
                    HStack(spacing: 1) {
                        // Show dots for number of migraines (up to 3)
                        ForEach(0..<min(migraines.count, 3), id: \.self) { _ in
                            Circle()
                                .fill(heatColor)
                                .frame(width: 5, height: 5)
                        }
                        if migraines.count > 3 {
                            Text("+")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(heatColor)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .help(tooltipText)
    }
    
    private var tooltipText: String {
        if migraines.isEmpty {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        let count = migraines.count
        let maxPain = maxPainLevel
        return "\(count) migraine\(count == 1 ? "" : "s") — Max pain: \(maxPain)/10"
    }
}

// MARK: - Calendar Migraine Row

private struct CalendarMigraineRow: View {
    let migraine: MigraineEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let startTime = migraine.startTime {
                    Text(startTime, style: .time)
                        .font(.headline)
                }
                Spacer()
                Text("Pain: \(migraine.painLevel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(painColor)
            }
            
            HStack {
                Text(migraine.location ?? "Unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let dur = formattedDuration {
                    Text("·")
                        .foregroundColor(.secondary)
                    Label(dur, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !migraine.selectedTriggerNames.isEmpty {
                Text(migraine.selectedTriggerNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var painColor: Color {
        switch migraine.painLevel {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    private var formattedDuration: String? {
        guard let start = migraine.startTime,
              let end = migraine.endTime else { return nil }
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return nil }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
