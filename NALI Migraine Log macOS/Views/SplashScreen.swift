import SwiftUI

struct SplashScreen: View {
    @State private var animationPhase: CGFloat = 0
    
    // Staggered entrance animation states
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showTagline = false
    @State private var showIcon = false
    @State private var showDivider = false
    @State private var showPractice = false
    @State private var showFooter = false
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Ver \(version) (\(build))"
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            MacAnimatedGradientBackground(animationPhase: animationPhase)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Title block
                VStack(spacing: 8) {
                    Text("Headway")
                        .font(.custom("Optima-Bold", size: 48))
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 12)
                    
                    Text("Migraine Monitor and Analytics")
                        .font(.custom("Optima-Regular", size: 28))
                        .opacity(showSubtitle ? 1 : 0)
                        .offset(y: showSubtitle ? 0 : 8)
                    
                    Text("Track  ·  Predict  ·  Prevent")
                        .font(.custom("Optima-Bold", size: 16))
                        .tracking(2)
                        .opacity(showTagline ? 0.85 : 0)
                        .offset(y: showTagline ? 0 : 8)
                        .padding(.top, 4)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .padding(.top, 15)
                        .opacity(showIcon ? 1 : 0)
                        .scaleEffect(showIcon ? 1 : 0.7)
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                
                // Gradient divider
                gradientDivider
                    .padding(.vertical, 30)
                    .opacity(showDivider ? 1 : 0)
                    .scaleEffect(x: showDivider ? 1 : 0, y: 1)
                
                Text("Neurological Associates\nof Long Island, P.C.")
                    .font(.custom("Optima-Bold", size: 26))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                    .opacity(showPractice ? 1 : 0)
                    .offset(y: showPractice ? 0 : 8)
                
                Spacer()
                
                VStack(alignment: .center, spacing: 8) {
                    Text("Developed by Vincent S. DeOrchis, M.D. M.S. FAAN")
                        .font(.custom("Optima-Regular", size: 14))
                    Text("© 2026 Clinical Insights Consulting Group")
                        .font(.custom("Optima-Regular", size: 14))
                    Text(appVersion)
                        .font(.custom("Optima-Regular", size: 14))
                }
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 1)
                .padding()
                .opacity(showFooter ? 1 : 0)
            }
        }
        .transition(.opacity)
        .onAppear {
            // Start the gradient animation
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                animationPhase = 1.0
            }
            
            // Staggered entrance animations
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                showTitle = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                showSubtitle = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                showTagline = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6)) {
                showIcon = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
                showDivider = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
                showPractice = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(1.2)) {
                showFooter = true
            }
        }
    }
    
    // MARK: - Gradient Divider
    
    private var gradientDivider: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.9),
                Color.white.opacity(0.9),
                Color.white.opacity(0)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 350, height: 1)
        .shadow(color: .white.opacity(0.3), radius: 4)
    }
}

// MARK: - macOS Animated Gradient Background

struct MacAnimatedGradientBackground: View {
    let animationPhase: CGFloat
    
    // Define color palette - blue → gray → purple transition
    private let blueShade1 = Color(red: 68/255, green: 130/255, blue: 180/255)   // Steel Blue
    private let blueShade2 = Color(red: 100/255, green: 149/255, blue: 237/255)  // Cornflower Blue
    private let blueShade3 = Color(red: 70/255, green: 130/255, blue: 180/255)   // Steel Blue
    
    private let grayShade1 = Color(red: 112/255, green: 128/255, blue: 144/255)  // Slate Gray
    private let grayShade2 = Color(red: 119/255, green: 136/255, blue: 153/255)  // Light Slate Gray
    private let grayShade3 = Color(red: 95/255, green: 115/255, blue: 140/255)   // Blue-Gray
    
    private let purpleShade1 = Color(red: 138/255, green: 43/255, blue: 226/255)  // Blue Violet
    private let purpleShade2 = Color(red: 147/255, green: 51/255, blue: 234/255)  // Medium Purple
    private let purpleShade3 = Color(red: 123/255, green: 104/255, blue: 238/255) // Medium Slate Blue
    
    var body: some View {
        ZStack {
            // Base gradient layer
            LinearGradient(
                gradient: Gradient(colors: [
                    interpolateThreeColors(from: blueShade1, mid: grayShade1, to: purpleShade1, progress: animationPhase),
                    interpolateThreeColors(from: blueShade2, mid: grayShade2, to: purpleShade2, progress: animationPhase),
                    interpolateThreeColors(from: blueShade3, mid: grayShade3, to: purpleShade3, progress: animationPhase)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Overlay gradient for depth
            RadialGradient(
                gradient: Gradient(colors: [
                    interpolateThreeColors(from: blueShade2, mid: grayShade2, to: purpleShade2, progress: animationPhase).opacity(0.4),
                    Color.clear
                ]),
                center: UnitPoint(
                    x: 0.5 + (animationPhase * 0.2),
                    y: 0.3 + (animationPhase * 0.1)
                ),
                startRadius: 50,
                endRadius: 600
            )
            
            // Shimmer effect
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.06), location: animationPhase * 0.3),
                    .init(color: .white.opacity(0.12), location: animationPhase * 0.5),
                    .init(color: .white.opacity(0.06), location: animationPhase * 0.7),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle vignette effect
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.black.opacity(0.15)
                ]),
                center: .center,
                startRadius: 250,
                endRadius: 700
            )
        }
    }
    
    // Helper function to interpolate between three colors
    private func interpolateThreeColors(from: Color, mid: Color, to: Color, progress: CGFloat) -> Color {
        if progress < 0.5 {
            let adjustedProgress = progress * 2.0
            return interpolateColor(from: from, to: mid, progress: adjustedProgress)
        } else {
            let adjustedProgress = (progress - 0.5) * 2.0
            return interpolateColor(from: mid, to: to, progress: adjustedProgress)
        }
    }
    
    // Helper function to interpolate between two colors (macOS-compatible)
    private func interpolateColor(from: Color, to: Color, progress: CGFloat) -> Color {
        let fromNS = NSColor(from)
        let toNS = NSColor(to)
        
        // Convert to sRGB to ensure we can read components
        let fromRGB = fromNS.usingColorSpace(.sRGB) ?? fromNS
        let toRGB = toNS.usingColorSpace(.sRGB) ?? toNS
        
        let r = fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * progress
        let g = fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * progress
        let b = fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * progress
        
        return Color(red: r, green: g, blue: b)
    }
}

#Preview {
    SplashScreen()
}
