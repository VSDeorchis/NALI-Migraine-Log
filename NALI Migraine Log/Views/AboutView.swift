import SwiftUI
import MapKit

struct AboutView: View {
    private let practiceName = "Neurological Associates of Long Island, P.C."
    private let streetAddress = "1991 Marcus Avenue"
    private let suite = "Suite 110"
    private let cityStateZip = "Lake Success, NY 11042"
    private let phoneNumber = "(516) 466-4700"
    private let faxNumber = "(516) 466-4810"
    
    private let backgroundColor = Color(red: 68/255, green: 130/255, blue: 180/255)  // Steelblue color
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("About Us")
                        .font(.custom("Optima-Regular", size: 34))  // We'll match the splash screen font
                        .foregroundColor(.white)
                        .padding(.bottom, 5)
                    
                    Image("about_image")  // Use the exact name you gave it in Assets.xcassets
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom)
                    
                    // Practice Description
                    Text("Neurological Associates of Long Island has been providing comprehensive, compassionate, and innovative neurologic care to our community for over 50 years. Our team of 10 board-certified neurologists covers virtually every aspect of neurologic disease, supported by extensive on-site diagnostic testing, physical therapy, and infusion services. We are also actively engaged in clinical research, investigating novel therapies for a variety of neurologic conditions.")
                        .foregroundColor(.white)
                        
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("In our continued effort to improve patient outcomes, we have created Headway. This app empowers patients to accurately track their headache symptoms, medications, and triggers, offering a clearer picture for both patients and physicians to guide treatment plans and improve headache management. To safeguard your privacy, all data entered into the app is stored locally on your device and never transmitted to a third party. Data may be preserved to your personal Apple iCloud account. At Neurological Associates, we remain committed to delivering timely appointments, assisting with insurance complexities, and ensuring every visit is a comfortable and informative experience.")
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
                        
                        Text("Maintaining a headache diary has been a well established method for identifying and managing headache symptoms and triggers¹,²")
                            .foregroundColor(.white) +
                        Text(". Further information can be found at the ")
                            .foregroundColor(.white) +
                        Text("American Migraine Foundation")
                            .foregroundColor(.white)
                            .underline() +
                        Text(".")
                            .foregroundColor(.white)
                        
                        Text("¹ van Casteren DS, et al. E-diary use in clinical headache practice: A prospective observational study. Cephalalgia. 2021.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .onTapGesture {
                                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/33938248/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        
                        Text("² Minen MT, et al. Headache clinicians' perspectives on the remote monitoring of patients' electronic diary data: A qualitative study. Headache. 2023.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .onTapGesture {
                                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/37313636/") {
                                    UIApplication.shared.open(url)
                                }
                            }
                    }
                    
                    // Horizontal Line
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    
                    // Contact Information
                    Group {
                        Text("Contact Us")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Button(action: {
                            openMaps()
                        }) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(practiceName)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text(streetAddress)
                                    .foregroundColor(.white)
                                Text(suite)
                                    .foregroundColor(.white)
                                Text(cityStateZip)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "phone")
                                .foregroundColor(.white)
                            Button("Tel: \(phoneNumber)") {
                                callPhone()
                            }
                            .foregroundColor(.white)
                        }
                        .padding(.top, 5)
                        
                        HStack {
                            Image(systemName: "printer")
                                .foregroundColor(.white)
                            Text("Fax: \(faxNumber)")
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.white)
                            Link("www.neuroli.com", destination: URL(string: "https://www.neuroli.com")!)
                                .accentColor(.white)
                                .underline()
                        }
                        .padding(.top, 5)
                    }
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle("")
        }
        .navigationViewStyle(.stack)
    }
    
    private func openMaps() {
        let address = "\(streetAddress) \(suite) \(cityStateZip)"
        let addressEncoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "maps://?address=\(addressEncoded)"),
              UIApplication.shared.canOpenURL(url) else {
            // Handle error - perhaps show an alert
            return
        }
        UIApplication.shared.open(url)
    }
    
    private func callPhone() {
        let telephone = phoneNumber.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        if let url = URL(string: "tel://\(telephone)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    AboutView()
} 
