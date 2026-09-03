import SwiftUI

struct DisclaimerView: View {
    @Binding var hasAcceptedDisclaimer: Bool
    @AppStorage("useICloudSync") private var useICloudSync = false
    /// Invoked when the user declines. The caller decides what to show;
    /// the process is never terminated.
    let declineAction: () -> Void
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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            
            HStack(spacing: 20) {
                Button("Decline") {
                    declineAction()
                }
                
                Button("Accept") {
                    UserDefaults.standard.set(true, forKey: Constants.hasAcceptedDisclaimer)

                    // Apply the onboarding sync choice to the live store if it
                    // differs from how the container launched.
                    if PersistenceController.shared.isCloudKitEnabled != useICloudSync {
                        PersistenceController.shared.reloadStore(cloudKitEnabled: useICloudSync)
                    }

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

/// Shown after the disclaimer is declined. The app stays open but unusable
/// until the user goes back and accepts.
struct DisclaimerDeclinedView: View {
    let reviewAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Disclaimer Not Accepted")
                .font(.title2)
                .bold()

            Text("Headway can only be used after you accept the medical disclaimer. Nothing has been recorded and no data has left your Mac. You can review the disclaimer again at any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Review Disclaimer", action: reviewAction)
                .buttonStyle(.borderedProminent)

            Link("Privacy Policy", destination: AppContactInfo.privacyPolicyURL)
                .font(.footnote)
        }
        .padding()
        .frame(width: 500)
    }
}