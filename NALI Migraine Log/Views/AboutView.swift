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
                    
                    // Bio
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Headway: Migraine Monitor was created by Vincent S. DeOrchis, M.D., M.S., F.A.A.N., a board-certified neurologist and Managing Partner of Neurological Associates of Long Island, P.C., where he specializes in Clinical Neurophysiology and Neuromuscular Disorders.")
                            .foregroundColor(.white)
                            .lineSpacing(4)
                        
                        Text("Dr. DeOrchis studied Neural Science at New York University and earned his Master\u{2019}s degree in Physiology and Biophysics from Georgetown University before receiving his medical degree from SUNY Downstate College of Medicine. He completed his Neurology residency at Albert Einstein College of Medicine\u{2019}s Montefiore Medical Center, where he served as Chief Resident, followed by a fellowship in Clinical Neurophysiology and Neuromuscular Disease.")
                            .foregroundColor(.white)
                            .lineSpacing(4)
                        
                        Text("A Fellow of the American Academy of Neurology, Dr. DeOrchis has been recognized as a Castle Connolly Top Doctor and was the only neurologist in Nassau County named to Super Doctors 2025 by The New York Times. His research has been published in Headache, Neurology, Muscle & Nerve, and other peer-reviewed journals, and he serves as a principal investigator on numerous clinical trials. He currently holds the positions of Director of Neurology and Stroke Director at St. Francis Hospital and Heart Center and is a Clinical Assistant Professor of Neurology at Hofstra Medical School.")
                            .foregroundColor(.white)
                            .lineSpacing(4)
                        
                        Text("Driven by a passion for clinical technology, Dr. DeOrchis has developed several digital health tools beyond Headway, including iFell, which records heart rate at the moment of a fall to help identify cardiovascular causes, and BrainMetrix, an analytics platform for quantitative brain MRI volumetric analysis. He also holds a patent pending for an avatar-assisted telemedicine platform and partnered with Fujifilm to bring the first Synergy Series MRI system in the nation to his practice. Headway and iFell are available free on the Apple App Store.")
                            .foregroundColor(.white)
                            .lineSpacing(4)
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

#Preview {
    AboutView()
}
