import SwiftUI
import DeviceActivity
import FamilyControls
import Stripe
import StripePaymentSheet

@main
struct payattentionclub_app_1_1App: App {
    init() {
        // Log environment configuration in debug builds
        #if DEBUG
        NSLog("ENV: %@ | Supabase: %@ | Stripe: %@",
              AppConfig.environment.displayName,
              SupabaseConfig.projectURL,
              StripeConfig.environment)
        #endif
        
        // Initialize Stripe SDK with publishable key
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
    }
    
    @StateObject private var model = AppModel()
    
    var body: some Scene {
        WindowGroup {
            // CRITICAL: Use a View (not Scene body) to observe model changes
            // Scene bodies don't re-evaluate when @Published properties change
            RootRouterView()
                .environmentObject(model)
                .onOpenURL { url in
                    #if DEBUG
                    NSLog("DEEPLINK: %@", url.absoluteString)
                    #endif
                    model.handleDeepLink(url)
                }
        }
    }
}

// View that observes model and switches screens
// This pattern ensures SwiftUI re-evaluates when model.currentScreen changes
struct RootRouterView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch model.currentScreen {
                case .loading:
                    LoadingView()
                case .setup:
                    SetupView()
                case .screenTimeAccess:
                    ScreenTimeAccessView()
                case .authorization:
                    AuthorizationView()
                case .monitor:
                    MonitorView()
                case .bulletin:
                    BulletinView()
                }
            }
            .id(model.currentScreen) // Force identity change
            
            // STAGING badge - only visible in test mode
            if AppConfig.isTestMode {
                StagingBadge()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // Check deadline when app becomes active (foreground)
            if newPhase == .active {
                // Small delay to let app fully activate
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    _ = model.checkDeadlineAndNavigate()
                }
            }
        }
    }
}

/// Badge shown in staging/test mode to prevent confusion with production
struct StagingBadge: View {
    var body: some View {
        Text("STAGING")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange)
            .cornerRadius(4)
            .padding(.leading, 8)
            .padding(.top, 60) // Below status bar
    }
}

