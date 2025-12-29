import SwiftUI
import DeviceActivity
import FamilyControls
import Stripe
import StripePaymentSheet

@main
struct payattentionclub_app_1_1App: App {
    init() {
        // TEST: Verify new code is running
        NSLog("MARKERS App: 🚀🚀🚀 App init() called - NEW CODE IS RUNNING")
        print("MARKERS App: 🚀🚀🚀 App init() called - NEW CODE IS RUNNING")
        fflush(stdout)
        
        // Log environment configuration - filter by "TESTMODE" in console
        NSLog("TESTMODE ========================================")
        NSLog("TESTMODE Environment: %@", AppConfig.environment.displayName)
        NSLog("TESTMODE isTestMode: %@", AppConfig.isTestMode ? "YES" : "NO")
        NSLog("TESTMODE isProduction: %@", AppConfig.isProduction ? "YES" : "NO")
        NSLog("TESTMODE Supabase URL: %@", SupabaseConfig.projectURL)
        NSLog("TESTMODE Stripe env: %@", StripeConfig.environment)
        NSLog("TESTMODE ========================================")
        
        // Initialize Stripe SDK with publishable key
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
        NSLog("STRIPE App: Stripe SDK initialized with publishable key: \(StripeConfig.publishableKey.prefix(20))...")
    }
    
    @StateObject private var model = AppModel()
    
    var body: some Scene {
        WindowGroup {
            // CRITICAL: Use a View (not Scene body) to observe model changes
            // Scene bodies don't re-evaluate when @Published properties change
            RootRouterView()
                .environmentObject(model)
                .background(Color(red: 226/255, green: 204/255, blue: 205/255))
                .ignoresSafeArea()
                .onOpenURL { url in
                    NSLog("DEEPLINK App: Received URL %@", url.absoluteString)
                    model.handleDeepLink(url)
                }
        }
    }
}

// View that observes model and switches screens
// This pattern ensures SwiftUI re-evaluates when model.currentScreen changes
struct RootRouterView: View {
    @EnvironmentObject var model: AppModel
    
    init() {
        NSLog("MARKERS RootRouterView: init() called")
        print("MARKERS RootRouterView: init() called")
        fflush(stdout)
    }
    
    var body: some View {
        let screen = model.currentScreen
        
        NSLog("MARKERS RootRouterView: body accessed - screen: %@", String(describing: screen))
        print("MARKERS RootRouterView: body accessed - screen: \(screen)")
        fflush(stdout)
        
        return Group {
            switch screen {
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
    }
}

