import SwiftUI

struct CalendarView: View {
    @ObservedObject var migraineStore: MigraineStore
    @State private var selectedDate = Date()
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Month selector with custom styling
                HStack {
                    Button(action: { moveMonth(by: -1) }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .foregroundColor(.blue)
                            .imageScale(.large)
                    }
                    
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                    
                    Button(action: { moveMonth(by: 1) }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .foregroundColor(.blue)
                            .imageScale(.large)
                    }
                }
                .padding(.horizontal)
                
                // Day labels with custom styling
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                
                // Calendar grid with enhanced styling
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(daysInMonth(), id: \.self) { date in
                        if let date = date {
                            DayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                hasMigraine: hasMigraine(on: date),
                                migraineCount: migraineCount(on: date)
                            )
                            .onTapGesture {
                                withAnimation {
                                    selectedDate = date
                                }
                            }
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Selected day details
                if let migraines = migrainesForDate(selectedDate), !migraines.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Migraines on \(selectedDate, style: .date)")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(migraines) { migraine in
                                MigraineSummaryCard(migraine: migraine)
                            }
                        }
                        .padding(.top)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Calendar")
        }
    }
    
    private func moveMonth(by months: Int) {
        if let newDate = calendar.date(byAdding: .month, value: months, to: selectedDate) {
            withAnimation {
                selectedDate = newDate
            }
        }
    }
    
    private func daysInMonth() -> [Date?] {
        let range = calendar.range(of: .day, in: .month, for: selectedDate)!
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
    
    private func hasMigraine(on date: Date) -> Bool {
        migraineStore.migraines.contains { migraine in
            calendar.isDate(migraine.startTime, inSameDayAs: date)
        }
    }
    
    private func migraineCount(on date: Date) -> Int {
        migraineStore.migraines.filter { migraine in
            calendar.isDate(migraine.startTime, inSameDayAs: date)
        }.count
    }
    
    private func migrainesForDate(_ date: Date) -> [MigraineEvent]? {
        let dayMigraines = migraineStore.migraines.filter { migraine in
            calendar.isDate(migraine.startTime, inSameDayAs: date)
        }
        return dayMigraines.isEmpty ? nil : dayMigraines
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let hasMigraine: Bool
    let migraineCount: Int
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
            
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isSelected ? .bold : .regular)
                
                if migraineCount > 1 {
                    Text("\(migraineCount)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .foregroundColor(textColor)
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private var backgroundColor: Color {
        if hasMigraine {
            return isSelected ? Color.red : Color.red.opacity(0.3)
        }
        return isSelected ? Color.blue.opacity(0.1) : Color.clear
    }
    
    private var textColor: Color {
        if hasMigraine {
            return isSelected ? .white : .primary
        }
        return .primary
    }
}

struct MigraineSummaryCard: View {
    let migraine: MigraineEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(migraine.startTime, style: .time)
                    .font(.headline)
                if let duration = migraine.duration {
                    Text("(\(Int(duration/3600))h \(Int((duration.truncatingRemainder(dividingBy: 3600))/60))m)")
                        .foregroundColor(.secondary)
                } else {
                    Text("(Ongoing)")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Pain: \(migraine.painLevel)/10")
                    .font(.subheadline)
                    .padding(4)
                    .background(painLevelColor.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if !migraine.medications.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(migraine.medications), id: \.self) { medication in
                            Text(medication.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
        .padding(.horizontal)
    }
    
    private var painLevelColor: Color {
        switch migraine.painLevel {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
}

#Preview {
    CalendarView(migraineStore: MigraineStore())
} 