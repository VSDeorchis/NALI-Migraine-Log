import SwiftUI

struct AboutView: View {
    @State private var showingPracticeInfo = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Headshot and Name
                HStack(spacing: 16) {
                    Image("headshot")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vincent S. DeOrchis")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("M.D., M.S., F.A.A.N.")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Board-Certified Neurologist")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                // App Introduction
                Text("Headway: Migraine Monitor was created by Vincent S. DeOrchis, M.D., M.S., F.A.A.N., a board-certified neurologist with subspecialty fellowship training in Clinical Neurophysiology and Neuromuscular Disorders at Neurological Associates of Long Island, P.C.")
                    .lineSpacing(3)
                
                // Education & Training
                VStack(alignment: .leading, spacing: 8) {
                    Text("Education & Training")
                        .font(.headline)
                    
                    MacBulletPoint("B.S. in Neural Science, New York University")
                    MacBulletPoint("M.S. in Physiology & Biophysics, Georgetown University")
                    MacBulletPoint("M.D., SUNY Downstate College of Medicine")
                    MacBulletPoint("Neurology Residency, Albert Einstein College of Medicine / Montefiore Medical Center \u{2014} Chief Resident")
                    MacBulletPoint("Fellowship in Clinical Neurophysiology & Neuromuscular Disease, Albert Einstein College of Medicine")
                }
                
                // Recognition
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognition")
                        .font(.headline)
                    
                    MacBulletPoint("Fellow of the American Academy of Neurology (FAAN)")
                    MacBulletPoint("Super Doctors 2025, The New York Times \u{2014} the only neurologist in Nassau County")
                    MacBulletPoint("Castle Connolly Top Doctors of New York")
                    MacBulletPoint("Published in Headache, Neurology, Muscle & Nerve, and other peer-reviewed journals")
                }
                
                // Clinical Roles
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clinical Leadership")
                        .font(.headline)
                    
                    MacBulletPoint("Managing Partner, Neurological Associates of Long Island, P.C.")
                    MacBulletPoint("Director of Neurology & Stroke Director, St. Francis Hospital and Heart Center")
                    MacBulletPoint("Clinical Assistant Professor of Neurology, Hofstra Medical School")
                    MacBulletPoint("Principal Investigator on multiple clinical trials")
                }
                
                // Technology Innovation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Technology & Innovation")
                        .font(.headline)
                    
                    Text("Dr. DeOrchis has a strong interest in clinical technology innovation. In addition to Headway, he created iFell, an iOS application that records heart rate at the moment of a fall to assess potential cardiovascular causes, and BrainMetrix, an advanced analytics platform for quantitative brain MRI volumetric analysis. He also holds a patent pending for an avatar-assisted telemedicine platform and collaborated with Fujifilm to establish the first Synergy Series MRI system in the United States. Headway and iFell are available free on the Apple App Store.")
                        .lineSpacing(3)
                }
                
                Divider()
                
                // Privacy Note
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                        Text("Your Privacy")
                            .font(.headline)
                    }
                    
                    Text("All data entered into Headway is stored locally on your device and never transmitted to a third party. Data may optionally be preserved to your personal Apple iCloud account.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
                
                Divider()
                
                // References
                VStack(alignment: .leading, spacing: 8) {
                    Text("Maintaining a headache diary has been a well established method for identifying and managing headache symptoms and triggers\u{00B9}\u{00B7}\u{00B2}.")
                        .font(.subheadline)
                    
                    Text("\u{00B9} van Casteren DS, et al. E-diary use in clinical headache practice: A prospective observational study. Cephalalgia. 2021.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            openURL("https://pubmed.ncbi.nlm.nih.gov/33938248/")
                        }
                    
                    Text("\u{00B2} Minen MT, et al. Headache clinicians\u{2019} perspectives on the remote monitoring of patients\u{2019} electronic diary data: A qualitative study. Headache. 2023.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            openURL("https://pubmed.ncbi.nlm.nih.gov/37313636/")
                        }
                }
                
                Divider()
                
                // About Practice Button
                Button(action: {
                    showingPracticeInfo = true
                }) {
                    HStack {
                        Image(systemName: "building.2")
                            .font(.title3)
                        Text("About Neurological Associates of Long Island")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                // Version
                Text("Ver \(appVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("About")
        .sheet(isPresented: $showingPracticeInfo) {
            MacNeurologicalAssociatesView()
        }
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Practice Info Sheet (macOS)

struct MacNeurologicalAssociatesView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let practiceName = "Neurological Associates of Long Island, P.C."
    private let streetAddress = "1991 Marcus Avenue"
    private let suite = "Suite 110"
    private let cityStateZip = "Lake Success, NY 11042"
    private let phoneNumber = "(516) 466-4700"
    private let faxNumber = "(516) 466-4810"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Our Practice")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image("about_image")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom)
                    
                    Text("Neurological Associates of Long Island has been providing comprehensive, compassionate, and innovative neurologic care to our community for over 50 years. Our team of 10 board-certified neurologists covers virtually every aspect of neurologic disease, supported by extensive on-site diagnostic testing, physical therapy, and infusion services. We are also actively engaged in clinical research, investigating novel therapies for a variety of neurologic conditions.")
                        .lineSpacing(3)
                    
                    Text("In our continued effort to improve patient outcomes, we have created Headway. This app empowers patients to accurately track their headache symptoms, medications, and triggers, offering a clearer picture for both patients and physicians to guide treatment plans and improve headache management. At Neurological Associates, we remain committed to delivering timely appointments, assisting with insurance complexities, and ensuring every visit is a comfortable and informative experience.")
                        .lineSpacing(3)
                    
                    Divider()
                    
                    // Contact Information
                    Group {
                        Text("Contact Information")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text(practiceName)
                                .fontWeight(.semibold)
                            Button(action: { openMaps() }) {
                                VStack(alignment: .leading) {
                                    Text(streetAddress)
                                    Text(suite)
                                    Text(cityStateZip)
                                }
                            }
                            .buttonStyle(.link)
                        }
                        
                        HStack {
                            Image(systemName: "phone")
                            Button("Tel: \(phoneNumber)") {
                                openURL("tel:\(phoneNumber.filter { $0.isNumber })")
                            }
                        }
                        
                        HStack {
                            Image(systemName: "printer")
                            Text("Fax: \(faxNumber)")
                        }
                        
                        HStack {
                            Image(systemName: "globe")
                            Link("www.neuroli.com", destination: URL(string: "https://www.neuroli.com")!)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 550, height: 600)
    }
    
    private func openMaps() {
        let address = "\(streetAddress) \(suite) \(cityStateZip)"
        let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        openURL("maps://?address=\(encodedAddress)")
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Helper Views

private struct MacBulletPoint: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .lineSpacing(2)
        }
    }
}

#Preview {
    AboutView()
}
