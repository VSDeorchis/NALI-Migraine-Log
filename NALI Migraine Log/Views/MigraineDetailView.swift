import SwiftUI
import CoreData

struct MigraineDetailView: View {
    let migraine: MigraineEvent
    @ObservedObject var viewModel: MigraineViewModel
    @ObservedObject private var settings = SettingsManager.shared
    let dismiss: () -> Void
    
    // State for form fields
    @State private var startTime: Date
    @State private var endTime: Date?
    @State private var painLevel: Int
    @State private var location: String
    
    // Trigger booleans
    @State private var isTriggerStress: Bool
    @State private var isTriggerLackOfSleep: Bool
    @State private var isTriggerDehydration: Bool
    @State private var isTriggerWeather: Bool
    @State private var isTriggerHormones: Bool
    @State private var isTriggerAlcohol: Bool
    @State private var isTriggerCaffeine: Bool
    @State private var isTriggerFood: Bool
    @State private var isTriggerExercise: Bool
    @State private var isTriggerScreenTime: Bool
    @State private var isTriggerOther: Bool
    
    // Medication booleans
    @State private var tookIbuprofin: Bool
    @State private var tookExcedrin: Bool
    @State private var tookTylenol: Bool
    @State private var tookSumatriptan: Bool
    @State private var tookRizatriptan: Bool
    @State private var tookNaproxen: Bool
    @State private var tookFrovatriptan: Bool
    @State private var tookNaratriptan: Bool
    @State private var tookNurtec: Bool
    @State private var tookSymbravo: Bool
    @State private var tookUbrelvy: Bool
    @State private var tookReyvow: Bool
    @State private var tookTrudhesa: Bool
    @State private var tookElyxyb: Bool
    @State private var tookOther: Bool
    @State private var tookEletriptan: Bool = false
    
    // Other booleans
    @State private var hasAura: Bool
    @State private var hasPhotophobia: Bool
    @State private var hasPhonophobia: Bool
    @State private var hasNausea: Bool
    @State private var hasVomiting: Bool
    @State private var hasWakeUpHeadache: Bool
    @State private var hasTinnitus: Bool
    @State private var hasVertigo: Bool
    @State private var missedWork: Bool
    @State private var missedSchool: Bool
    @State private var missedEvents: Bool
    @State private var notes: String
    @State private var showingWeatherLocationEditor = false
    
    // Constants for picker options
    private let locations = [
        "Frontal",
        "Whole Head",
        "Left Side",
        "Right Side",
        "Occipital/Back of Head"
    ]
    
    init(migraine: MigraineEvent, viewModel: MigraineViewModel, dismiss: @escaping () -> Void) {
        self.migraine = migraine
        self.viewModel = viewModel
        self.dismiss = dismiss
        
        // Initialize state with migraine data
        _startTime = State(initialValue: migraine.startTime ?? Date())
        _endTime = State(initialValue: migraine.endTime)
        _painLevel = State(initialValue: Int(migraine.painLevel))
        _location = State(initialValue: migraine.location ?? "")
        
        // Initialize trigger booleans
        _isTriggerStress = State(initialValue: migraine.isTriggerStress)
        _isTriggerLackOfSleep = State(initialValue: migraine.isTriggerLackOfSleep)
        _isTriggerDehydration = State(initialValue: migraine.isTriggerDehydration)
        _isTriggerWeather = State(initialValue: migraine.isTriggerWeather)
        _isTriggerHormones = State(initialValue: migraine.isTriggerHormones)
        _isTriggerAlcohol = State(initialValue: migraine.isTriggerAlcohol)
        _isTriggerCaffeine = State(initialValue: migraine.isTriggerCaffeine)
        _isTriggerFood = State(initialValue: migraine.isTriggerFood)
        _isTriggerExercise = State(initialValue: migraine.isTriggerExercise)
        _isTriggerScreenTime = State(initialValue: migraine.isTriggerScreenTime)
        _isTriggerOther = State(initialValue: migraine.isTriggerOther)
        
        // Initialize medication booleans
        _tookIbuprofin = State(initialValue: migraine.tookIbuprofin)
        _tookExcedrin = State(initialValue: migraine.tookExcedrin)
        _tookTylenol = State(initialValue: migraine.tookTylenol)
        _tookSumatriptan = State(initialValue: migraine.tookSumatriptan)
        _tookRizatriptan = State(initialValue: migraine.tookRizatriptan)
        _tookNaproxen = State(initialValue: migraine.tookNaproxen)
        _tookFrovatriptan = State(initialValue: migraine.tookFrovatriptan)
        _tookNaratriptan = State(initialValue: migraine.tookNaratriptan)
        _tookNurtec = State(initialValue: migraine.tookNurtec)
        _tookSymbravo = State(initialValue: migraine.tookSymbravo)
        _tookUbrelvy = State(initialValue: migraine.tookUbrelvy)
        _tookReyvow = State(initialValue: migraine.tookReyvow)
        _tookTrudhesa = State(initialValue: migraine.tookTrudhesa)
        _tookElyxyb = State(initialValue: migraine.tookElyxyb)
        _tookOther = State(initialValue: migraine.tookOther)
        _tookEletriptan = State(initialValue: migraine.tookEletriptan)
        
        // Initialize other booleans
        _hasAura = State(initialValue: migraine.hasAura)
        _hasPhotophobia = State(initialValue: migraine.hasPhotophobia)
        _hasPhonophobia = State(initialValue: migraine.hasPhonophobia)
        _hasNausea = State(initialValue: migraine.hasNausea)
        _hasVomiting = State(initialValue: migraine.hasVomiting)
        _hasWakeUpHeadache = State(initialValue: migraine.hasWakeUpHeadache)
        _hasTinnitus = State(initialValue: migraine.hasTinnitus)
        _hasVertigo = State(initialValue: migraine.hasVertigo)
        _missedWork = State(initialValue: migraine.missedWork)
        _missedSchool = State(initialValue: migraine.missedSchool)
        _missedEvents = State(initialValue: migraine.missedEvents)
        _notes = State(initialValue: migraine.notes ?? "")
    }
    
    var body: some View {
        Form {
            // Weather data section
            Section(header: 
                Label("WEATHER DATA", systemImage: "cloud.sun.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            ) {
                if migraine.hasWeatherData {
                    // Show current weather data
                    HStack {
                        Image(systemName: weatherIconForCode(Int(migraine.weatherCode)))
                            .foregroundColor(weatherIconColor(for: migraine.weatherCode))
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(WeatherService.weatherCondition(for: Int(migraine.weatherCode)))
                                .font(.headline)
                            Text(settings.formatTemperature(migraine.weatherTemperature))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            showingWeatherLocationEditor = true
                        }) {
                            Label("Edit", systemImage: "location.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack {
                        Text("Pressure Change")
                        Spacer()
                        Text(settings.formatPressureChange(migraine.weatherPressureChange24h))
                            .foregroundColor(pressureChangeColor(migraine.weatherPressureChange24h))
                    }
                    .font(.caption)
                } else {
                    // No weather data
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Weather Data Unavailable")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Weather data wasn't collected for this entry")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button(action: {
                                    Task {
                                        await viewModel.retryWeatherFetch(for: migraine)
                                    }
                                }) {
                                    Label("Use Current Location", systemImage: "location.fill")
                                }
                                Button(action: {
                                    showingWeatherLocationEditor = true
                                }) {
                                    Label("Custom Location", systemImage: "mappin.and.ellipse")
                                }
                            } label: {
                                if viewModel.weatherFetchStatus == .fetching {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Label("Fetch Weather", systemImage: "arrow.clockwise")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.weatherFetchStatus == .fetching)
                        }
                        
                        // Note about location permission
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption2)
                            Text("When you tap 'Fetch Weather', iOS will ask for location permission. Tap 'Allow Once' to fetch weather data for this entry.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(.systemBlue).opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Pain Details Section
            Section(header: 
                Label("PAIN DETAILS", systemImage: "thermometer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            ) {
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
                        get: { endTime ?? startTime },
                        set: { endTime = $0 }
                    ))
                }
                PainSlider(value: Binding(
                    get: { Int16(painLevel) },
                    set: { painLevel = Int($0) }
                ))
                Picker("Location", selection: $location) {
                    ForEach(locations, id: \.self) { location in
                        Text(location).tag(location)
                    }
                }
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Primary Symptoms Section
            Section(header: 
                Label("PRIMARY SYMPTOMS", systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)
            ) {
                Toggle("Aura", isOn: $hasAura)
                Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                Toggle("Nausea", isOn: $hasNausea)
                Toggle("Vomiting", isOn: $hasVomiting)
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Additional Symptoms Section
            Section(header: 
                Label("ADDITIONAL SYMPTOMS", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)
            ) {
                Toggle("Wake-up Headache", isOn: $hasWakeUpHeadache)
                Toggle("Tinnitus", isOn: $hasTinnitus)
                Toggle("Vertigo", isOn: $hasVertigo)
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Triggers Section
            Section(header: 
                Label("TRIGGERS", systemImage: "bolt.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
            ) {
                TriggerSelectionView(isTriggerStress: $isTriggerStress, isTriggerLackOfSleep: $isTriggerLackOfSleep, isTriggerDehydration: $isTriggerDehydration, isTriggerWeather: $isTriggerWeather, isTriggerHormones: $isTriggerHormones, isTriggerAlcohol: $isTriggerAlcohol, isTriggerCaffeine: $isTriggerCaffeine, isTriggerFood: $isTriggerFood, isTriggerExercise: $isTriggerExercise, isTriggerScreenTime: $isTriggerScreenTime, isTriggerOther: $isTriggerOther)
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Medications Section
            Section(header: 
                Label("MEDICATIONS", systemImage: "pills.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
            ) {
                MedicationSelectionView(tookIbuprofin: $tookIbuprofin, tookExcedrin: $tookExcedrin, tookTylenol: $tookTylenol, tookSumatriptan: $tookSumatriptan, tookRizatriptan: $tookRizatriptan, tookNaproxen: $tookNaproxen, tookFrovatriptan: $tookFrovatriptan, tookNaratriptan: $tookNaratriptan, tookNurtec: $tookNurtec, tookSymbravo: $tookSymbravo, tookUbrelvy: $tookUbrelvy, tookReyvow: $tookReyvow, tookTrudhesa: $tookTrudhesa, tookElyxyb: $tookElyxyb, tookOther: $tookOther, tookEletriptan: $tookEletriptan)
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Impact Section
            Section(header: 
                Label("IMPACT", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)
            ) {
                Toggle("Missed Work", isOn: $missedWork)
                Toggle("Missed School", isOn: $missedSchool)
                Toggle("Missed Events", isOn: $missedEvents)
            }
            .listRowBackground(Color(.systemGray6).opacity(0.5))
            
            // Notes Section
            Section(header: 
                Label("NOTES", systemImage: "note.text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)
            ) {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }
            .listRowBackground(Color(.systemGray6).opacity(0.2))
        }
        .formStyle(GroupedFormStyle())
        .navigationTitle("Edit Migraine")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingWeatherLocationEditor) {
            WeatherLocationEditorView(migraine: migraine, viewModel: viewModel)
        }
        .toolbar(content: {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await viewModel.updateMigraine(
                            migraine,
                            startTime: startTime,
                            endTime: endTime,
                            painLevel: Int16(painLevel),
                            location: location,
                            isTriggerStress: isTriggerStress,
                            isTriggerLackOfSleep: isTriggerLackOfSleep,
                            isTriggerDehydration: isTriggerDehydration,
                            isTriggerWeather: isTriggerWeather,
                            isTriggerHormones: isTriggerHormones,
                            isTriggerAlcohol: isTriggerAlcohol,
                            isTriggerCaffeine: isTriggerCaffeine,
                            isTriggerFood: isTriggerFood,
                            isTriggerExercise: isTriggerExercise,
                            isTriggerScreenTime: isTriggerScreenTime,
                            isTriggerOther: isTriggerOther,
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
                            tookIbuprofin: tookIbuprofin,
                            tookExcedrin: tookExcedrin,
                            tookTylenol: tookTylenol,
                            tookSumatriptan: tookSumatriptan,
                            tookRizatriptan: tookRizatriptan,
                            tookNaproxen: tookNaproxen,
                            tookFrovatriptan: tookFrovatriptan,
                            tookNaratriptan: tookNaratriptan,
                            tookNurtec: tookNurtec,
                            tookSymbravo: tookSymbravo,
                            tookUbrelvy: tookUbrelvy,
                            tookReyvow: tookReyvow,
                            tookTrudhesa: tookTrudhesa,
                            tookElyxyb: tookElyxyb,
                            tookOther: tookOther,
                            tookEletriptan: tookEletriptan,
                            notes: notes
                        )
                        dismiss()
                    }
                }
            }
        })
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
    
    private func pressureChangeColor(_ change: Double) -> Color {
        let absChange = abs(change)
        if absChange < 2 {
            return .green
        } else if absChange < 5 {
            return .orange
        } else {
            return .red
        }
    }
    
    // Local copy of weather icon mapping
    private func weatherIconForCode(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.max.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75: return "cloud.snow.fill"
        case 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.rain.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    
    private func weatherIconColor(for code: Int16) -> Color {
        let colorName = WeatherService.weatherColor(for: Int(code))
        switch colorName {
        case "yellow": return .yellow
        case "orange": return .orange
        case "gray": return .gray
        case "blue": return .blue
        case "cyan": return .cyan
        case "purple": return .purple
        default: return .gray
        }
    }
}

struct TriggerSelectionView: View {
    @Binding var isTriggerStress: Bool
    @Binding var isTriggerLackOfSleep: Bool
    @Binding var isTriggerDehydration: Bool
    @Binding var isTriggerWeather: Bool
    @Binding var isTriggerHormones: Bool
    @Binding var isTriggerAlcohol: Bool
    @Binding var isTriggerCaffeine: Bool
    @Binding var isTriggerFood: Bool
    @Binding var isTriggerExercise: Bool
    @Binding var isTriggerScreenTime: Bool
    @Binding var isTriggerOther: Bool
    
    private let triggers = [
        "Stress",
        "Lack of Sleep",
        "Dehydration",
        "Weather",
        "Menstrual",
        "Alcohol",
        "Caffeine",
        "Food",
        "Exercise",
        "Screen Time",
        "Other"
    ]
    
    var body: some View {
        ForEach(triggers, id: \.self) { trigger in
            Toggle(trigger, isOn: Binding(
                get: {
                    trigger == "Stress" ? isTriggerStress :
                    trigger == "Lack of Sleep" ? isTriggerLackOfSleep :
                    trigger == "Dehydration" ? isTriggerDehydration :
                    trigger == "Weather" ? isTriggerWeather :
                    trigger == "Menstrual" ? isTriggerHormones :
                    trigger == "Alcohol" ? isTriggerAlcohol :
                    trigger == "Caffeine" ? isTriggerCaffeine :
                    trigger == "Food" ? isTriggerFood :
                    trigger == "Exercise" ? isTriggerExercise :
                    trigger == "Screen Time" ? isTriggerScreenTime :
                    isTriggerOther
                },
                set: { isSelected in
                    withAnimation {
                        if isSelected {
                            switch trigger {
                            case "Stress": isTriggerStress = true
                            case "Lack of Sleep": isTriggerLackOfSleep = true
                            case "Dehydration": isTriggerDehydration = true
                            case "Weather": isTriggerWeather = true
                            case "Menstrual": isTriggerHormones = true
                            case "Alcohol": isTriggerAlcohol = true
                            case "Caffeine": isTriggerCaffeine = true
                            case "Food": isTriggerFood = true
                            case "Exercise": isTriggerExercise = true
                            case "Screen Time": isTriggerScreenTime = true
                            default: isTriggerOther = true
                            }
                        } else {
                            switch trigger {
                            case "Stress": isTriggerStress = false
                            case "Lack of Sleep": isTriggerLackOfSleep = false
                            case "Dehydration": isTriggerDehydration = false
                            case "Weather": isTriggerWeather = false
                            case "Menstrual": isTriggerHormones = false
                            case "Alcohol": isTriggerAlcohol = false
                            case "Caffeine": isTriggerCaffeine = false
                            case "Food": isTriggerFood = false
                            case "Exercise": isTriggerExercise = false
                            case "Screen Time": isTriggerScreenTime = false
                            default: isTriggerOther = false
                            }
                        }
                    }
                }
            ))
        }
    }
}

struct MedicationSelectionView: View {
    @Binding var tookIbuprofin: Bool
    @Binding var tookExcedrin: Bool
    @Binding var tookTylenol: Bool
    @Binding var tookSumatriptan: Bool
    @Binding var tookRizatriptan: Bool
    @Binding var tookNaproxen: Bool
    @Binding var tookFrovatriptan: Bool
    @Binding var tookNaratriptan: Bool
    @Binding var tookNurtec: Bool
    @Binding var tookSymbravo: Bool
    @Binding var tookUbrelvy: Bool
    @Binding var tookReyvow: Bool
    @Binding var tookTrudhesa: Bool
    @Binding var tookElyxyb: Bool
    @Binding var tookOther: Bool
    @Binding var tookEletriptan: Bool
    
    private let medications = [
        "Tylenol (acetaminophen)",
        "Ibuprofen",
        "Naproxen",
        "Excedrin",
        "Ubrelvy (ubrogepant)",
        "Nurtec (rimegepant)",
        "Symbravo",
        "Sumatriptan",
        "Rizatriptan",
        "Eletriptan",
        "Naratriptan",
        "Frovatriptan",
        "Reyvow (lasmiditan)",
        "Trudhesa (dihydroergotamine)",
        "Elyxyb",
        "Other"
    ]
    
    var body: some View {
        ForEach(medications, id: \.self) { medication in
            Toggle(medication, isOn: Binding(
                get: {
                    switch medication {
                    case "Tylenol (acetaminophen)": return tookTylenol
                    case "Ibuprofen": return tookIbuprofin
                    case "Naproxen": return tookNaproxen
                    case "Excedrin": return tookExcedrin
                    case "Ubrelvy (ubrogepant)": return tookUbrelvy
                    case "Nurtec (rimegepant)": return tookNurtec
                    case "Symbravo": return tookSymbravo
                    case "Sumatriptan": return tookSumatriptan
                    case "Rizatriptan": return tookRizatriptan
                    case "Eletriptan": return tookEletriptan
                    case "Naratriptan": return tookNaratriptan
                    case "Frovatriptan": return tookFrovatriptan
                    case "Reyvow (lasmiditan)": return tookReyvow
                    case "Trudhesa (dihydroergotamine)": return tookTrudhesa
                    case "Elyxyb": return tookElyxyb
                    case "Other": return tookOther
                    default: return false
                    }
                },
                set: { isSelected in
                    withAnimation {
                        switch medication {
                        case "Tylenol (acetaminophen)": tookTylenol = isSelected
                        case "Ibuprofen": tookIbuprofin = isSelected
                        case "Naproxen": tookNaproxen = isSelected
                        case "Excedrin": tookExcedrin = isSelected
                        case "Ubrelvy (ubrogepant)": tookUbrelvy = isSelected
                        case "Nurtec (rimegepant)": tookNurtec = isSelected
                        case "Symbravo": tookSymbravo = isSelected
                        case "Sumatriptan": tookSumatriptan = isSelected
                        case "Rizatriptan": tookRizatriptan = isSelected
                        case "Eletriptan": tookEletriptan = isSelected
                        case "Naratriptan": tookNaratriptan = isSelected
                        case "Frovatriptan": tookFrovatriptan = isSelected
                        case "Reyvow (lasmiditan)": tookReyvow = isSelected
                        case "Trudhesa (dihydroergotamine)": tookTrudhesa = isSelected
                        case "Elyxyb": tookElyxyb = isSelected
                        case "Other": tookOther = isSelected
                        default: break
                        }
                    }
                }
            ))
        }
    }
} 