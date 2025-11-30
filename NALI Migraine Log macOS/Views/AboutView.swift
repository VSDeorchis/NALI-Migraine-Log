import SwiftUI

struct AboutView: View {
    private let practiceName = "Neurological Associates of Long Island, P.C."
    private let streetAddress = "1991 Marcus Avenue"
    private let suite = "Suite 110"
    private let cityStateZip = "Lake Success, NY 11042"
    private let phoneNumber = "(516) 466-4700"
    private let faxNumber = "(516) 466-4810"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("about_image")  // Make sure to add this image to Assets
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom)
                
                Group {
                    Text("Neurological Associates of Long Island has been providing comprehensive, compassionate, and innovative neurologic care to our community for over 50 years. Our team of 10 board-certified neurologists covers virtually every aspect of neurologic disease, supported by extensive on-site diagnostic testing, physical therapy, and infusion services. We are also actively engaged in clinical research, investigating novel therapies for a variety of neurologic conditions.")
                        .padding(.bottom)
                    
                    Text("In our continued effort to improve patient outcomes, we have created Headway. This app empowers patients to accurately track their headache symptoms, medications, and triggers, offering a clearer picture for both patients and physicians to guide treatment plans and improve headache management. To safeguard your privacy, all data entered into the app is stored locally on your device and never transmitted to a third party. Data may be preserved to your personal Apple iCloud account. At Neurological Associates, we remain committed to delivering timely appointments, assisting with insurance complexities, and ensuring every visit is a comfortable and informative experience.")
                }
                .lineSpacing(5)
                
                Divider()
                    .padding(.vertical)
                
                // References section
                Group {
                    Text("Maintaining a headache diary has been a well established method for identifying and managing headache symptoms and triggers¹,².")
                    
                    Text("¹ van Casteren DS, et al. E-diary use in clinical headache practice: A prospective observational study. Cephalalgia. 2021.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            openURL("https://pubmed.ncbi.nlm.nih.gov/33938248/")
                        }
                    
                    Text("² Minen MT, et al. Headache clinicians' perspectives on the remote monitoring of patients' electronic diary data: A qualitative study. Headache. 2023.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            openURL("https://pubmed.ncbi.nlm.nih.gov/37313636/")
                        }
                }
                
                Divider()
                    .padding(.vertical)
                
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
        .navigationTitle("About")
    }
    
    private func openMaps() {
        let address = "\(streetAddress) \(suite) \(cityStateZip)"
        let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mapsURL = "maps://?address=\(encodedAddress)"
        openURL(mapsURL)
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    AboutView()
} 