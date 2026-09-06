import SwiftUI

struct AboutView: View {
    @ScaledMetric(relativeTo: .title) private var headshotSize: CGFloat = 128

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = info?["CFBundleVersion"] as? String {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileHero
                    biographyCard
                    evidenceCard
                    privacyCard
                    practiceCard
                    footer
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About")
        }
    }

    // MARK: - Hero

    private var profileHero: some View {
        VStack(spacing: 14) {
            Image("headshot")
                .resizable()
                .scaledToFill()
                .frame(width: headshotSize, height: headshotSize)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Vincent S. DeOrchis")
                    .font(.custom("Optima-Bold", size: 26, relativeTo: .title))
                Text("M.D., M.S., F.A.A.N.")
                    .font(.custom("Optima-Regular", size: 17, relativeTo: .body))
                    .opacity(0.92)
                Text("Board-Certified Neurologist")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.85)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)

            Text("Creator of Headway: Migraine Monitor")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(AboutPalette.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Biography

    private var biographyCard: some View {
        AboutCard(title: "Meet Dr. DeOrchis", systemImage: "person.text.rectangle") {
            Text("Headway: Migraine Monitor was created by Vincent S. DeOrchis, M.D., M.S., F.A.A.N., a board-certified neurologist and Managing Partner of Neurological Associates of Long Island, P.C., where he specializes in Clinical Neurophysiology and Neuromuscular Disorders.")
                .font(.callout)
                .lineSpacing(3)

            AboutFactRow(
                title: "Education & Training",
                systemImage: "graduationcap.fill",
                tint: AboutPalette.steelBlue,
                text: "Studied Neural Science at New York University and earned a Master\u{2019}s in Physiology and Biophysics from Georgetown University before receiving his medical degree from SUNY Downstate College of Medicine. Completed his Neurology residency at Albert Einstein College of Medicine\u{2019}s Montefiore Medical Center, where he served as Chief Resident, followed by a fellowship in Clinical Neurophysiology and Neuromuscular Disease."
            )

            AboutFactRow(
                title: "Recognition & Research",
                systemImage: "rosette",
                tint: .orange,
                text: "A Fellow of the American Academy of Neurology, recognized as a Castle Connolly Top Doctor and the only neurologist in Nassau County named to Super Doctors 2025 by The New York Times. His research has been published in Headache, Neurology, Muscle & Nerve, and other peer-reviewed journals, and he serves as a principal investigator on numerous clinical trials."
            )

            AboutFactRow(
                title: "Leadership & Teaching",
                systemImage: "building.columns.fill",
                tint: .teal,
                text: "Director of Neurology and Stroke Director at St. Francis Hospital and Heart Center, and Clinical Assistant Professor of Neurology at Hofstra Medical School."
            )

            AboutFactRow(
                title: "Digital Health",
                systemImage: "cpu.fill",
                tint: .purple,
                text: "Driven by a passion for clinical technology, Dr. DeOrchis has developed several digital health tools beyond Headway, including iFell, which records heart rate at the moment of a fall to help identify cardiovascular causes, and BrainMetrix, an analytics platform for quantitative brain MRI volumetric analysis. He also holds a patent pending for an avatar-assisted telemedicine platform and partnered with Fujifilm to bring the first Synergy Series MRI system in the nation to his practice. Headway and iFell are available free on the Apple App Store."
            )
        }
    }

    // MARK: - Evidence

    private var evidenceCard: some View {
        AboutCard(title: "Why Keep a Headache Diary?", systemImage: "text.book.closed.fill") {
            Text("Maintaining a headache diary is a well-established method for identifying and managing headache symptoms and triggers. Further information can be found at the American Migraine Foundation.")
                .font(.callout)
                .lineSpacing(3)

            if let url = AboutReference.americanMigraineFoundationURL {
                Link(destination: url) {
                    Label("American Migraine Foundation", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityHint("Opens the American Migraine Foundation website.")
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(AboutReference.citations) { citation in
                    Link(destination: citation.url) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(citation.marker)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AboutPalette.steelBlue)
                                .frame(width: 16, alignment: .leading)
                            Text(citation.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(citation.accessibilityLabel)
                    .accessibilityHint("Opens the article on PubMed.")
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        AboutCard(title: "Your Privacy", systemImage: "lock.shield.fill", tint: .green) {
            Text("All data entered into Headway is stored locally on your device and never transmitted to a third party. Data may optionally be preserved to your personal Apple iCloud account.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Link(destination: AppContactInfo.privacyPolicyURL) {
                Label("View Privacy Policy", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("View privacy policy")
            .accessibilityHint("Opens the full Headway privacy policy in your default browser.")
        }
    }

    // MARK: - Practice

    private var practiceCard: some View {
        NavigationLink {
            NeurologicalAssociatesView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AboutPalette.heroGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Neurological Associates of Long Island")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Our practice, location, and contact details")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .aboutSurface()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Headway: Migraine Monitor")
                .font(.custom("Optima-Regular", size: 15, relativeTo: .subheadline))
            Text(versionString)
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Building blocks

enum AboutPalette {
    static let steelBlue = Color(red: 68/255, green: 130/255, blue: 180/255)
    static let deepBlue = Color(red: 38/255, green: 84/255, blue: 132/255)

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [steelBlue, deepBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct AboutSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}

extension View {
    func aboutSurface() -> some View {
        modifier(AboutSurface())
    }
}

private struct AboutCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = AboutPalette.steelBlue
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .aboutSurface()
    }
}

private struct AboutFactRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - References

private struct AboutCitation: Identifiable {
    let marker: String
    let text: String
    let url: URL
    let accessibilityLabel: String

    var id: String { marker }
}

private enum AboutReference {
    static let americanMigraineFoundationURL = URL(string: "https://americanmigrainefoundation.org")

    static let citations: [AboutCitation] = [
        (
            marker: "1",
            text: "van Casteren DS, et al. E-diary use in clinical headache practice: A prospective observational study. Cephalalgia. 2021.",
            urlString: "https://pubmed.ncbi.nlm.nih.gov/33938248/",
            accessibilityLabel: "Reference 1: van Casteren and colleagues, E-diary use in clinical headache practice, Cephalalgia, 2021"
        ),
        (
            marker: "2",
            text: "Minen MT, et al. Headache clinicians\u{2019} perspectives on the remote monitoring of patients\u{2019} electronic diary data: A qualitative study. Headache. 2023.",
            urlString: "https://pubmed.ncbi.nlm.nih.gov/37313636/",
            accessibilityLabel: "Reference 2: Minen and colleagues, Headache clinicians\u{2019} perspectives on remote monitoring of electronic diary data, Headache, 2023"
        )
    ].compactMap { entry -> AboutCitation? in
        guard let url = URL(string: entry.urlString) else { return nil }
        return AboutCitation(marker: entry.marker, text: entry.text, url: url, accessibilityLabel: entry.accessibilityLabel)
    }
}

#Preview {
    AboutView()
}
