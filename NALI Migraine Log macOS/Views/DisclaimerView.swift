import SwiftUI

struct DisclaimerView: View {
    @Binding var hasAcceptedDisclaimer: Bool
    @AppStorage("useICloudSync") private var useICloudSync = true
    let dismissAction: () -> Void
    @State private var showingICloudAlert = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Disclaimer")
                .font(.title)
                .bold()
            
            Text("Headway Migraine Monitor does not provide medical advice, diagnosis or treatment. Always seek the advice of your physician or other qualified health provider with any questions you have regarding a medical condition.")
                .multilineTextAlignment(.center)
                .padding()
            
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable iCloud Sync", isOn: $useICloudSync)
                    .padding(.horizontal)
                
                Text("iCloud sync enables data synchronization across your devices. Your data remains private and is never shared with third parties.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            
            HStack(spacing: 20) {
                Button("Decline") {
                    dismissAction()
                }
                
                Button("Accept") {
                    UserDefaults.standard.set(true, forKey: Constants.hasAcceptedDisclaimer)
                    hasAcceptedDisclaimer = true
                }
            }
            
            Button("Learn More About Data Storage") {
                showingICloudAlert = true
            }
            .font(.footnote)
        }
        .padding()
        .frame(width: 500)
        .alert("Data Storage Information", isPresented: $showingICloudAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your migraine data is stored locally on your device. If iCloud sync is enabled, data will also be stored in your personal iCloud account to enable synchronization between your devices. The data is private and only accessible through your Apple ID. You can change sync settings at any time through the app's settings.")
        }
    }
} 