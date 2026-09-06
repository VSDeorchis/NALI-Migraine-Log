import SwiftUI

struct NeurologicalAssociatesView: View {
    @Environment(\.openURL) private var openURL

    private let practiceName = "Neurological Associates of Long Island, P.C."
    private let streetAddress = "1991 Marcus Avenue"
    private let suite = "Suite 110"
    private let cityStateZip = "Lake Success, NY 11042"
    private let phoneNumber = "(516) 466-4700"
    private let faxNumber = "(516) 466-4810"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroImage
                aboutCard
                contactCard
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Our Practice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroImage: some View {
        Image("about_image")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(practiceName)
                    .font(.custom("Optima-Bold", size: 18, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(14)
            }
            .accessibilityLabel("Photograph of the Neurological Associates of Long Island building at sunset")
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("About Us")
                    .font(.headline)
            } icon: {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(AboutPalette.steelBlue)
            }
            .accessibilityAddTraits(.isHeader)

            Text("Neurological Associates of Long Island has been providing comprehensive, compassionate, and innovative neurologic care to our community for over 50 years. Our team of 10 board-certified neurologists covers virtually every aspect of neurologic disease, supported by extensive on-site diagnostic testing, physical therapy, and infusion services. We are also actively engaged in clinical research, investigating novel therapies for a variety of neurologic conditions.")
                .font(.callout)
                .lineSpacing(3)

            Text("In our continued effort to improve patient outcomes, we have created Headway. This app empowers patients to accurately track their headache symptoms, medications, and triggers, offering a clearer picture for both patients and physicians to guide treatment plans and improve headache management. At Neurological Associates, we remain committed to delivering timely appointments, assisting with insurance complexities, and ensuring every visit is a comfortable and informative experience.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .aboutSurface()
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text("Contact Us")
                    .font(.headline)
            } icon: {
                Image(systemName: "phone.bubble.fill")
                    .foregroundStyle(AboutPalette.steelBlue)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 10)

            ContactRow(systemImage: "mappin.and.ellipse", title: "Address", detail: "\(streetAddress), \(suite)\n\(cityStateZip)", action: openMaps)
                .accessibilityHint("Opens the practice address in Maps.")
            Divider().padding(.leading, 42)
            ContactRow(systemImage: "phone.fill", title: "Phone", detail: phoneNumber, action: callPhone)
                .accessibilityHint("Calls the practice.")
            Divider().padding(.leading, 42)
            ContactRow(systemImage: "printer.fill", title: "Fax", detail: faxNumber, action: nil)
            Divider().padding(.leading, 42)
            ContactRow(systemImage: "globe", title: "Website", detail: "www.neuroli.com") {
                openURL(AppContactInfo.websiteURL)
            }
            .accessibilityHint("Opens the practice website in your browser.")
        }
        .padding(18)
        .aboutSurface()
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
    let systemImage: String
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AboutPalette.steelBlue)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(isLink ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if isLink {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        NeurologicalAssociatesView()
    }
}
