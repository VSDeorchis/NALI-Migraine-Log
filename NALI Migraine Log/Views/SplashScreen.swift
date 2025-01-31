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
                
                Text("Neurological Associates\nof Long Island, P.C.")
                    .font(.custom("Optima-Bold", size: 32))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                
                Text("NALI Migraine Tracker")
                    .font(.custom("Optima-Regular", size: 24))
                    .foregroundColor(.white)
                    .padding(.top)
                
                Spacer()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("© 2025 Clinical Insights Consulting Group")
                            .font(.custom("Optima-Regular", size: 12))
                            .foregroundColor(.white)
                        Text("Developed by Vincent S. DeOrchis, M.D. M.S. FAAN")
                            .font(.custom("Optima-Regular", size: 12))
                            .foregroundColor(.white)
                        Text("Ver \(appVersion)")
                            .font(.custom("Optima-Regular", size: 12))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    SplashScreen()
} 