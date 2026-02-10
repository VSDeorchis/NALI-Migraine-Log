struct WatchNewMigraineView: View {
    // ... keep existing properties except selectedTriggers and selectedMedications ...
    @State private var startTime = Date()
    @State private var endTime: Date?
    @State private var painLevel: Int16 = 5
    @State private var location = "Frontal"
    
    // Triggers as booleans
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
    
    // Medications as booleans
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
    @State private var tookOther = false
    
    // ... keep other existing properties ...
    
    var body: some View {
        TabView(selection: $currentSection) {
            // ... keep Pain Details and Symptoms sections ...
            
            // Triggers Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Stress", isOn: $isTriggerStress)
                    Toggle("Lack of Sleep", isOn: $isTriggerLackOfSleep)
                    Toggle("Dehydration", isOn: $isTriggerDehydration)
                    Toggle("Weather", isOn: $isTriggerWeather)
                    Toggle("Menstrual", isOn: $isTriggerHormones)
                    Toggle("Alcohol", isOn: $isTriggerAlcohol)
                    Toggle("Caffeine", isOn: $isTriggerCaffeine)
                    Toggle("Food", isOn: $isTriggerFood)
                    Toggle("Exercise", isOn: $isTriggerExercise)
                    Toggle("Screen Time", isOn: $isTriggerScreenTime)
                    Toggle("Other", isOn: $isTriggerOther)
                }
                .padding()
            }
            .tag(1)
            
            // ... keep Quality of Life section ...
            
            // Medications Section
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Ibuprofen", isOn: $tookIbuprofin)
                    Toggle("Excedrin", isOn: $tookExcedrin)
                    Toggle("Tylenol", isOn: $tookTylenol)
                    Toggle("Sumatriptan", isOn: $tookSumatriptan)
                    Toggle("Rizatriptan", isOn: $tookRizatriptan)
                    Toggle("Naproxen", isOn: $tookNaproxen)
                    Toggle("Frovatriptan", isOn: $tookFrovatriptan)
                    Toggle("Naratriptan", isOn: $tookNaratriptan)
                    Toggle("Nurtec", isOn: $tookNurtec)
                    Toggle("Ubrelvy", isOn: $tookUbrelvy)
                    Toggle("Reyvow", isOn: $tookReyvow)
                    Toggle("Trudhesa", isOn: $tookTrudhesa)
                    Toggle("Elyxyb", isOn: $tookElyxyb)
                    Toggle("Other", isOn: $tookOther)
                }
                .padding()
            }
            .tag(4)
            
            // ... keep Notes section and Save Button ...
        }
        .tabViewStyle(.page)
        .navigationTitle("New Entry")
    }
    
    private func saveMigraine() {
        Task {
            await viewModel.addMigraine(
                startTime: startTime,
                endTime: endTime,
                painLevel: painLevel,
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
                tookOther: tookOther,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        }
    }
} 