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
                    
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                    
                    Button(action: { moveMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                    }
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
                
                // Calendar grid
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(daysInMonth()) { day in
                        if let date = day.date {
                            DayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                migraines: migrainesForDate(date)
                            )
                            .onTapGesture {
                                selectedDate = date
                            }
                        } else {
                            Color.clear
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 300)
            
            // Detail View
            let selectedDateMigraines = migrainesForDate(selectedDate)
            if !selectedDateMigraines.isEmpty {
                List(selection: $selectedMigraine) {
                    ForEach(selectedDateMigraines) { migraine in
                        MigraineRowView(migraine: migraine)
                            .tag(migraine)
                    }
                }
                .frame(minWidth: 300)
            } else {
                Text("No migraines recorded for this date")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Calendar")
        .sheet(item: $selectedMigraine) { migraine in
            MigraineDetailView(migraine: migraine, viewModel: viewModel)
        }
    }
    
    private func moveMonth(by months: Int) {
        if let newDate = calendar.date(byAdding: .month, value: months, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func daysInMonth() -> [CalendarDay] {
        guard let range = calendar.range(of: .day, in: .month, for: selectedDate),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var days: [CalendarDay] = []
        
        // Add empty days at start
        for index in 0..<(firstWeekday - 1) {
            days.append(CalendarDay(id: -index - 1, date: nil))
        }
        
        // Add days of month
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
}

private struct CalendarDay: Identifiable {
    let id: Int
    let date: Date?
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let migraines: [MigraineEvent]
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
            
            VStack {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded))
                if !migraines.isEmpty {
                    Text("\(migraines.count)")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color.red))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue.opacity(0.3)
        }
        return migraines.isEmpty ? .clear : .red.opacity(0.1)
    }
} 
