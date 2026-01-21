import SwiftUI
import Foundation
import Combine
import FamilyControls
import DeviceActivity

@MainActor
final class AppModel: ObservableObject {
    // Navigation
    @Published var currentScreen: AppScreen = .loading
    
    // Setup values
    @Published var limitMinutes: Double = 21 * 60 // Default 21 hours in minutes
    @Published var penaltyPerMinute: Double = 0.10 // Default $0.10 per minute
    @Published var selectedApps = FamilyActivitySelection()
    
    // Authorization
    @Published var authorizationAmount: Double = 0.0
    
    // Usage tracking
    @Published var baselineUsageSeconds: Int = 0 // Snapshot when "Lock in" is pressed
    @Published var currentUsageSeconds: Int = 0 // Updated from Monitor Extension via App Group
    @Published var currentPenalty: Double = 0.0 // Calculated from excess usage
    @Published var isStartingMonitoring: Bool = false // Loading state during startMonitoring()
    
    // Countdown model for smooth countdown timer (lazy initialization)
    @Published var countdownModel: CountdownModel?

    // Weekly settlement state
    @Published var weekStatus: WeekStatusResponse?
    @Published var isLoadingWeekStatus: Bool = false
    @Published var weekStatusError: String?
    
    // Cached deadline date (recalculated only when needed)
    private var cachedNextMondayNoonEST: Date?
    private var cachedDeadlineDate: Date?
    
    // Flag to track if initialization is complete
    private var isInitialized = false
    
    // Intro state
    @Published var hasSeenIntro: Bool = false
    
    init() {
        // Minimal initialization - just set defaults
        // Heavy work deferred to finishInitialization() which is called after UI renders
        checkFirstLaunch()
    }
    
    private func checkFirstLaunch() {
        #if DEBUG
        // Always show intro in debug for easier testing
        hasSeenIntro = false
        #else
        hasSeenIntro = UserDefaults.standard.bool(forKey: "hasSeenIntro")
        #endif
    }
    
    func completeIntro() {
        hasSeenIntro = true
        UserDefaults.standard.set(true, forKey: "hasSeenIntro")
        navigate(.setup)
    }
    
    /// Finish initialization after UI has rendered (called from LoadingView.onAppear)
    func finishInitialization() async {
        guard !isInitialized else { 
            return 
        }
        isInitialized = true
        
        // Initialize countdown model (lightweight operation)
        // Prioritize stored deadline from commitment (from backend, compressed in testing mode)
        // Fall back to calculated deadline if no stored deadline exists
        let deadline = UsageTracker.shared.getCommitmentDeadline() ?? getNextMondayNoonEST()
        countdownModel = CountdownModel(deadline: deadline)
        refreshCachedDeadline()
        
        // Wait for loading animation to complete before navigating
        // This ensures user sees the loading screen logo
        try? await Task.sleep(nanoseconds: 2_700_000_000) // 2.7 seconds (0.6s fade in + 1.5s stay + 0.6s fade out)
        
        // Check if user has an active commitment first
        // This prevents showing intro/setup screens when commitment already exists
        if let commitmentDeadline = UsageTracker.shared.getCommitmentDeadline() {
            // Commitment exists - check if deadline has passed
            let deadlinePassed = UsageTracker.shared.isCommitmentDeadlinePassed()
            
            if deadlinePassed {
                // Deadline has passed - show bulletin with results
                NSLog("APP AppModel: Active commitment found, deadline passed - navigating to bulletin")
                navigate(.bulletin)
            } else {
                // Active commitment exists and deadline hasn't passed - go to monitor
                NSLog("APP AppModel: Active commitment found, deadline not passed - navigating to monitor")
                navigate(.monitor)
            }
        } else {
            // No commitment exists - follow normal flow based on intro status
            if hasSeenIntro {
                navigate(.setup)
            } else {
                navigate(.intro)
            }
        }
        
        // NOTE: Monitoring check and sync removed from startup to avoid UserDefaults reads
        // These will be handled lazily when needed:
        // - Monitoring check: Can be done in SetupView.onAppear if needed
        // - Sync: Can be done when app comes to foreground or manually
    }
    
    /// Refresh usage data from App Group (called when reopening app with active monitoring)
    private func refreshUsageFromAppGroup() async {
        Task.detached(priority: .userInitiated) {
            // Access UsageTracker.shared on main actor, then call nonisolated methods
            let tracker = await MainActor.run { UsageTracker.shared }
            let currentTotal = tracker.getCurrentTimeSpent()
            let baseline = tracker.getBaselineTime()
            let usageSeconds = Int(currentTotal) - Int(baseline)
            
            // Update UI on main thread
            await MainActor.run {
                self.currentUsageSeconds = usageSeconds
                self.updateCurrentPenalty()
            }
        }
    }
    
    func refreshWeekStatus(weekStartDateOverride: Date? = nil) {
        Task { @MainActor in
            isLoadingWeekStatus = true
            defer { isLoadingWeekStatus = false }

            do {
                let response = try await BackendClient.shared.fetchWeekStatus(
                    weekStartDate: weekStartDateOverride ?? UsageTracker.shared.getCommitmentDeadline()
                )
                weekStatus = response
                weekStatusError = nil
                
                // Load commitment settings from backend (source of truth)
                // This ensures limitMinutes and penaltyPerMinute match the actual commitment
                if response.limitMinutes > 0 {
                    limitMinutes = Double(response.limitMinutes)
                    NSLog("APP AppModel: Loaded limitMinutes from backend: \(response.limitMinutes) minutes")
                }
                if response.penaltyPerMinuteCents > 0 {
                    penaltyPerMinute = Double(response.penaltyPerMinuteCents) / 100.0
                    NSLog("APP AppModel: Loaded penaltyPerMinute from backend: $\(penaltyPerMinute) per minute")
                }
                
                // Save to UserDefaults for persistence
                savePersistedValues()
            } catch let backendError as BackendError {
                switch backendError {
                case .notAuthenticated:
                    weekStatus = nil
                    weekStatusError = "Sign in to view your settlement status."
                default:
                    weekStatusError = backendError.localizedDescription
                }
            } catch {
                weekStatusError = error.localizedDescription
            }
        }
    }

    // MARK: - Navigation
    
    /// Navigate to a screen (ensures main thread)
    func navigate(_ screen: AppScreen) {
        assert(Thread.isMainThread, "navigate() must be called on main thread")
        currentScreen = screen
    }
    
    /// Navigate after yielding to let system UI settle
    /// Now async and awaitable to ensure navigation completes
    func navigateAfterYield(_ screen: AppScreen) async {
        await Task.yield() // Let the runloop present/dismiss system UI
        await MainActor.run {
            navigate(screen)
        }
    }
    
    // MARK: - Deep Link Handling
    
    /// Handle custom URL deep links (payattentionclub://...)
    func handleDeepLink(_ url: URL) {
        NSLog("DEEPLINK AppModel: Handling URL %@", url.absoluteString)
        
        guard url.scheme?.lowercased() == "payattentionclub" else {
            NSLog("DEEPLINK AppModel: Unsupported scheme %@", url.scheme ?? "nil")
            return
        }
        
        let host = url.host?.lowercased() ?? ""
        switch host {
        case "weekly-results":
            NSLog("DEEPLINK AppModel: Navigating to bulletin view for weekly results")
            navigate(.bulletin)
        case "monitor":
            NSLog("DEEPLINK AppModel: Navigating to monitor view")
            navigate(.monitor)
        default:
            NSLog("DEEPLINK AppModel: No handler for host %@", host)
        }
    }
    
    // MARK: - Authorization Calculation
    
    /// Fetch authorization amount from backend (single source of truth)
    /// This calls the same calculation function that rpc_create_commitment uses.
    /// Backend calculates deadline internally (single source of truth).
    func fetchAuthorizationAmount() async -> Double {
        do {
            // Backend calculates deadline internally - no need to pass it
            let response = try await BackendClient.shared.previewMaxCharge(
                limitMinutes: Int(limitMinutes),
                penaltyPerMinuteCents: Int(penaltyPerMinute * 100),
                selectedApps: selectedApps
            )
            // Store preview deadline for Test 5 comparison
            NSLog("🧪 TEST 5 - PREVIEW: iOS app received deadline from backend: \(response.deadlineDate) at \(Date().ISO8601Format())")
            return response.maxChargeDollars
        } catch {
            #if DEBUG
            NSLog("AUTH AppModel: ❌ Failed to fetch authorization amount: \(error)")
            NSLog("AUTH AppModel: Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                NSLog("AUTH AppModel: Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            #endif
            // Fallback to minimum if backend call fails
            return 5.0
        }
    }
    
    /// Local fallback calculation (used only if backend is unreachable)
    /// DEPRECATED: Use fetchAuthorizationAmount() instead
    func calculateAuthorizationAmount() -> Double {
        // Simplified fallback - just return minimum $5 or estimate
        // The real calculation is in the backend
        return 5.0
    }
    
    // MARK: - Date Utilities
    
    /// Refresh cached deadline date (call when deadline might have changed)
    func refreshCachedDeadline() {
        // Prioritize stored deadline from commitment (from backend, compressed in testing mode)
        // Fall back to calculated deadline if no stored deadline exists
        let newDeadline: Date
        if let storedDeadline = UsageTracker.shared.getCommitmentDeadline() {
            // Use stored deadline (from backend, matches testing mode if enabled)
            newDeadline = storedDeadline
            NSLog("RESET AppModel: ✅ Using stored deadline from commitment: \(newDeadline)")
        } else if let cached = cachedNextMondayNoonEST, cached > Date() {
            // Use cached calculated deadline
            newDeadline = cached
        } else {
            // Calculate new deadline (fallback only)
            newDeadline = getNextMondayNoonEST()
        }
        
        cachedNextMondayNoonEST = newDeadline
        cachedDeadlineDate = newDeadline
        // Update countdown model with new deadline (if it exists)
        countdownModel?.updateDeadline(newDeadline)
    }
    
    /// Get next Monday noon EST (uses cached value if available)
    func getNextMondayNoonEST() -> Date {
        // Return cached value if available and still valid (not past)
        if let cached = cachedNextMondayNoonEST, cached > Date() {
            return cached
        }
        
        // Recalculate and cache
        let calculated = calculateNextMondayNoonEST()
        cachedNextMondayNoonEST = calculated
        return calculated
    }
    
    /// Calculate next Monday noon EST (expensive operation - should be cached)
    private func calculateNextMondayNoonEST() -> Date {
        let calendar = Calendar.current
        var estCalendar = calendar
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        let now = Date()
        var components = estCalendar.dateComponents([.year, .month, .day, .weekday, .hour], from: now)
        
        // Find next Monday
        if let weekday = components.weekday {
            let daysUntilMonday = (9 - weekday) % 7
            if daysUntilMonday == 0 && (components.hour ?? 0) < 12 {
                // Today is Monday and before noon, use today
                components.hour = 12
                components.minute = 0
                components.second = 0
            } else {
                // Find next Monday
                let daysToAdd = daysUntilMonday == 0 ? 7 : daysUntilMonday
                components.day = (components.day ?? 0) + daysToAdd
                components.hour = 12
                components.minute = 0
                components.second = 0
            }
        }
        
        return estCalendar.date(from: components) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
    }
    
    /// Format countdown timer (DD:HH:MM:SS)
    /// Uses cached deadline date for fast calculation
    func formatCountdown() -> String {
        let now = Date()
        let nextMondayNoon = getNextMondayNoonEST()
        let timeInterval = nextMondayNoon.timeIntervalSince(now)
        
        if timeInterval <= 0 {
            // Deadline passed - refresh cache for next deadline
            refreshCachedDeadline()
            return "00:00:00:00"
        }
        
        let days = Int(timeInterval) / 86400
        let hours = (Int(timeInterval) % 86400) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        
        return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
    }
    
    // MARK: - Penalty Calculation
    
    /// Calculate current penalty based on usage
    func updateCurrentPenalty() {
        let usageMinutes = Double(currentUsageSeconds - baselineUsageSeconds) / 60.0
        let limitMinutes = self.limitMinutes
        let excessMinutes = max(0, usageMinutes - limitMinutes)
        currentPenalty = excessMinutes * penaltyPerMinute
    }
    
    // MARK: - Persistence
    
    private func loadPersistedValues() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub2.0.app") else {
            return
        }
        
        // Load limitMinutes - use default only if not previously saved
        if userDefaults.object(forKey: "limitMinutes") != nil {
            limitMinutes = userDefaults.double(forKey: "limitMinutes")
        } else {
            limitMinutes = 21 * 60 // Default 21 hours for first-time users
        }
        
        // Load penaltyPerMinute - use default only if not previously saved
        if userDefaults.object(forKey: "penaltyPerMinute") != nil {
            penaltyPerMinute = userDefaults.double(forKey: "penaltyPerMinute")
        } else {
            penaltyPerMinute = 0.10 // Default $0.10 for first-time users
        }
        
        // Load selectedApps - restore previous commit's selection
        if let data = userDefaults.data(forKey: "selectedApps"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selectedApps = decoded
        } else {
            selectedApps = FamilyActivitySelection() // Default: 0 apps for first-time users
        }
        
        baselineUsageSeconds = userDefaults.integer(forKey: "baselineUsageSeconds")
        currentUsageSeconds = userDefaults.integer(forKey: "currentUsageSeconds")
        
        // Load authorizationAmount
        if userDefaults.object(forKey: "authorizationAmount") != nil {
            authorizationAmount = userDefaults.double(forKey: "authorizationAmount")
        }
    }
    
    func savePersistedValues() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub2.0.app") else {
            return
        }
        
        userDefaults.set(limitMinutes, forKey: "limitMinutes")
        userDefaults.set(penaltyPerMinute, forKey: "penaltyPerMinute")
        userDefaults.set(baselineUsageSeconds, forKey: "baselineUsageSeconds")
        userDefaults.set(authorizationAmount, forKey: "authorizationAmount")
        
        // Save selectedApps - persist for next commit
        if let encoded = try? JSONEncoder().encode(selectedApps) {
            userDefaults.set(encoded, forKey: "selectedApps")
        }
        
        // Removed synchronize() - it can block and is not needed
        // UserDefaults writes are automatically persisted
    }
}

enum AppScreen {
    case loading
    case intro
    case setup
    case screenTimeAccess
    case authorization
    case monitor
    case bulletin
}

