struct WatchMigraineDetailView: View {
    @State private var startTime: Date = Date()
    @State private var endTime: Date?
    @State private var painLevel: Int = 5
    @State private var location: String = "Home"
    @State private var hasAura: Bool = false
    @State private var hasPhotophobia: Bool = false
    @State private var hasPhonophobia: Bool = false
    @State private var hasNausea: Bool = false
    @State private var hasVomiting: Bool = false
    @State private var hasWakeUpHeadache: Bool = false
    @State private var hasTinnitus: Bool = false
    @State private var hasVertigo: Bool = false
    @State private var selectedTriggers: [Trigger] = []
    @State private var selectedMedications: [Medication] = []
    @State private var missedWork: Bool = false
    @State private var missedSchool: Bool = false
    @State private var missedEvents: Bool = false
    @State private var notes: String = ""
    @State private var lastPainLevel: Int = 0  // Track previous value for haptics
    
    var body: some View {
        Form {
            Section("Timing") {
                DatePicker("Start Time", selection: $startTime)
                DatePicker("End Time", selection: Binding(
                    get: { endTime ?? startTime },
                    set: { endTime = $0 }
                ))
            }
            
            Section("Pain Level: \(painLevel)") {
                Slider(value: .init(
                    get: { Double(painLevel) },
                    set: { newValue in
                        let newLevel = Int(newValue)
                        if newLevel != lastPainLevel {
                            playPainLevelHaptic(newLevel)
                            lastPainLevel = newLevel
                        }
                        painLevel = newLevel
                    }
                ), in: 1...10, step: 1)
                .tint(painLevelColor(painLevel))
            }
            
            Section("Location") {
                Picker("Location", selection: $location) {
                    ForEach(locations, id: \.self) { location in
                        Text(location).tag(location)
                    }
                }
            }
            
            Section("Primary Symptoms") {
                Toggle("Aura", isOn: $hasAura)
                Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                Toggle("Nausea", isOn: $hasNausea)
                Toggle("Vomiting", isOn: $hasVomiting)
            }
            
            Section("Additional Symptoms") {
                Toggle("Wake-up Headache", isOn: $hasWakeUpHeadache)
                Toggle("Tinnitus", isOn: $hasTinnitus)
                Toggle("Vertigo", isOn: $hasVertigo)
            }
            
            Section("Triggers") {
                TriggerSelectionView(selectedTriggers: $selectedTriggers)
            }
            
            Section("Medications") {
                MedicationSelectionView(selectedMedications: $selectedMedications)
            }
            
            Section("Impact") {
                Toggle("Missed Work", isOn: $missedWork)
                Toggle("Missed School", isOn: $missedSchool)
                Toggle("Missed Events", isOn: $missedEvents)
            }
            
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }
        }
        // ... rest of the view ...
    }
    
    private func playPainLevelHaptic(_ level: Int) {
        switch level {
        case 1...3:
            WKInterfaceDevice.current().play(.success)
        case 4...6:
            WKInterfaceDevice.current().play(.click)
        case 7...8:
            WKInterfaceDevice.current().play(.directionUp)
        case 9...10:
            WKInterfaceDevice.current().play(.notification)
        default:
            break
        }
    }
} 