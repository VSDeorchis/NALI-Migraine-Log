import SwiftUI

struct NeurologicalAssociatesView: View {
    @Environment(\.openURL) private var openURL

    private let streetAddress = "1991 Marcus Avenue"
    private let suite = "Suite 110"
    private let cityStateZip = "Lake Success, NY 11042"
    private let phoneNumber = "(516) 466-4700"
    private let faxNumber = "(516) 466-4810"

    var body: some View {
        List {
            photoSection
            aboutSection
            contactSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Our Practice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photoSection: some View {
        Section {
            Image("about_image")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Photograph of the Neurological Associates of Long Island building at sunset")
        }
    }

    private var aboutSection: some View {
        Section("Neurological Associates of Long Island, P.C.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Neurological Associates of Long Island has provided comprehensive, compassionate and innovative neurologic care to our community for more than 50 years. Our ten board-certified neurologists cover virtually every aspect of neurologic disease, supported by extensive on-site diagnostic testing, physical therapy and infusion services, and we take an active part in clinical research into new therapies for neurologic conditions.")

                Text("Headway grew out of that work. By making it easy to record symptoms, medications and triggers accurately, it gives patients and physicians a clearer picture to guide treatment. We remain committed to timely appointments, help with insurance and a comfortable, informative visit every time.")
            }
            .font(.callout)
            .padding(.vertical, 4)
        }
    }

    private var contactSection: some View {
        Section("Contact") {
            ContactRow(title: "Address", detail: "\(streetAddress), \(suite)\n\(cityStateZip)", action: openMaps)
                .accessibilityHint("Opens the practice address in Maps.")
            ContactRow(title: "Phone", detail: phoneNumber, action: callPhone)
                .accessibilityHint("Calls the practice.")
            ContactRow(title: "Fax", detail: faxNumber, action: nil)
            ContactRow(title: "Website", detail: "neuroli.com") {
                openURL(AppContactInfo.websiteURL)
            }
            .accessibilityHint("Opens the practice website in your browser.")
        }
    }

    private func openMaps() {
        let address = "\(streetAddress) \(suite) \(cityStateZip)"
        let addressEncoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "maps://?address=\(addressEncoded)") else { return }
        openURL(url)
    }

    private func callPhone() {
        let telephone = phoneNumber.filter(\.isNumber)
        guard let url = URL(string: "tel://\(telephone)") else { return }
        openURL(url)
    }
}

private struct ContactRow: View {
    let title: LocalizedStringKey
    let detail: String
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { rowContent(isLink: true) }
                .buttonStyle(.plain)
        } else {
            rowContent(isLink: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func rowContent(isLink: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.body)
                .foregroundStyle(isLink ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        NeurologicalAssociatesView()
    }
}
