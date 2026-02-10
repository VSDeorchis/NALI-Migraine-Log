import SwiftUI

struct SplashScreen: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var body: some View {
        ZStack {
            Color(red: 68/255, green: 130/255, blue: 180/255) // Steel Blue
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Text("Headway")
                        .font(.custom("Optima-Bold", size: 48))
                    Text("Migraine Monitor and Analytics")
                        .font(.custom("Optima-Regular", size: 34))
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 45))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                }
                .foregroundColor(.white)
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 400, height: 1)
                    .padding(.vertical, 40)
                
                Text("Neurological Associates\nof Long Island, P.C.")
                    .font(.custom("Optima-Bold", size: 26))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(alignment: .center, spacing: 8) {
                    Text("Developed by Vincent S. DeOrchis, M.D. M.S. FAAN")
                        .font(.custom("Optima-Regular", size: 14))
                    Text("© 2025 Clinical Insights Consulting Group")
                        .font(.custom("Optima-Regular", size: 14))
                    Text("Ver \(appVersion)")
                        .font(.custom("Optima-Regular", size: 14))
                }
                .foregroundColor(.white)
                .padding()
            }
        }
        .transition(.opacity)
    }
}


#Preview {
    SplashScreen()
} 
