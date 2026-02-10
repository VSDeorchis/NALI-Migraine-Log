import SwiftUI

struct AboutView: View {
    private let backgroundColor = Color(red: 68/255, green: 130/255, blue: 180/255)
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("About")
                        .font(.custom("Optima-Regular", size: 34))
                        .foregroundColor(.white)
                        .padding(.bottom, 5)
                    
                    // Headshot and Name
                    HStack(spacing: 16) {
                        Image("headshot")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vincent S. DeOrchis")
                                .font(.custom("Optima-Bold", size: 20))
                                .foregroundColor(.white)
                            Text("M.D., M.S., F.A.A.N.")
                                .font(.custom("Optima-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Board-Certified Neurologist")
                                .font(.custom("Optima-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.bottom, 4)
                    
                    // App Introduction
                    Text("Headway: Migraine Monitor was created by Vincent S. DeOrchis, M.D., M.S., F.A.A.N., a board-certified neurologist with subspecialty fellowship training in Clinical Neurophysiology and Neuromuscular Disorders at Neurological Associates of Long Island, P.C.")
                        .foregroundColor(.white)
                        .lineSpacing(3)
                    
                    // Education & Training
                    VStack(alignment: .leading, spacing: 8) {
                        AboutSectionHeader(title: "Education & Training")
                        
                        BulletPoint("B.S. in Neural Science, New York University")
                        BulletPoint("M.S. in Physiology & Biophysics, Georgetown University")
                        BulletPoint("M.D., SUNY Downstate College of Medicine")
                        BulletPoint("Neurology Residency, Albert Einstein College of Medicine / Montefiore Medical Center \u{2014} Chief Resident")
                        BulletPoint("Fellowship in Clinical Neurophysiology & Neuromuscular Disease, Albert Einstein College of Medicine")
                    }
                    
                    // Recognition
                    VStack(alignment: .leading, spacing: 8) {
                        AboutSectionHeader(title: "Recognition")
                        
                        BulletPoint("Fellow of the American Academy of Neurology (FAAN)")
                        BulletPoint("Super Doctors 2025, The New York Times \u{2014} the only neurologist in Nassau County")
                        BulletPoint("Castle Connolly Top Doctors of New York")
                        BulletPoint("Published in Headache, Neurology, Muscle & Nerve, and other peer-reviewed journals")
                    }
                    
                    // Clinical Roles
                    VStack(alignment: .leading, spacing: 8) {
                        AboutSectionHeader(title: "Clinical Leadership")
                        
                        BulletPoint("Managing Partner, Neurological Associates of Long Island, P.C.")
                        BulletPoint("Director of Neurology & Stroke Director, St. Francis Hospital and Heart Center")
                        BulletPoint("Clinical Assistant Professor of Neurology, Hofstra Medical School")
                        BulletPoint("Principal Investigator on multiple clinical trials")
                    }
                    
                    // Technology Innovation
                    VStack(alignment: .leading, spacing: 8) {
                        AboutSectionHeader(title: "Technology & Innovation")
                        
                        Text("Dr. DeOrchis has a strong interest in clinical technology innovation. In addition to Headway, he created iFell, an iOS application that records heart rate at the moment of a fall to assess potential cardiovascular causes, and BrainMetrix, an advanced analytics platform for quantitative brain MRI volumetric analysis. He also holds a patent pending for an avatar-assisted telemedicine platform and collaborated with Fujifilm to establish the first Synergy Series MRI system in the United States. Headway and iFell are available free on the Apple App Store.")
                            .foregroundColor(.white)
                            .lineSpacing(3)
                    }
                    
                    // Privacy Note
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.white)
                            Text("Your Privacy")
                                .font(.custom("Optima-Bold", size: 16))
                                .foregroundColor(.white)
                        }
                        
                        Text("All data entered into Headway is stored locally on your device and never transmitted to a third party. Data may optionally be preserved to your personal Apple iCloud account.")
                            .foregroundColor(.white.opacity(0.9))
                            .font(.subheadline)
                            .lineSpacing(3)
                    }
                    
                    // References
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maintaining a headache diary has been a well established method for identifying and managing headache symptoms and triggers\u{00B9}\u{00B7}\u{00B2}")
                            .foregroundColor(.white)
                            .font(.subheadline) +
                        Text(". Further information can be found at the ")
                            .foregroundColor(.white)
                            .font(.subheadline) +
                        Text("American Migraine Foundation")
                            .foregroundColor(.white)
                            .font(.subheadline)
                            .underline() +
                        Text(".")
                            .foregroundColor(.white)
                            .font(.subheadline)
                        
                        Text("\u{00B9} van Casteren DS, et al. E-diary use in clinical headache practice: A prospective observational study. Cephalalgia. 2021.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .onTapGesture {
                                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/33938248/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        
                        Text("\u{00B2} Minen MT, et al. Headache clinicians\u{2019} perspectives on the remote monitoring of patients\u{2019} electronic diary data: A qualitative study. Headache. 2023.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .onTapGesture {
                                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/37313636/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                    }
                    
                    // Horizontal Line
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    
                    // About Practice Button
                    NavigationLink(destination: NeurologicalAssociatesView()) {
                        HStack {
                            Image(systemName: "building.2")
                                .font(.title3)
                            Text("About Neurological Associates of Long Island")
                                .font(.custom("Optima-Bold", size: 16))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                    }
                    
                    // Version
                    Text("Ver \(appVersion)")
                        .font(.custom("Optima-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle("")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Helper Views

private struct AboutSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.custom("Optima-Bold", size: 18))
            .foregroundColor(.white)
    }
}

private struct BulletPoint: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundColor(.white.opacity(0.8))
                .font(.subheadline)
            Text(text)
                .foregroundColor(.white.opacity(0.9))
                .font(.subheadline)
                .lineSpacing(2)
        }
    }
}

#Preview {
    AboutView()
}
