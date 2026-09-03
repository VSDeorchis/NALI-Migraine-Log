import SwiftUI

struct DisclaimerView: View {
    @Binding var hasAcceptedDisclaimer: Bool
    /// Invoked when the user declines. The caller decides what to show;
    /// the process is never terminated.
    let declineAction: () -> Void
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingICloudAlert = false
    @State private var enableLocationServices = false
    
    var body: some View {
        ScrollView {
            content
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
        .alert("Data Storage Information", isPresented: $showingICloudAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your migraine data is stored locally on your device. If iCloud sync is enabled, data will also be stored in your personal iCloud account to enable synchronization between your iPhone and Apple Watch. The data is private and only accessible through your Apple ID. You can change sync settings at any time through the app's settings.")
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Text("Disclaimer")
                .font(.title)
                .bold()
            
            Text("Headway Migraine Monitor does not provide medical advice, diagnosis or treatment. Always seek the advice of your physician or other qualified health provider with any questions you have regarding a medical condition.")
                .multilineTextAlignment(.center)
                .padding()
            
            VStack(alignment: .leading, spacing: 15) {
                // iCloud Sync Section
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Enable iCloud Sync", isOn: $settings.useICloudSync)
                        .padding(.horizontal)
                    
                    Text("iCloud sync enables data synchronization across your devices. Your data remains private and is never shared with third parties.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                
                Divider()
                    .padding(.horizontal)
                
                // Location Services Section
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Location Services", isOn: $enableLocationServices)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud.sun.fill")
                                .foregroundStyle(.blue)
                                .scaledFont(size: 13)
                            Text("Weather Tracking")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(.primary)
                        }
                        
                        Text("Your location is used to automatically fetch weather data (temperature, barometric pressure changes) for each migraine entry. This helps identify weather-related triggers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if enableLocationServices {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("How It Works")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                                Text("iOS will ask for your location each time you save a migraine entry. Simply tap 'Allow Once' to automatically fetch weather data. This privacy-first approach keeps you in control.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 4)
                        } else {
                            Text("You can enable weather tracking later in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            
            HStack(spacing: 20) {
                Button("Decline") {
                    declineAction()
                }
                .foregroundStyle(.red)
                
                Button("Accept") {
                    UserDefaults.standard.set(true, forKey: Constants.hasAcceptedDisclaimer)

                    // Persist the onboarding sync choice explicitly and apply it
                    // to the live store if it differs from how the container
                    // launched (e.g. the user turned sync off on this screen).
                    UserDefaults.standard.set(settings.useICloudSync, forKey: "useICloudSync")
                    if PersistenceController.shared.isCloudKitEnabled != settings.useICloudSync {
                        PersistenceController.shared.reloadStore(cloudKitEnabled: settings.useICloudSync)
                    }

                    hasAcceptedDisclaimer = true
                    
                    // Request location permission if user enabled it
                    if enableLocationServices {
                        locationManager.requestPermission()
                    }
                }
                .foregroundStyle(.blue)
            }
            
            Button("Learn More About Data Storage") {
                showingICloudAlert = true
            }
            .font(.footnote)
            .foregroundStyle(.blue)
        }
        .padding()
    }
}

/// Shown in place of the main UI after the disclaimer is declined. Nothing
/// else is reachable until the user returns to the disclaimer and accepts.
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

            Text("Headway can only be used after you accept the medical disclaimer. Nothing has been recorded and no data has left your device. You can review the disclaimer again at any time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Review Disclaimer", action: reviewAction)
                .buttonStyle(.borderedProminent)

            Link("Privacy Policy", destination: AppContactInfo.privacyPolicyURL)
                .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}