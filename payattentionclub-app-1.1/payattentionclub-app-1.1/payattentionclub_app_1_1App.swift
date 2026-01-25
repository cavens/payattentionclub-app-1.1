import SwiftUI
import DeviceActivity
import FamilyControls
import Stripe
import StripePaymentSheet

@main
struct payattentionclub_app_1_1App: App {
    init() {
        // Initialize Stripe SDK with publishable key
        StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
        
        // Set up notification delegate to show notifications when app is in foreground
        // Use singleton to ensure delegate is retained
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        NSLog("NOTIFICATION App: ✅ Set NotificationDelegate.shared as UNUserNotificationCenter delegate")
        
        // Verify delegate is set
        if center.delegate === NotificationDelegate.shared {
            NSLog("NOTIFICATION App: ✅ Verified delegate is correctly set")
        } else {
            NSLog("NOTIFICATION App: ❌ ERROR - Delegate verification failed!")
        }
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
                    #if DEBUG
                    NSLog("DEEPLINK App: Received URL %@", url.absoluteString)
                    #endif
                    model.handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Update daily usage and sync when app comes to foreground
                    Task { @MainActor in
                        // Check if deadline has passed and store consumedMinutes at deadline if needed
                        let tracker = UsageTracker.shared
                        if tracker.isCommitmentDeadlinePassed() {
                            let consumedMinutes = tracker.getConsumedMinutes()
                            // Only store if we don't already have a stored value
                            if tracker.getConsumedMinutesAtDeadline() == nil {
                                tracker.storeConsumedMinutesAtDeadline(consumedMinutes)
                                NSLog("APP Foreground: ⏰ Deadline passed, stored consumedMinutes at deadline: \(consumedMinutes) min")
                            }
                        }
                        await UsageSyncManager.shared.updateAndSync()
                    }
                }
        }
    }
}

// View that observes model and switches screens
// This pattern ensures SwiftUI re-evaluates when model.currentScreen changes
struct RootRouterView: View {
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        NavigationStack {
            Group {
                switch model.currentScreen {
                case .loading:
                    LoadingView()
                case .intro:
                    IntroView()
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
        }
    }
}

