import SwiftUI
import CoreData

/// Three-page quick-log form: pain, the wearer's four most-used
/// triggers/symptoms, save. Everything else lives behind "More".
struct WatchNewMigraineView: View {
    @ObservedObject var viewModel: MigraineViewModel
    @Environment(\.dismiss) var dismiss

    @State private var draft = MigraineDraft(
        startTime: Date(),
        endTime: nil,
        painLevel: 5,
        location: "Frontal",
        notes: nil
    )
    @State private var currentSection = 0
    @State private var quickPicks: [QuickPick] = QuickPick.defaults
    @State private var showingMore = false
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable {
        case idle, saving, failed, saved
    }

    private let totalSections = 3

    var body: some View {
        TabView(selection: $currentSection) {
            painPage.tag(0)
            quickPicksPage.tag(1)
            savePage.tag(2)
        }
        .tabViewStyle(.page)
        .navigationTitle("New Entry")
        .interactiveDismissDisabled(saveState == .saving)
        .sheet(isPresented: $showingMore) {
            WatchMigraineDetailsForm(draft: $draft)
        }
        .sensoryFeedback(.success, trigger: saveState) { _, new in new == .saved }
        .sensoryFeedback(.error, trigger: saveState) { _, new in new == .failed }
        .onAppear {
            quickPicks = QuickPick.personal(from: viewModel.migraines)
        }
    }

    // MARK: Pages

    private var painPage: some View {
        VStack(spacing: 8) {
            StepIndicator(current: 0, total: totalSections)

            Text("Pain Level: \(draft.painLevel)")
                .font(.headline)

            Picker("Pain Level", selection: $draft.painLevel) {
                ForEach(Int16(1)...Int16(10), id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Pain level")
            .accessibilityValue("\(draft.painLevel) of 10")
        }
    }

    private var quickPicksPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                StepIndicator(current: 1, total: totalSections)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(quickPicks) { pick in
                        QuickPickButton(
                            title: pick.displayName,
                            isOn: pick.isSelected(in: draft)
                        ) {
                            pick.toggle(in: &draft)
                        }
                    }
                }

                Button {
                    showingMore = true
                } label: {
                    Label(moreLabel, systemImage: "ellipsis.circle")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
    }

    private var moreLabel: String {
        let extra = draft.detailCount(excluding: quickPicks)
        return extra == 0 ? "More…" : "More… (\(extra))"
    }

    private var savePage: some View {
        VStack(spacing: 10) {
            StepIndicator(current: 2, total: totalSections)

            switch saveState {
            case .saving:
                ProgressView("Saving…")

            case .failed:
                Label("Couldn't save", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                Text("Your entry is still here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Try Again") { saveMigraine() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

            case .idle, .saved:
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Save Entry") { saveMigraine() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .font(.title3)
                    .disabled(saveState == .saved)
            }
        }
        .padding(.horizontal, 4)
    }

    private var summary: String {
        let count = draft.detailCount(excluding: [])
        let details = count == 1 ? "1 detail" : "\(count) details"
        return "Pain \(draft.painLevel)/10 · \(details)"
    }

    // MARK: Save

    private func saveMigraine() {
        guard saveState != .saving else { return }
        saveState = .saving
        let draft = draft
        Task { @MainActor in
            let saved = await viewModel.addMigraine(
                startTime: draft.startTime,
                endTime: draft.endTime,
                painLevel: draft.painLevel,
                location: draft.location,
                triggers: draft.triggers,
                hasAura: draft.hasAura,
                hasPhotophobia: draft.hasPhotophobia,
                hasPhonophobia: draft.hasPhonophobia,
                hasNausea: draft.hasNausea,
                hasVomiting: draft.hasVomiting,
                hasWakeUpHeadache: draft.hasWakeUpHeadache,
                hasTinnitus: draft.hasTinnitus,
                hasVertigo: draft.hasVertigo,
                missedWork: draft.missedWork,
                missedSchool: draft.missedSchool,
                missedEvents: draft.missedEvents,
                medications: draft.medications,
                notes: draft.notes?.isEmpty == false ? draft.notes : nil
            )
            guard saved != nil else {
                saveState = .failed
                return
            }
            saveState = .saved
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }
}

// MARK: - Quick picks

/// A trigger or symptom that can be toggled with one tap.
enum QuickPick: Hashable, Identifiable {
    case trigger(MigraineTrigger)
    case symptom(WatchSymptom)

    var id: String {
        switch self {
        case .trigger(let t): return "trigger.\(t.rawValue)"
        case .symptom(let s): return "symptom.\(s.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .trigger(let t): return t.displayName
        case .symptom(let s): return s.displayName
        }
    }

    func isSelected(in draft: MigraineDraft) -> Bool {
        switch self {
        case .trigger(let t): return draft.triggers.contains(t)
        case .symptom(let s): return draft[keyPath: s.keyPath]
        }
    }

    func toggle(in draft: inout MigraineDraft) {
        switch self {
        case .trigger(let t):
            if draft.triggers.contains(t) { draft.triggers.remove(t) } else { draft.triggers.insert(t) }
        case .symptom(let s):
            draft[keyPath: s.keyPath].toggle()
        }
    }

    static let defaults: [QuickPick] = [
        .trigger(.stress), .trigger(.lackOfSleep),
        .symptom(.photophobia), .symptom(.nausea)
    ]

    /// The four picks the wearer has logged most often, falling back to
    /// `defaults` when history is thin.
    static func personal(from migraines: [MigraineEvent], count: Int = 4) -> [QuickPick] {
        var tally: [QuickPick: Int] = [:]
        for migraine in migraines {
            for trigger in migraine.triggers { tally[.trigger(trigger), default: 0] += 1 }
            for symptom in WatchSymptom.allCases where migraine[keyPath: symptom.eventKeyPath] {
                tally[.symptom(symptom), default: 0] += 1
            }
        }
        let ranked = tally
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.id < $1.key.id }
            .map(\.key)
        var picks = Array(ranked.prefix(count))
        for fallback in defaults where picks.count < count && !picks.contains(fallback) {
            picks.append(fallback)
        }
        return picks
    }
}

enum WatchSymptom: String, CaseIterable, Hashable {
    case aura, photophobia, phonophobia, nausea, vomiting, wakeUpHeadache, tinnitus, vertigo

    var displayName: String {
        switch self {
        case .aura: return "Aura"
        case .photophobia: return "Light Sensitivity"
        case .phonophobia: return "Sound Sensitivity"
        case .nausea: return "Nausea"
        case .vomiting: return "Vomiting"
        case .wakeUpHeadache: return "Wake-up Headache"
        case .tinnitus: return "Tinnitus"
        case .vertigo: return "Vertigo"
        }
    }

    var keyPath: WritableKeyPath<MigraineDraft, Bool> {
        switch self {
        case .aura: return \.hasAura
        case .photophobia: return \.hasPhotophobia
        case .phonophobia: return \.hasPhonophobia
        case .nausea: return \.hasNausea
        case .vomiting: return \.hasVomiting
        case .wakeUpHeadache: return \.hasWakeUpHeadache
        case .tinnitus: return \.hasTinnitus
        case .vertigo: return \.hasVertigo
        }
    }

    var eventKeyPath: KeyPath<MigraineEvent, Bool> {
        switch self {
        case .aura: return \.hasAura
        case .photophobia: return \.hasPhotophobia
        case .phonophobia: return \.hasPhonophobia
        case .nausea: return \.hasNausea
        case .vomiting: return \.hasVomiting
        case .wakeUpHeadache: return \.hasWakeUpHeadache
        case .tinnitus: return \.hasTinnitus
        case .vertigo: return \.hasVertigo
        }
    }
}

extension MigraineDraft {
    /// Number of non-default details set, ignoring `excluded` quick picks
    /// so the "More…" badge only counts what isn't visible on the grid.
    func detailCount(excluding excluded: [QuickPick]) -> Int {
        var count = 0
        for trigger in triggers where !excluded.contains(.trigger(trigger)) { count += 1 }
        for symptom in WatchSymptom.allCases where self[keyPath: symptom.keyPath] && !excluded.contains(.symptom(symptom)) {
            count += 1
        }
        count += medications.count
        count += [missedWork, missedSchool, missedEvents].filter { $0 }.count
        if notes?.isEmpty == false { count += 1 }
        return count
    }
}

private struct QuickPickButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .blue : .gray)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Full form ("More…")

struct WatchMigraineDetailsForm: View {
    @Binding var draft: MigraineDraft
    @Environment(\.dismiss) private var dismiss

    private let locations = ["Frontal", "Temporal", "Occipital", "Orbital", "Whole Head"]

    @State private var favorites = MedicationFavorites.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    Picker("Location", selection: $draft.location) {
                        ForEach(locations, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Triggers") {
                    ForEach(MigraineTrigger.allCases) { trigger in
                        Toggle(trigger.displayName, isOn: setBinding($draft.triggers, trigger))
                    }
                }

                Section("Symptoms") {
                    ForEach(WatchSymptom.allCases, id: \.self) { symptom in
                        Toggle(symptom.displayName, isOn: $draft[dynamicMember: symptom.keyPath])
                    }
                }

                Section("Impact") {
                    Toggle("Missed Work", isOn: $draft.missedWork)
                    Toggle("Missed School", isOn: $draft.missedSchool)
                    Toggle("Missed Events", isOn: $draft.missedEvents)
                }

                Section("Medications") {
                    ForEach(favorites.orderedMedications) { medication in
                        Toggle(isOn: setBinding($draft.medications, medication)) {
                            VStack(alignment: .leading) {
                                Text(medication.genericName)
                                if let brand = medication.brandNames.first {
                                    Text(brand)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Add notes", text: notesBinding)
                }
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { draft.notes ?? "" },
            set: { draft.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private func setBinding<T: Hashable>(_ set: Binding<Set<T>>, _ element: T) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(element) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(element) } else { set.wrappedValue.remove(element) }
            }
        )
    }
}

// MARK: - Step Indicator for Watch
struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}
