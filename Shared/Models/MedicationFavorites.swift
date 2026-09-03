import Foundation
import Observation

/// User-pinned medications, shown at the top of every medication picker.
/// Stored as raw values in `UserDefaults`; no health content is involved.
@MainActor
@Observable
final class MedicationFavorites {
    static let shared = MedicationFavorites()

    private static let key = "medication.pinnedFavorites"

    private(set) var pinned: [MigraineMedication]

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        pinned = stored.compactMap(MigraineMedication.init(rawValue:))
        self.defaults = defaults
    }

    private let defaults: UserDefaults

    func isPinned(_ medication: MigraineMedication) -> Bool {
        pinned.contains(medication)
    }

    func toggle(_ medication: MigraineMedication) {
        if let index = pinned.firstIndex(of: medication) {
            pinned.remove(at: index)
        } else {
            pinned.append(medication)
        }
        defaults.set(pinned.map(\.rawValue), forKey: Self.key)
    }

    /// Pinned medications first (in pin order), then the rest in canonical order.
    var orderedMedications: [MigraineMedication] {
        pinned + MigraineMedication.allCases.filter { !pinned.contains($0) }
    }
}
