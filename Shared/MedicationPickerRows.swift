import SwiftUI

/// Toggle rows for every medication, pinned favourites first. Drop inside a
/// `Section`; long-press (or right-click on Mac) a row to pin or unpin it.
struct MedicationPickerRows: View {
    @Binding var selection: Set<MigraineMedication>
    @State private var favorites = MedicationFavorites.shared

    var body: some View {
        ForEach(favorites.orderedMedications) { medication in
            Toggle(isOn: binding(for: medication)) {
                HStack(spacing: 6) {
                    if favorites.isPinned(medication) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.fullDisplayName)
                        if medication != .other {
                            Text(medication.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            #if os(macOS)
            .toggleStyle(.switch)
            #endif
            .contextMenu {
                Button {
                    withAnimation { favorites.toggle(medication) }
                } label: {
                    Label(
                        favorites.isPinned(medication) ? "Unpin" : "Pin to Top",
                        systemImage: favorites.isPinned(medication) ? "pin.slash" : "pin"
                    )
                }
            }
            .accessibilityHint(favorites.isPinned(medication) ? "Pinned. Long press to unpin." : "Long press to pin to top.")
        }
    }

    private func binding(for medication: MigraineMedication) -> Binding<Bool> {
        Binding(
            get: { selection.contains(medication) },
            set: { isOn in
                withAnimation {
                    if isOn { selection.insert(medication) } else { selection.remove(medication) }
                }
            }
        )
    }
}
