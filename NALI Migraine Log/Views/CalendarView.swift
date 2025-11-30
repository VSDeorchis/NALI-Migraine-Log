import SwiftUI
import CoreData

private struct CalendarDay: Identifiable {
    let id: Int
    let date: Date?
}

struct CalendarView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()
    @State private var selectedMigraine: MigraineEvent?
    @State private var showingNewMigraine = false
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Month selector
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                    }
                    
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                    
                    Button(action: nextMonth) {
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
                    ForEach(daysInMonth(), id: \.self) { date in
                        if let date = date {
                            DayCell(date: date, migraines: migrainesForDate(date), viewModel: viewModel)
                        } else {
                            Color.clear
                        }
                    }
                }
                
                // Selected day details
                let migraines = viewModel.migraines
                if !migraines.isEmpty {
                    List(migraines) { migraine in
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
                } else {
                    Text("No migraines recorded for this date")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Calendar")
            .sheet(isPresented: $showingNewMigraine) {
                NewMigraineView(viewModel: viewModel)
            }
        }
    }
    
    private func previousMonth() {
        selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
    }
    
    private func nextMonth() {
        selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
    }
    
    private func daysInMonth() -> [Date?] {
        let range = calendar.range(of: .day, in: .month, for: selectedDate)!
        let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        var days: [Date?] = []
        
        // Add empty days at start
        for index in 0..<(firstWeekday - 1) {
            days.append(nil)
        }
        
        // Add days of month
        for day in 1...range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        // Add empty days at end
        let remainingDays = (7 - (days.count % 7)) % 7
        for index in 0..<remainingDays {
            days.append(nil)
        }
        
        return days
    }
    
    private func migrainesForDate(_ date: Date) -> [MigraineEvent] {
        viewModel.migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return calendar.isDate(startTime, inSameDayAs: date)
        }
    }
    
    private func printDebugInfo() {
        #if DEBUG
        print("Number of migraines: \(viewModel.migraines.count)")
        #endif
    }
}

struct DayCell: View {
    let date: Date
    let migraines: [MigraineEvent]
    @ObservedObject var viewModel: MigraineViewModel
    
    var body: some View {
        NavigationLink(destination: DayDetailView(date: date, migraines: migraines, viewModel: viewModel)) {
            ZStack {
                // Migraine indicator (solid pink circle)
                if !migraines.isEmpty {
                    Circle()
                        .fill(Color.pink.opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                
                // Current day indicator (solid light blue circle with dark blue outline)
                if Calendar.current.isDateInToday(date) {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .stroke(Color.blue, lineWidth: 1)
                        .frame(width: 32, height: 32)
                }
                
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(.body))
            }
            .frame(height: 40)
        }
    }
}

struct DayDetailView: View {
    let date: Date
    let migraines: [MigraineEvent]
    @ObservedObject var viewModel: MigraineViewModel
    
    var body: some View {
        List(migraines) { migraine in
            MigraineRowView(viewModel: viewModel, migraine: migraine)
        }
        .navigationTitle(date.formatted(date: .complete, time: .omitted))
    }
}

struct MigraineSummaryCard: View {
    let migraine: MigraineEvent
    
    // Helper to get active medications
    private var activeMedications: [String] {
        var medications: [String] = []
        if migraine.tookIbuprofin { medications.append("Ibuprofen") }
        if migraine.tookExcedrin { medications.append("Excedrin") }
        if migraine.tookTylenol { medications.append("Tylenol") }
        if migraine.tookSumatriptan { medications.append("Sumatriptan") }
        if migraine.tookRizatriptan { medications.append("Rizatriptan") }
        if migraine.tookNaproxen { medications.append("Naproxen") }
        if migraine.tookFrovatriptan { medications.append("Frovatriptan") }
        if migraine.tookNaratriptan { medications.append("Naratriptan") }
        if migraine.tookNurtec { medications.append("Nurtec") }
        if migraine.tookUbrelvy { medications.append("Ubrelvy") }
        if migraine.tookReyvow { medications.append("Reyvow") }
        if migraine.tookTrudhesa { medications.append("Trudhesa") }
        if migraine.tookElyxyb { medications.append("Elyxyb") }
        if migraine.tookOther { medications.append("Other") }
        return medications
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(migraine.startTime!, style: .time)
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
            
            let medications = activeMedications
            if !medications.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(medications, id: \.self) { medication in
                            Text(medication)
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
    let context = PersistenceController.preview.container.viewContext
    return CalendarView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 

