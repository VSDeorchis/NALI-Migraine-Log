struct WatchNewMigraineView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @Environment(\.dismiss) var dismiss
    
    // Pain details
    @State private var painLevel = 5
    @State private var location = "Frontal"
    
    // Trigger booleans
    @State private var isTriggerStress = false
    @State private var isTriggerLackOfSleep = false
    @State private var isTriggerDehydration = false
    @State private var isTriggerWeather = false
    @State private var isTriggerHormones = false
    @State private var isTriggerAlcohol = false
    @State private var isTriggerCaffeine = false
    @State private var isTriggerFood = false
    @State private var isTriggerExercise = false
    @State private var isTriggerScreenTime = false
    @State private var isTriggerOther = false
    
    // Medication booleans
    @State private var tookIbuprofin = false
    @State private var tookExcedrin = false
    @State private var tookTylenol = false
    @State private var tookSumatriptan = false
    @State private var tookRizatriptan = false
    @State private var tookNaproxen = false
    @State private var tookFrovatriptan = false
    @State private var tookNaratriptan = false
    @State private var tookNurtec = false
    @State private var tookUbrelvy = false
    @State private var tookReyvow = false
    @State private var tookTrudhesa = false
    @State private var tookElyxyb = false
    @State private var tookEletriptan = false
    @State private var tookOther = false
    
    // Other booleans
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
    
    @State private var currentSection = 0
    @State private var feedbackGenerator = WKHapticType.click
    
    var body: some View {
        TabView(selection: $currentSection) {
            // Pain Level Section
            VStack {
                Text("Pain Level: \(painLevel)")
                    .font(.headline)
                Slider(value: .init(
                    get: { Double(painLevel) },
                    set: { newValue in 
                        let oldLevel = painLevel
                        painLevel = Int(newValue)
                        playPainLevelHaptic(oldLevel: oldLevel, newLevel: painLevel)
                    }
                ), in: 1...10, step: 1)
                .tint(painLevelColor(painLevel))
            }
            .tag(0)
            
            // Location Section
            List {
                ForEach(viewModel.locations, id: \.self) { loc in
                    Button(action: { location = loc }) {
                        HStack {
                            Text(loc)
                            if location == loc {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .tag(1)
            
            // Primary Symptoms Section
            List {
                Toggle("Aura", isOn: $hasAura)
                Toggle("Light Sensitivity", isOn: $hasPhotophobia)
                Toggle("Sound Sensitivity", isOn: $hasPhonophobia)
                Toggle("Nausea", isOn: $hasNausea)
                Toggle("Vomiting", isOn: $hasVomiting)
            }
            .tag(2)
            
            // Additional Symptoms Section
            List {
                Toggle("Wake-up Headache", isOn: $hasWakeUpHeadache)
                Toggle("Tinnitus", isOn: $hasTinnitus)
                Toggle("Vertigo", isOn: $hasVertigo)
            }
            .tag(3)
            
            // Triggers Section
            List {
                Toggle("Stress", isOn: $isTriggerStress)
                Toggle("Lack of Sleep", isOn: $isTriggerLackOfSleep)
                Toggle("Dehydration", isOn: $isTriggerDehydration)
                Toggle("Weather", isOn: $isTriggerWeather)
                Toggle("Hormones", isOn: $isTriggerHormones)
                Toggle("Alcohol", isOn: $isTriggerAlcohol)
                Toggle("Caffeine", isOn: $isTriggerCaffeine)
                Toggle("Food", isOn: $isTriggerFood)
                Toggle("Exercise", isOn: $isTriggerExercise)
                Toggle("Screen Time", isOn: $isTriggerScreenTime)
                Toggle("Other", isOn: $isTriggerOther)
            }
            .tag(4)
            
            // Medications Section
            List {
                Toggle("Tylenol (acetaminophen)", isOn: $tookTylenol)
                Toggle("Ibuprofen", isOn: $tookIbuprofin)
                Toggle("Naproxen", isOn: $tookNaproxen)
                Toggle("Excedrin", isOn: $tookExcedrin)
                Toggle("Ubrelvy (ubrogepant)", isOn: $tookUbrelvy)
                Toggle("Nurtec (rimegepant)", isOn: $tookNurtec)
                Toggle("Sumatriptan", isOn: $tookSumatriptan)
                Toggle("Rizatriptan", isOn: $tookRizatriptan)
                Toggle("Eletriptan", isOn: $tookEletriptan)
                Toggle("Naratriptan", isOn: $tookNaratriptan)
                Toggle("Frovatriptan", isOn: $tookFrovatriptan)
                Toggle("Reyvow (lasmiditan)", isOn: $tookReyvow)
                Toggle("Trudhesa (dihydroergotamine)", isOn: $tookTrudhesa)
                Toggle("Elyxyb", isOn: $tookElyxyb)
                Toggle("Other", isOn: $tookOther)
            }
            .tag(5)
            
            // Impact Section
            List {
                Toggle("Missed Work", isOn: $missedWork)
                Toggle("Missed School", isOn: $missedSchool)
                Toggle("Missed Events", isOn: $missedEvents)
            }
            .tag(6)
            
            // Add status view before save button
            VStack {
                SyncStatusView(connectivityManager: connectivityManager)
                    .padding(.bottom)
                
                Button("Save Entry") {
                    saveMigraine()
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .font(.title3)
            }
            .tag(7)
        }
        .tabViewStyle(.page)
        .navigationTitle("New Entry")
    }
    
    private func playPainLevelHaptic(oldLevel: Int, newLevel: Int) {
        if newLevel != oldLevel {
            switch newLevel {
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
    
    private func painLevelColor(_ level: Int) -> Color {
        switch level {
        case 1...3: return .green
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
    
    private func saveMigraine() {
        Task {
            if let migraine = await viewModel.addMigraine(
                startTime: Date(),
                endTime: nil,
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
                tookUbrelvy: tookUbrelvy,
                tookReyvow: tookReyvow,
                tookTrudhesa: tookTrudhesa,
                tookElyxyb: tookElyxyb,
                tookEletriptan: tookEletriptan,
                tookOther: tookOther,
                notes: nil
            ) {
                do {
                    try await connectivityManager.sendMigraineToiOS(migraine)
                    print("Successfully synced migraine to iOS")
                } catch {
                    print("Failed to sync migraine to iOS: \(error)")
                }
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
} 