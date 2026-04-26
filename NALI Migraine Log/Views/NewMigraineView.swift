import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

struct NewMigraineView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) var dismiss
    
    /// Used to expand the notes editor on iPad (more canvas for Apple
    /// Pencil scribble) — `Scribble` itself is on by default for any
    /// SwiftUI `TextEditor`, no opt-in required, so all we need is
    /// enough vertical space to actually write into.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var startTime = Date()
    @State private var endTime: Date?
    @State private var painLevel: Int16 = 5
    @State private var location = "Frontal"
    @State private var selectedTriggers: Set<MigraineTrigger> = []
    @State private var hasAura = false
    @State private var hasPhotophobia = false
    @State private var hasPhonophobia = false
    @State private var hasNausea = false
    @State private var hasVomiting = false
    @State private var hasWakeUpHeadache = false
    @State private var hasTinnitus = false
    @State private var hasVertigo = false
    @State private var missedWork = false
    @State private var missedSchool = false
    @State private var missedEvents = false
    @State private var selectedMedications: Set<MigraineMedication> = []
    @State private var notes = ""
    @State private var showingSaveError = false
    @State private var isSaving = false
    @ObservedObject private var healthKit = HealthKitManager.shared
    @State private var healthSnapshot: HealthKitSnapshot?
    @State private var isLoadingHealth = false
    
    private var locationPicker: some View {
        Picker("Location", selection: $location) {
            ForEach(viewModel.locations, id: \.self) { location in
                Text(location).tag(location)
            }
        }
    }
    
    private var triggersSection: some View {
        Section {
            ForEach(MigraineTrigger.allCases) { trigger in
                Toggle(trigger.displayName, isOn: Binding(
                    get: { selectedTriggers.contains(trigger) },
                    set: { isOn in
                        withAnimation {
                            if isOn { selectedTriggers.insert(trigger) }
                            else    { selectedTriggers.remove(trigger) }
                        }
                    }
                ))
            }
        } header: {
            SectionHeader(
                title: "TRIGGERS",
                systemImage: "bolt.fill",
                color: .blue
            )
        }
        .listRowBackground(Color(.systemGray6).opacity(0.5))
    }

    private var medicationsSection: some View {
        Section {
            ForEach(MigraineMedication.allCases) { medication in
                Toggle(medication.fullDisplayName, isOn: Binding(
                    get: { selectedMedications.contains(medication) },
                    set: { isOn in
                        withAnimation {
                            if isOn { selectedMedications.insert(medication) }
                            else    { selectedMedications.remove(medication) }
                        }
                    }
                ))
            }
        } header: {
            SectionHeader(
                title: "MEDICATIONS",
                systemImage: "pill.fill",
                color: .purple
            )
        }
        .listRowBackground(Color(.systemGray6).opacity(0.5))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Weather fetch status banner
                if viewModel.weatherFetchStatus != .idle {
                    weatherStatusBanner
                }
                
                Form {
                    // Health Context Section (live HealthKit data)
                    if healthKit.isAvailable {
                        healthContextSection
                    }
                    
                    // Pain Details Section
                    Section {
                    DatePicker("Start Time", selection: $startTime)
                    Toggle("Add End Time", isOn: Binding(
                        get: { endTime != nil },
                        set: { newValue in
                            if newValue {
                                endTime = endTime ?? startTime
                            } else {
                                endTime = nil
                            }
                        }
                    ))
                    if endTime != nil {
                        DatePicker("End Time", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                    PainSlider(value: $painLevel)
                    locationPicker
                } header: {
                    SectionHeader(
                        title: "PAIN DETAILS",
                        systemImage: "thermometer",
                        color: .blue
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Primary Symptoms Section
                Section {
                    Toggle("Aura", isOn: $hasAura)
                    Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                    Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                    Toggle("Nausea", isOn: $hasNausea)
                    Toggle("Vomiting", isOn: $hasVomiting)
                } header: {
                    SectionHeader(
                        title: "PRIMARY SYMPTOMS",
                        systemImage: "exclamationmark.circle",
                        color: .purple
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Additional Symptoms Section
                Section {
                    Toggle("Wake-up Headache", isOn: $hasWakeUpHeadache)
                    Toggle("Tinnitus", isOn: $hasTinnitus)
                    Toggle("Vertigo", isOn: $hasVertigo)
                } header: {
                    SectionHeader(
                        title: "ADDITIONAL SYMPTOMS",
                        systemImage: "plus.circle",
                        color: .purple
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Triggers Section
                triggersSection
                
                // Medications Section
                medicationsSection
                
                // Impact Section
                Section {
                    Toggle("Missed Work", isOn: $missedWork)
                    Toggle("Missed School", isOn: $missedSchool)
                    Toggle("Missed Events", isOn: $missedEvents)
                } header: {
                    SectionHeader(
                        title: "IMPACT",
                        systemImage: "chart.bar.fill",
                        color: .red
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.5))
                
                // Notes Section
                //
                // The minimum height grows on iPad so Apple Pencil
                // users have enough room to scribble a sentence or
                // two without the editor immediately becoming a
                // scrollable single-line strip. SwiftUI's `TextEditor`
                // already accepts Scribble input automatically — no
                // opt-in modifier exists or is needed.
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: horizontalSizeClass == .regular ? 200 : 100)
                        .accessibilityHint(horizontalSizeClass == .regular
                            ? "Type with the keyboard or write with Apple Pencil"
                            : "Add any additional details about this migraine")
                } header: {
                    SectionHeader(
                        title: "NOTES",
                        systemImage: "note.text",
                        color: .red
                    )
                }
                .listRowBackground(Color(.systemGray6).opacity(0.2))
                }
                .formStyle(.grouped)
                .navigationTitle("New Migraine")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    AppLogger.ui.debug("NewMigraineView appeared")
                }
                .task {
                    await loadHealthData()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Button("Save") {
                                Task { @MainActor in
                                    isSaving = true
                                    
                                    let result = await viewModel.addMigraine(
                                        startTime: startTime,
                                        endTime: endTime,
                                        painLevel: painLevel,
                                        location: location,
                                        triggers: selectedTriggers,
                                        hasAura: hasAura,
                                        hasPhotophobia: hasPhotophobia,
                                        hasPhonophobia: hasPhonophobia,
                                        hasNausea: hasNausea,
                                        hasVomiting: hasVomiting,
                                        hasWakeUpHeadache: hasWakeUpHeadache,
                                        hasTinnitus: hasTinnitus,
                                        hasVertigo: hasVertigo,
                                        missedWork: missedWork,
                                        missedSchool: missedSchool,
                                        missedEvents: missedEvents,
                                        medications: selectedMedications,
                                        notes: notes.isEmpty ? nil : notes
                                    )
                                    
                                    isSaving = false
                                    
                                    if result != nil {
                                        // Success haptic
                                        let notificationFeedback = UINotificationFeedbackGenerator()
                                        notificationFeedback.notificationOccurred(.success)
                                        dismiss()
                                    } else {
                                        // Error haptic
                                        let notificationFeedback = UINotificationFeedbackGenerator()
                                        notificationFeedback.notificationOccurred(.error)
                                        showingSaveError = true
                                    }
                                }
                            }
                        }
                    }
                }
                .alert("Unable to Save", isPresented: $showingSaveError) {
                    Button("Try Again", role: .cancel) { }
                } message: {
                    Text("There was a problem saving your migraine entry. Please check your connection and try again.")
                }
            }
        }
    }
    
    // MARK: - Health Context
    
    private func loadHealthData() async {
        guard healthKit.isAvailable else { return }
        isLoadingHealth = true
        if !healthKit.isAuthorized {
            await healthKit.requestAuthorization()
        }
        if healthKit.isAuthorized {
            healthSnapshot = await healthKit.fetchSnapshot()
        }
        isLoadingHealth = false
    }
    
    private var healthContextSection: some View {
        Section {
            if isLoadingHealth {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Reading health data...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if !healthKit.isAuthorized {
                HStack(spacing: 10) {
                    Image(systemName: "heart.slash")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HealthKit Not Authorized")
                            .font(.subheadline.weight(.medium))
                        Text("Enable in Settings to see health context")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let snapshot = healthSnapshot {
                healthDataGrid(snapshot)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "heart.text.square")
                        .foregroundColor(.secondary)
                    Text("No health data available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            SectionHeader(
                title: "HEALTH CONTEXT",
                systemImage: "heart.fill",
                color: .pink
            )
        } footer: {
            if healthSnapshot != nil {
                Text("Live data from Apple Health — not stored with this entry.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .listRowBackground(Color(.systemGray6).opacity(0.5))
    }
    
    @ViewBuilder
    private func healthDataGrid(_ snapshot: HealthKitSnapshot) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 10) {
            if let sleep = snapshot.sleepHours {
                HealthContextTile(
                    icon: "bed.double.fill",
                    label: "Sleep",
                    value: String(format: "%.1f hrs", sleep),
                    color: sleepColor(sleep)
                )
            }
            
            if let hrv = snapshot.hrv {
                HealthContextTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: String(format: "%.0f ms", hrv),
                    color: hrvColor(hrv)
                )
            }
            
            if let rhr = snapshot.restingHeartRate {
                HealthContextTile(
                    icon: "heart.fill",
                    label: "Resting HR",
                    value: String(format: "%.0f bpm", rhr),
                    color: .red
                )
            }
            
            if let steps = snapshot.steps {
                HealthContextTile(
                    icon: "figure.walk",
                    label: "Steps Yesterday",
                    value: formatSteps(steps),
                    color: stepsColor(steps)
                )
            }
            
            if let days = snapshot.daysSinceMenstruation {
                HealthContextTile(
                    icon: "calendar.circle.fill",
                    label: "Menstrual Cycle",
                    value: "\(days) days ago",
                    color: .purple
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Health Context Helpers
    
    private func sleepColor(_ hours: Double) -> Color {
        if hours < 5 { return .red }
        if hours < 6.5 { return .orange }
        return .green
    }
    
    private func hrvColor(_ hrv: Double) -> Color {
        if hrv < 20 { return .red }
        if hrv < 40 { return .orange }
        return .green
    }
    
    private func stepsColor(_ steps: Int) -> Color {
        if steps < 3000 { return .orange }
        if steps < 7000 { return .blue }
        return .green
    }
    
    private func formatSteps(_ steps: Int) -> String {
        if steps >= 1000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }
    
    private var weatherStatusBanner: some View {
        Group {
            switch viewModel.weatherFetchStatus {
            case .idle:
                EmptyView()
            case .fetching:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Fetching weather data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
            case .success:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Weather data added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
            case .failed:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Weather data unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            case .locationDenied:
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .foregroundColor(.orange)
                    Text("Enable location for weather data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.weatherFetchStatus)
        // Combine the icon + text so VoiceOver hears one statement instead of
        // two, and add `.updatesFrequently` so the active state isn't cached.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(weatherStatusAccessibilityLabel)
    }

    private var weatherStatusAccessibilityLabel: String {
        switch viewModel.weatherFetchStatus {
        case .idle:           return ""
        case .fetching:       return "Fetching weather data"
        case .success:        return "Weather data added"
        case .failed:         return "Weather data unavailable"
        case .locationDenied: return "Location access required for weather data"
        }
    }
    
    private func saveMigraine() {
        Task {
            await viewModel.addMigraine(
                startTime: startTime,
                endTime: endTime,
                painLevel: painLevel,
                location: location,
                triggers: selectedTriggers,
                hasAura: hasAura,
                hasPhotophobia: hasPhotophobia,
                hasPhonophobia: hasPhonophobia,
                hasNausea: hasNausea,
                hasVomiting: hasVomiting,
                hasWakeUpHeadache: hasWakeUpHeadache,
                hasTinnitus: hasTinnitus,
                hasVertigo: hasVertigo,
                missedWork: missedWork,
                missedSchool: missedSchool,
                missedEvents: missedEvents,
                medications: selectedMedications,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        }
    }
}

// Add custom section header style
struct SectionHeader: View {
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(color)
    }
}

// MARK: - Health Context Tile

struct HealthContextTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08))
        )
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    return NewMigraineView(viewModel: MigraineViewModel(context: context))
        .environment(\.managedObjectContext, context)
} 