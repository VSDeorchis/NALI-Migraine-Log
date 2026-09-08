import SwiftUI

struct AboutView: View {
    @ScaledMetric(relativeTo: .title) private var headshotSize: CGFloat = 112

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
            List {
                profileSection
                biographySection
                diarySection
                privacySection
                practiceSection
                versionSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("About")
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section {
            VStack(spacing: 12) {
                Image("headshot")
                    .resizable()
                    .scaledToFill()
                    .frame(width: headshotSize, height: headshotSize)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text("Vincent S. DeOrchis")
                        .font(.custom("Optima-Bold", size: 24, relativeTo: .title2))
                    Text("M.D., M.S., F.A.A.N.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Board-certified neurologist and creator of Headway")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Biography

    private var biographySection: some View {
        Section("About Dr. DeOrchis") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dr. DeOrchis is Managing Partner of Neurological Associates of Long Island, P.C., where he specializes in clinical neurophysiology and neuromuscular disorders. He is Director of Neurology and Stroke Director at St. Francis Hospital and Heart Center, and Clinical Assistant Professor of Neurology at Hofstra Medical School.")

                Text("He studied neural science at New York University and earned a master\u{2019}s degree in physiology and biophysics from Georgetown University before receiving his medical degree from SUNY Downstate College of Medicine. He completed his neurology residency at Albert Einstein College of Medicine\u{2019}s Montefiore Medical Center, where he served as chief resident, followed by a fellowship in clinical neurophysiology and neuromuscular disease.")

                Text("A Fellow of the American Academy of Neurology, he has been recognized as a Castle Connolly Top Doctor and was the only neurologist in Nassau County named to Super Doctors 2025 by The New York Times. His research has appeared in Headache, Neurology, Muscle & Nerve, and other peer-reviewed journals, and he serves as principal investigator on numerous clinical trials.")

                Text("Beyond Headway, he has developed other digital health tools, including iFell, which records heart rate at the moment of a fall to help identify cardiovascular causes, and BrainMetrix, an analytics platform for quantitative brain MRI volumetry. He holds a patent pending for an avatar-assisted telemedicine platform and partnered with Fujifilm to bring the first Synergy Series MRI system in the nation to his practice. Headway and iFell are available free on the App Store.")
            }
            .font(.callout)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Headache diary

    private var diarySection: some View {
        Section {
            Text("Keeping a headache diary is a well-established way to identify triggers, track treatment response and give your clinician a clearer picture between visits.")
                .font(.callout)
                .padding(.vertical, 4)

            if let url = AboutReference.americanMigraineFoundationURL {
                Link("American Migraine Foundation", destination: url)
                    .accessibilityHint("Opens the American Migraine Foundation website.")
            }
        } header: {
            Text("Why Keep a Headache Diary?")
        } footer: {
            Text(AboutReference.citationsFooter)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Link("Privacy Policy", destination: AppContactInfo.privacyPolicyURL)
                .accessibilityHint("Opens the full Headway privacy policy in your default browser.")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Everything you enter in Headway stays on your device and is never sent to a third party. You can optionally keep a copy in your personal iCloud account.")
        }
    }

    // MARK: - Practice

    private var practiceSection: some View {
        Section {
            NavigationLink("Neurological Associates of Long Island") {
                NeurologicalAssociatesView()
            }
        }
    }

    // MARK: - Version

    private var versionSection: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(spacing: 2) {
                Text("Headway: Migraine Monitor")
                Text(versionString)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - References

private enum AboutReference {
    static let americanMigraineFoundationURL = URL(string: "https://americanmigrainefoundation.org")

    static let citationsFooter: LocalizedStringKey = "Sources: [van Casteren et al., Cephalalgia 2021](https://pubmed.ncbi.nlm.nih.gov/33938248/) and [Minen et al., Headache 2023](https://pubmed.ncbi.nlm.nih.gov/37313636/)."
}

#Preview {
    AboutView()
}
