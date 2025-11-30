import SwiftUI

struct LegacySplashScreen: View {
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Ver \(version) (\(build))"
    }
    
    var body: some View {
        ZStack {
            Color(red: 68/255, green: 130/255, blue: 180/255) // Steel Blue
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Text("Headway")
                        .font(.custom("Optima-Bold", size: 38))
                    Text("Migraine Monitor and Analytics")
                        .font(.custom("Optima-Regular", size: 24))
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 45))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                }
                .foregroundColor(.white)
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 200, height: 1)
                    .padding(.vertical, 20)
                
                Text("Neurological Associates\nof Long Island, P.C.")
                    .font(.custom("Optima-Bold", size: 22))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(alignment: .center, spacing: 8) {
                    Text("Developed by Vincent S. DeOrchis, M.D. M.S. FAAN")
                        .font(.custom("Optima-Regular", size: 12))
                    Text("© 2025 Clinical Insights Consulting Group")
                        .font(.custom("Optima-Regular", size: 12))
                    Text(appVersion)
                        .font(.custom("Optima-Regular", size: 12))
                }
                .foregroundColor(.white)
                .padding()
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    LegacySplashScreen()
} 