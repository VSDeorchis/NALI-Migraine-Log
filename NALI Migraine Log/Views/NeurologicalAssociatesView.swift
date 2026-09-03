import SwiftUI
import MapKit

struct NeurologicalAssociatesView: View {
    private let practiceName = "Neurological Associates of Long Island, P.C."
    private let streetAddress = "1991 Marcus Avenue"
    private let suite = "Suite 110"
    private let cityStateZip = "Lake Success, NY 11042"
    private let phoneNumber = "(516) 466-4700"
    private let faxNumber = "(516) 466-4810"
    
    private let backgroundColor = Color(red: 68/255, green: 130/255, blue: 180/255)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("about_image")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom)
                
                // Practice Description
                Text("Neurological Associates of Long Island has been providing comprehensive, compassionate, and innovative neurologic care to our community for over 50 years. Our team of 10 board-certified neurologists covers virtually every aspect of neurologic disease, supported by extensive on-site diagnostic testing, physical therapy, and infusion services. We are also actively engaged in clinical research, investigating novel therapies for a variety of neurologic conditions.")
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                
                Text("In our continued effort to improve patient outcomes, we have created Headway. This app empowers patients to accurately track their headache symptoms, medications, and triggers, offering a clearer picture for both patients and physicians to guide treatment plans and improve headache management. At Neurological Associates, we remain committed to delivering timely appointments, assisting with insurance complexities, and ensuring every visit is a comfortable and informative experience.")
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                
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
                        .foregroundStyle(.white)
                    
                    Button(action: {
                        openMaps()
                    }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(practiceName)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Text(streetAddress)
                                .foregroundStyle(.white)
                            Text(suite)
                                .foregroundStyle(.white)
                            Text(cityStateZip)
                                .foregroundStyle(.white)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "phone")
                            .foregroundStyle(.white)
                        Button("Tel: \(phoneNumber)") {
                            callPhone()
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(.top, 5)
                    
                    HStack {
                        Image(systemName: "printer")
                            .foregroundStyle(.white)
                        Text("Fax: \(faxNumber)")
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.white)
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
        .navigationTitle("Our Practice")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func openMaps() {
        let address = "\(streetAddress) \(suite) \(cityStateZip)"
        let addressEncoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "maps://?address=\(addressEncoded)"),
              UIApplication.shared.canOpenURL(url) else {
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
    NavigationStack {
        NeurologicalAssociatesView()
    }
}
