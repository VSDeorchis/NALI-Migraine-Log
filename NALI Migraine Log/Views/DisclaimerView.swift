import SwiftUI

struct DisclaimerView: View {
    @Binding var hasAcceptedDisclaimer: Bool
    let dismissAction: () -> Void
    let viewModel: MigraineViewModel
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingICloudAlert = false
    @State private var showingSettings = false
    @State private var enableLocationServices = false
    
    var body: some View {
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
                        .foregroundColor(.secondary)
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
                                .foregroundColor(.blue)
                                .font(.system(size: 13))
                            Text("Weather Tracking")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Text("Your location is used to automatically fetch weather data (temperature, barometric pressure changes) for each migraine entry. This helps identify weather-related triggers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if enableLocationServices {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("How It Works")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                                Text("iOS will ask for your location each time you save a migraine entry. Simply tap 'Allow Once' to automatically fetch weather data. This privacy-first approach keeps you in control.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 4)
                        } else {
                            Text("You can enable weather tracking later in Settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            
            HStack(spacing: 20) {
                Button("Decline") {
                    dismissAction()
                }
                .foregroundColor(.red)
                
                Button("Accept") {
                    UserDefaults.standard.set(true, forKey: Constants.hasAcceptedDisclaimer)
                    hasAcceptedDisclaimer = true
                    
                    // Request location permission if user enabled it
                    if enableLocationServices {
                        locationManager.requestPermission()
                    }
                }
                .foregroundColor(.blue)
            }
            
            Button("Learn More About Data Storage") {
                showingSettings = true
            }
            .font(.footnote)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
        .alert("Data Storage Information", isPresented: $showingICloudAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your migraine data is stored locally on your device. If iCloud sync is enabled, data will also be stored in your personal iCloud account to enable synchronization between your iPhone and Apple Watch. The data is private and only accessible through your Apple ID. You can change sync settings at any time through the app's settings.")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
} 