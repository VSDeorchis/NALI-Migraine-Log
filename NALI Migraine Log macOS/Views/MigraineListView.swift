import SwiftUI

// MARK: - Smart Filter

enum SmartFilter: String, CaseIterable, Identifiable {
    case all = "All Entries"
    case highPain = "High Pain (7+)"
    case withAura = "With Aura"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case weatherRelated = "Weather Related"
    case missedWork = "Missed Work"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .highPain: return "exclamationmark.triangle.fill"
        case .withAura: return "eye.circle"
        case .thisWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar"
        case .weatherRelated: return "cloud.sun.fill"
        case .missedWork: return "briefcase.fill"
        }
    }
    
    func matches(_ migraine: MigraineEvent) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .all:
            return true
        case .highPain:
            return migraine.painLevel >= 7
        case .withAura:
            return migraine.hasAura
        case .thisWeek:
            guard let start = migraine.startTime else { return false }
            return calendar.isDate(start, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            guard let start = migraine.startTime else { return false }
            return calendar.isDate(start, equalTo: now, toGranularity: .month)
        case .weatherRelated:
            return migraine.hasWeatherData
        case .missedWork:
            return migraine.missedWork
        }
    }
}

// MARK: - Sort Option

enum SortOption: String, CaseIterable {
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case painHighest = "Pain (Highest)"
    case painLowest = "Pain (Lowest)"
    case durationLongest = "Duration (Longest)"
}

// MARK: - Migraine List View (Table + Inspector)

struct MigraineListView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @State private var searchText = ""
    @State private var selectedMigraineID: MigraineEvent.ID?
    @State private var isEditing = false
    @State private var sortOption: SortOption = .dateNewest
    @State private var showInspector = true
    var activeFilter: SmartFilter = .all
    
    private var selectedMigraine: MigraineEvent? {
        guard let id = selectedMigraineID else { return nil }
        return filteredMigraines.first { $0.id == id }
    }
    
    var filteredMigraines: [MigraineEvent] {
        var result = viewModel.migraines.filter { activeFilter.matches($0) }
        
        if !searchText.isEmpty {
            result = result.filter { migraine in
                let notesMatch = migraine.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let medicationsMatch = migraine.selectedMedicationNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                let triggersMatch = migraine.selectedTriggerNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
                let locationMatch = migraine.location?.localizedCaseInsensitiveContains(searchText) ?? false
                return notesMatch || medicationsMatch || triggersMatch || locationMatch
            }
        }
        
        switch sortOption {
        case .dateNewest:
            result.sort { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
        case .dateOldest:
            result.sort { ($0.startTime ?? .distantPast) < ($1.startTime ?? .distantPast) }
        case .painHighest:
            result.sort { $0.painLevel > $1.painLevel }
        case .painLowest:
            result.sort { $0.painLevel < $1.painLevel }
        case .durationLongest:
            result.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
        
        return result
    }
    
    var body: some View {
        HSplitView {
            // Main table area
            VStack(spacing: 0) {
                if filteredMigraines.isEmpty {
                    emptyStateView
                } else {
                    migraineTable
                }
            }
            .frame(minWidth: 500)
            
            // Inspector panel
            if showInspector, let migraine = selectedMigraine {
                MigraineInspectorView(
                    migraine: migraine,
                    viewModel: viewModel,
                    isEditing: $isEditing
                )
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 450)
            }
        }
        .navigationTitle(activeFilter == .all ? "Migraine Log" : activeFilter.rawValue)
        .searchable(text: $searchText, prompt: "Search medications, triggers, or notes")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Sort picker
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 180)
                
                Divider()
                
                // Entry count
                Text("\(filteredMigraines.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Inspector toggle
                Button {
                    withAnimation {
                        showInspector.toggle()
                    }
                } label: {
                    Label("Toggle Inspector", systemImage: showInspector ? "sidebar.trailing" : "sidebar.trailing")
                }
                .help("Toggle Inspector Panel (⌘I)")
                .keyboardShortcut("i", modifiers: .command)
                
                // Export button
                Button {
                    exportMigrainesToCSV()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export to CSV (⇧⌘E)")
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        .task {
            viewModel.fetchMigraines()
        }
        .onChange(of: selectedMigraineID) { _ in
            if selectedMigraineID == nil {
                isEditing = false
            }
        }
    }
    
    // MARK: - Table View
    
    private var migraineTable: some View {
        Table(of: MigraineEvent.self, selection: $selectedMigraineID) {
            TableColumn("Date") { (migraine: MigraineEvent) in
                VStack(alignment: .leading, spacing: 2) {
                    if let startTime = migraine.startTime {
                        Text(startTime, style: .date)
                            .font(.system(.body, weight: .medium))
                        Text(startTime, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            .width(min: 120, ideal: 150)
            
            TableColumn("Pain") { (migraine: MigraineEvent) in
                HStack(spacing: 6) {
                    Circle()
                        .fill(painLevelColor(migraine.painLevel))
                        .frame(width: 10, height: 10)
                    Text("\(migraine.painLevel)")
                        .font(.body.weight(.semibold))
                        .foregroundColor(painLevelColor(migraine.painLevel))
                }
            }
            .width(min: 50, ideal: 60)
            
            TableColumn("Location") { (migraine: MigraineEvent) in
                Text(migraine.location ?? "—")
                    .font(.body)
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("Duration") { (migraine: MigraineEvent) in
                if let text = formattedDuration(for: migraine) {
                    Label(text, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("Triggers") { (migraine: MigraineEvent) in
                let triggers = migraine.selectedTriggerNames
                if triggers.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                } else {
                    Text(triggers.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .width(min: 100, ideal: 160)
            
            TableColumn("Symptoms") { (migraine: MigraineEvent) in
                let count = symptomCount(for: migraine)
                if count > 0 {
                    Text("\(count) symptom\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.purple)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .width(min: 80, ideal: 100)
        } rows: {
            ForEach(filteredMigraines) { migraine in
                TableRow(migraine)
                    .contextMenu {
                        Button {
                            selectedMigraineID = migraine.id
                            isEditing = false
                        } label: {
                            Label("View Details", systemImage: "eye")
                        }
                        
                        Button {
                            selectedMigraineID = migraine.id
                            isEditing = true
                        } label: {
                            Label("Edit…", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button {
                            exportSingleMigraine(migraine)
                        } label: {
                            Label("Export as PDF…", systemImage: "doc.richtext")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            viewModel.deleteMigraine(migraine)
                            if selectedMigraineID == migraine.id {
                                selectedMigraineID = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: activeFilter == .all ? "brain.head.profile" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            if activeFilter == .all && searchText.isEmpty {
                Text("No Migraines Logged")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Start tracking your migraines to see patterns\nand receive personalized predictions.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Press ⌘N to log your first entry")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else if !searchText.isEmpty {
                Text("No Results")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
                Text("No migraines match \"\(searchText)\"")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Text("No Matching Entries")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
                Text("No migraines match the \"\(activeFilter.rawValue)\" filter.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func formattedDuration(for migraine: MigraineEvent) -> String? {
        guard let start = migraine.startTime,
              let end = migraine.endTime else { return nil }
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return nil }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
    
    private func symptomCount(for migraine: MigraineEvent) -> Int {
        var count = 0
        if migraine.hasAura { count += 1 }
        if migraine.hasPhotophobia { count += 1 }
        if migraine.hasPhonophobia { count += 1 }
        if migraine.hasNausea { count += 1 }
        if migraine.hasVomiting { count += 1 }
        if migraine.hasWakeUpHeadache { count += 1 }
        if migraine.hasTinnitus { count += 1 }
        if migraine.hasVertigo { count += 1 }
        return count
    }
    
    private func painLevelColor(_ level: Int16) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    // MARK: - Export
    
    private func exportMigrainesToCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Migraine_Log_\(dateStamp()).csv"
        panel.title = "Export Migraine Log"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            var csv = "Date,Time,Pain Level,Location,Duration,Triggers,Medications,Symptoms,Notes\n"
            
            for m in filteredMigraines {
                let date = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? ""
                let time = m.startTime.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
                let pain = "\(m.painLevel)"
                let location = m.location ?? ""
                let duration = formattedDuration(for: m) ?? ""
                let triggers = m.selectedTriggerNames.joined(separator: "; ")
                let medications = m.selectedMedicationNames.joined(separator: "; ")
                var symptoms: [String] = []
                if m.hasAura { symptoms.append("Aura") }
                if m.hasPhotophobia { symptoms.append("Photophobia") }
                if m.hasPhonophobia { symptoms.append("Phonophobia") }
                if m.hasNausea { symptoms.append("Nausea") }
                if m.hasVomiting { symptoms.append("Vomiting") }
                if m.hasWakeUpHeadache { symptoms.append("Wake-up Headache") }
                if m.hasTinnitus { symptoms.append("Tinnitus") }
                if m.hasVertigo { symptoms.append("Vertigo") }
                let notes = (m.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                
                csv += "\"\(date)\",\"\(time)\",\(pain),\"\(location)\",\"\(duration)\",\"\(triggers)\",\"\(medications)\",\"\(symptoms.joined(separator: "; "))\",\"\(notes)\"\n"
            }
            
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func exportSingleMigraine(_ migraine: MigraineEvent) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Migraine_\(migraine.startTime.map { dateStamp(from: $0) } ?? "Entry").pdf"
        panel.title = "Export Migraine"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            generateMigrainePDF(migraine, to: url)
        }
    }
    
    private func generateMigrainePDF(_ migraine: MigraineEvent, to url: URL) {
        let pdfMetaData: [CFString: Any] = [
            kCGPDFContextCreator: "Headway Migraine Log",
            kCGPDFContextTitle: "Migraine Report"
        ]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        
        guard let context = CGContext(url as CFURL, mediaBox: nil, pdfMetaData as CFDictionary) else { return }
        context.beginPDFPage(nil)
        
        let nsFont = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let titleFont = NSFont(name: "Helvetica-Bold", size: 18) ?? NSFont.boldSystemFont(ofSize: 18)
        let headerFont = NSFont(name: "Helvetica-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14)
        
        var y: CGFloat = pageRect.height - 50
        let leftMargin: CGFloat = 50
        
        func drawText(_ text: String, font: NSFont, at point: CGPoint) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let str = NSAttributedString(string: text, attributes: attrs)
            str.draw(at: point)
        }
        
        drawText("Migraine Report", font: titleFont, at: CGPoint(x: leftMargin, y: y))
        y -= 30
        
        if let start = migraine.startTime {
            drawText("Date: \(DateFormatter.localizedString(from: start, dateStyle: .long, timeStyle: .short))", font: nsFont, at: CGPoint(x: leftMargin, y: y))
            y -= 20
        }
        
        drawText("Pain Level: \(migraine.painLevel)/10", font: nsFont, at: CGPoint(x: leftMargin, y: y))
        y -= 20
        drawText("Location: \(migraine.location ?? "Not specified")", font: nsFont, at: CGPoint(x: leftMargin, y: y))
        y -= 20
        
        if let dur = formattedDuration(for: migraine) {
            drawText("Duration: \(dur)", font: nsFont, at: CGPoint(x: leftMargin, y: y))
            y -= 20
        }
        
        y -= 10
        let triggers = migraine.selectedTriggerNames
        if !triggers.isEmpty {
            drawText("Triggers:", font: headerFont, at: CGPoint(x: leftMargin, y: y))
            y -= 18
            drawText(triggers.joined(separator: ", "), font: nsFont, at: CGPoint(x: leftMargin + 10, y: y))
            y -= 20
        }
        
        let meds = migraine.selectedMedicationNames
        if !meds.isEmpty {
            drawText("Medications:", font: headerFont, at: CGPoint(x: leftMargin, y: y))
            y -= 18
            drawText(meds.joined(separator: ", "), font: nsFont, at: CGPoint(x: leftMargin + 10, y: y))
            y -= 20
        }
        
        if let notes = migraine.notes, !notes.isEmpty {
            y -= 10
            drawText("Notes:", font: headerFont, at: CGPoint(x: leftMargin, y: y))
            y -= 18
            drawText(notes, font: nsFont, at: CGPoint(x: leftMargin + 10, y: y))
        }
        
        // Footer
        drawText("Generated by Headway — Migraine Monitor and Analytics", font: NSFont(name: "Helvetica", size: 9) ?? NSFont.systemFont(ofSize: 9), at: CGPoint(x: leftMargin, y: 30))
        
        context.endPDFPage()
        context.closePDF()
    }
    
    private func dateStamp(from date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

// MARK: - Inspector View

struct MigraineInspectorView: View {
    let migraine: MigraineEvent
    let viewModel: MigraineViewModel
    @Binding var isEditing: Bool
    
    @State private var editedStartTime: Date
    @State private var editedEndTime: Date?
    @State private var editedPainLevel: Int16
    @State private var editedLocation: String
    @State private var editedNotes: String
    @State private var editedTriggers: Set<String>
    @State private var editedMedications: Set<String>
    @State private var editedHasAura: Bool
    @State private var editedHasPhotophobia: Bool
    @State private var editedHasPhonophobia: Bool
    @State private var editedHasNausea: Bool
    @State private var editedHasVomiting: Bool
    @State private var editedHasWakeUpHeadache: Bool
    @State private var editedHasTinnitus: Bool
    @State private var editedHasVertigo: Bool
    @State private var editedMissedWork: Bool
    @State private var editedMissedSchool: Bool
    @State private var editedMissedEvents: Bool
    
    init(migraine: MigraineEvent, viewModel: MigraineViewModel, isEditing: Binding<Bool>) {
        self.migraine = migraine
        self.viewModel = viewModel
        _isEditing = isEditing
        _editedStartTime = State(initialValue: migraine.startTime ?? Date())
        _editedEndTime = State(initialValue: migraine.endTime)
        _editedPainLevel = State(initialValue: migraine.painLevel)
        _editedLocation = State(initialValue: migraine.location ?? "")
        _editedNotes = State(initialValue: migraine.notes ?? "")
        _editedTriggers = State(initialValue: Set(migraine.selectedTriggerNames))
        _editedMedications = State(initialValue: Set(migraine.selectedMedicationNames))
        _editedHasAura = State(initialValue: migraine.hasAura)
        _editedHasPhotophobia = State(initialValue: migraine.hasPhotophobia)
        _editedHasPhonophobia = State(initialValue: migraine.hasPhonophobia)
        _editedHasNausea = State(initialValue: migraine.hasNausea)
        _editedHasVomiting = State(initialValue: migraine.hasVomiting)
        _editedHasWakeUpHeadache = State(initialValue: migraine.hasWakeUpHeadache)
        _editedHasTinnitus = State(initialValue: migraine.hasTinnitus)
        _editedHasVertigo = State(initialValue: migraine.hasVertigo)
        _editedMissedWork = State(initialValue: migraine.missedWork)
        _editedMissedSchool = State(initialValue: migraine.missedSchool)
        _editedMissedEvents = State(initialValue: migraine.missedEvents)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Inspector header
            HStack {
                Text("Details")
                    .font(.headline)
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        resetEdits()
                    }
                    .controlSize(.small)
                    Button("Save") {
                        saveChanges()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if isEditing {
                editView
            } else {
                readView
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: migraine) { _ in
            resetEdits()
            isEditing = false
        }
    }
    
    // MARK: - Read-only View
    
    private var readView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Date & Time
                InspectorSection(title: "Date & Time", icon: "calendar") {
                    if let start = migraine.startTime {
                        Text(start, style: .date)
                            .font(.body.weight(.medium))
                        Text(start, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let end = migraine.endTime {
                        HStack {
                            Text("Ended:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(end, style: .time)
                                .font(.caption)
                        }
                    }
                    if let dur = duration {
                        HStack {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(dur)
                                .font(.caption.weight(.medium))
                        }
                    }
                }
                
                // Pain
                InspectorSection(title: "Pain", icon: "thermometer") {
                    HStack(spacing: 8) {
                        Text("\(migraine.painLevel)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(painColor)
                        Text("/ 10")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(migraine.location ?? "Unknown")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Pain bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(painColor)
                                .frame(width: geo.size.width * CGFloat(migraine.painLevel) / 10.0)
                        }
                    }
                    .frame(height: 6)
                }
                
                // Symptoms
                let symptoms = activeSymptoms
                if !symptoms.isEmpty {
                    InspectorSection(title: "Symptoms", icon: "staroflife") {
                        FlowLayout {
                            ForEach(symptoms, id: \.0) { name, icon in
                                Label(name, systemImage: icon)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Triggers
                let triggers = migraine.selectedTriggerNames
                if !triggers.isEmpty {
                    InspectorSection(title: "Triggers", icon: "bolt.fill") {
                        FlowLayout {
                            ForEach(triggers, id: \.self) { trigger in
                                Text(trigger)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Medications
                let meds = migraine.selectedMedicationNames
                if !meds.isEmpty {
                    InspectorSection(title: "Medications", icon: "pill.fill") {
                        FlowLayout {
                            ForEach(meds, id: \.self) { med in
                                Text(med)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // Impact
                if migraine.missedWork || migraine.missedSchool || migraine.missedEvents {
                    InspectorSection(title: "Impact", icon: "chart.bar.fill") {
                        VStack(alignment: .leading, spacing: 4) {
                            if migraine.missedWork {
                                Label("Missed Work", systemImage: "briefcase")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            if migraine.missedSchool {
                                Label("Missed School", systemImage: "graduationcap")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            if migraine.missedEvents {
                                Label("Missed Events", systemImage: "calendar.badge.minus")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                // Notes
                if let notes = migraine.notes, !notes.isEmpty {
                    InspectorSection(title: "Notes", icon: "note.text") {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Edit View
    
    private var editView: some View {
        EditMigraineView(
            startTime: $editedStartTime,
            endTime: $editedEndTime,
            painLevel: $editedPainLevel,
            location: $editedLocation,
            notes: $editedNotes,
            selectedTriggers: $editedTriggers,
            selectedMedications: $editedMedications,
            hasAura: $editedHasAura,
            hasPhotophobia: $editedHasPhotophobia,
            hasPhonophobia: $editedHasPhonophobia,
            hasNausea: $editedHasNausea,
            hasVomiting: $editedHasVomiting,
            hasWakeUpHeadache: $editedHasWakeUpHeadache,
            hasTinnitus: $editedHasTinnitus,
            hasVertigo: $editedHasVertigo,
            missedWork: $editedMissedWork,
            missedSchool: $editedMissedSchool,
            missedEvents: $editedMissedEvents
        )
    }
    
    // MARK: - Helpers
    
    private var painColor: Color {
        switch migraine.painLevel {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    private var duration: String? {
        guard let start = migraine.startTime,
              let end = migraine.endTime else { return nil }
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return nil }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
    
    private var activeSymptoms: [(String, String)] {
        var symptoms: [(String, String)] = []
        if migraine.hasAura { symptoms.append(("Aura", "eye.circle")) }
        if migraine.hasPhotophobia { symptoms.append(("Light Sensitivity", "sun.max")) }
        if migraine.hasPhonophobia { symptoms.append(("Sound Sensitivity", "ear")) }
        if migraine.hasNausea { symptoms.append(("Nausea", "stomach")) }
        if migraine.hasVomiting { symptoms.append(("Vomiting", "exclamationmark.triangle")) }
        if migraine.hasWakeUpHeadache { symptoms.append(("Wake-up Headache", "bed.double")) }
        if migraine.hasTinnitus { symptoms.append(("Tinnitus", "waveform")) }
        if migraine.hasVertigo { symptoms.append(("Vertigo", "arrow.triangle.2.circlepath")) }
        return symptoms
    }
    
    private func resetEdits() {
        editedStartTime = migraine.startTime ?? Date()
        editedEndTime = migraine.endTime
        editedPainLevel = migraine.painLevel
        editedLocation = migraine.location ?? ""
        editedNotes = migraine.notes ?? ""
        editedTriggers = Set(migraine.selectedTriggerNames)
        editedMedications = Set(migraine.selectedMedicationNames)
        editedHasAura = migraine.hasAura
        editedHasPhotophobia = migraine.hasPhotophobia
        editedHasPhonophobia = migraine.hasPhonophobia
        editedHasNausea = migraine.hasNausea
        editedHasVomiting = migraine.hasVomiting
        editedHasWakeUpHeadache = migraine.hasWakeUpHeadache
        editedHasTinnitus = migraine.hasTinnitus
        editedHasVertigo = migraine.hasVertigo
        editedMissedWork = migraine.missedWork
        editedMissedSchool = migraine.missedSchool
        editedMissedEvents = migraine.missedEvents
    }
    
    private func saveChanges() {
        viewModel.updateMigraine(
            migraine,
            startTime: editedStartTime,
            endTime: editedEndTime,
            painLevel: editedPainLevel,
            location: editedLocation,
            notes: editedNotes.isEmpty ? nil : editedNotes,
            triggers: Array(editedTriggers),
            medications: Array(editedMedications),
            hasAura: editedHasAura,
            hasPhotophobia: editedHasPhotophobia,
            hasPhonophobia: editedHasPhonophobia,
            hasNausea: editedHasNausea,
            hasVomiting: editedHasVomiting,
            hasWakeUpHeadache: editedHasWakeUpHeadache,
            hasTinnitus: editedHasTinnitus,
            hasVertigo: editedHasVertigo,
            missedWork: editedMissedWork,
            missedSchool: editedMissedSchool,
            missedEvents: editedMissedEvents
        )
        isEditing = false
    }
}

// MARK: - Inspector Section

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

// MARK: - Search Bar (kept for backward compat)

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search medications, triggers, or notes", text: $text)
                .textFieldStyle(.roundedBorder)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    MigraineListView(viewModel: MigraineViewModel(context: PersistenceController.preview.container.viewContext))
}
