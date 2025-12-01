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
        }
    }
}

// View that observes model and switches screens
// This pattern ensures SwiftUI re-evaluates when model.currentScreen changes
struct RootRouterView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    
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
            case .backendTest:
                BackendTestView() // TEMPORARY: Remove after testing
            case .dailyUsageTest:
                DailyUsageTestView() // TEMPORARY: Phase 2 testing
            }
        }
        .id(model.currentScreen) // Force identity change
        .onChange(of: scenePhase) { newPhase in
            // Sync when app comes to foreground (becomes active)
            if newPhase == .active {
                NSLog("SYNC RootRouterView: 🔄 App became active, syncing usage data...")
                print("SYNC RootRouterView: 🔄 App became active, syncing usage data...")
                Task {
                    do {
                        try await UsageSyncManager.shared.syncToBackend()
                        NSLog("SYNC RootRouterView: ✅ Foreground sync completed")
                        print("SYNC RootRouterView: ✅ Foreground sync completed")
                    } catch {
                        NSLog("SYNC RootRouterView: ⚠️ Foreground sync failed: \(error)")
                        print("SYNC RootRouterView: ⚠️ Foreground sync failed: \(error)")
                        // Don't show error to user, just log it (happens in background)
                    }
                }
            }
        }
    }
}

