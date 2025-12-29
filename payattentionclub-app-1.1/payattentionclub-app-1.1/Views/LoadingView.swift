import SwiftUI

struct LoadingView: View {
    @EnvironmentObject var model: AppModel
    @State private var logoOpacity: Double = 0
    @State private var hasStartedAnimation = false
    
    private let pinkColor = Color(red: 226/255, green: 204/255, blue: 205/255)
    
    var body: some View {
        ZStack {
            // Completely pink background - appears immediately
            pinkColor
                .ignoresSafeArea()
            
            // Logo in center
            if let uiImage = UIImage(named: "PayAttentionClubLogo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 173, height: 173) // 50% bigger than setup screen (115 * 1.5 = 172.5)
                    .opacity(logoOpacity)
            } else {
                // Fallback if logo not found
                Text("Pay Attention Club")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(logoOpacity)
            }
        }
        .background(pinkColor)
        .ignoresSafeArea()
        .onAppear {
            guard !hasStartedAnimation else { return }
            hasStartedAnimation = true
            
            // Start initialization in background (non-blocking)
            Task.detached(priority: .userInitiated) {
                await model.finishInitialization()
            }
            
            // Start fade in animation immediately
            withAnimation(.easeIn(duration: 0.6)) {
                logoOpacity = 1.0
            }
            
            // Wait for fade in + stay time (0.6s fade in + 1.5s stay = 2.1s), then fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                withAnimation(.easeOut(duration: 0.6)) {
                    logoOpacity = 0.0
                }
                
                // After fade out completes (0.6s), navigate to setup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // Navigation will happen automatically when initialization completes
                    // But ensure we navigate even if initialization is slow
                    Task { @MainActor in
                        if model.currentScreen == .loading {
                            // Small delay to ensure initialization has had time
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            if model.currentScreen == .loading {
                                // If still loading, check navigation status
                                let isActive = UsageTracker.shared.isMonitoringActive()
                                model.navigate(isActive ? .monitor : .setup)
                            }
                        }
                    }
                }
            }
        }
    }
}

