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
    
    init() {
        // Minimal initialization - just set defaults
        // Heavy work deferred to finishInitialization() which is called after UI renders
    }
    
    /// Finish initialization after UI has rendered (called from LoadingView.onAppear)
    func finishInitialization() async {
        guard !isInitialized else { 
            return 
        }
        isInitialized = true
        
        // Initialize countdown model (lightweight operation)
        let deadline = getNextMondayNoonEST()
        countdownModel = CountdownModel(deadline: deadline)
        refreshCachedDeadline()
        
        // Wait for loading animation to complete before navigating
        // This ensures user sees the loading screen logo
        try? await Task.sleep(nanoseconds: 2_700_000_000) // 2.7 seconds (0.6s fade in + 1.5s stay + 0.6s fade out)
        
        // Check for existing commitment via backend (avoids UserDefaults reads)
        // This determines which screen to show on app restart
        await checkForExistingCommitmentAndNavigate()
    }
    
    /// Check if user has an active commitment and navigate to appropriate screen
    /// Uses backend API instead of UserDefaults to avoid startup hangs
    private func checkForExistingCommitmentAndNavigate() async {
        // Check if user is authenticated
        let isAuth = await BackendClient.shared.isAuthenticated
        guard isAuth else {
            NSLog("INIT AppModel: ⚠️ Not authenticated, navigating to setup")
        navigate(.setup)
            return
        }
        
        // Try to fetch week status (this will succeed if commitment exists for current week)
        do {
            // Pass nil to get current week's status
            let weekStatus = try await BackendClient.shared.fetchWeekStatus(weekStartDate: nil)
            
            // Check if commitment exists by looking at userMaxChargeCents
            // This is more reliable than just checking weekEndDate
            let hasCommitment = weekStatus.userMaxChargeCents > 0
            
            NSLog("INIT AppModel: 🔍 Week status check - userMaxChargeCents: \(weekStatus.userMaxChargeCents), commitmentCreatedAt: \(weekStatus.commitmentCreatedAt ?? "nil")")
            
            if !hasCommitment {
                // No commitment found - go to setup
                NSLog("INIT AppModel: ⚠️ No commitment found (userMaxChargeCents: \(weekStatus.userMaxChargeCents)), navigating to setup")
                navigate(.setup)
                return
            }
            
            // Commitment exists - verify it's for the current week
            // Check if deadline is within the next 7 days (to ensure it's current week, not a past week)
            guard let weekEndDateString = weekStatus.weekEndDate else {
                // Commitment exists but no deadline date - this shouldn't happen, but treat as no commitment
                NSLog("INIT AppModel: ⚠️ Commitment found but no deadline date (userMaxChargeCents: \(weekStatus.userMaxChargeCents)), treating as no commitment, navigating to setup")
                navigate(.setup)
                return
            }
            
            // Parse deadline to verify it's for the current week
            var deadline: Date?
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            deadline = isoFormatter.date(from: weekEndDateString)
            
            if deadline == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                deadline = isoFormatter.date(from: weekEndDateString)
            }
            
            // Try date-only format if ISO8601 fails
            if deadline == nil {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
                if let dateOnly = dateFormatter.date(from: weekEndDateString) {
                    var estCalendar = Calendar.current
                    estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
                    var components = estCalendar.dateComponents([.year, .month, .day], from: dateOnly)
                    components.hour = 12
                    components.minute = 0
                    components.second = 0
                    deadline = estCalendar.date(from: components)
                }
            }
            
            guard let deadline = deadline else {
                // Could not parse deadline - treat as no commitment
                NSLog("INIT AppModel: ⚠️ Could not parse deadline date: \(weekEndDateString), treating as no commitment, navigating to setup")
                navigate(.setup)
                return
            }
            
            // Verify deadline is for the current week (within next 7 days)
            // If deadline is more than 7 days away, it's probably from a past week calculation error
            let now = Date()
            let daysUntilDeadline = deadline.timeIntervalSince(now) / 86400.0 // Convert to days
            
            if daysUntilDeadline > 7 {
                // Deadline is more than 7 days away - this is likely a stale commitment
                NSLog("INIT AppModel: ⚠️ Commitment found but deadline is \(Int(daysUntilDeadline)) days away (more than 7 days), treating as stale commitment, navigating to setup")
                navigate(.setup)
                return
            }
            
            if daysUntilDeadline < -1 {
                // Deadline was more than 1 day ago - commitment is expired
                NSLog("INIT AppModel: ⚠️ Commitment found but deadline was \(Int(-daysUntilDeadline)) days ago, treating as expired, navigating to setup")
                navigate(.setup)
                return
            }
            
            // Verify commitment was created recently (within last 7 days)
            // This helps catch stale test commitments
            if let commitmentCreatedAtString = weekStatus.commitmentCreatedAt {
                var commitmentCreatedAt: Date?
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                commitmentCreatedAt = isoFormatter.date(from: commitmentCreatedAtString)
                
                if commitmentCreatedAt == nil {
                    isoFormatter.formatOptions = [.withInternetDateTime]
                    commitmentCreatedAt = isoFormatter.date(from: commitmentCreatedAtString)
                }
                
                if let commitmentCreatedAt = commitmentCreatedAt {
                    let daysSinceCreation = now.timeIntervalSince(commitmentCreatedAt) / 86400.0
                    NSLog("INIT AppModel: 📅 Commitment created \(String(format: "%.1f", daysSinceCreation)) days ago")
                    if daysSinceCreation > 7 {
                        // Commitment was created more than 7 days ago - treat as stale
                        NSLog("INIT AppModel: ⚠️ Commitment found but was created \(Int(daysSinceCreation)) days ago (more than 7 days), treating as stale commitment, navigating to setup")
                        navigate(.setup)
                        return
                    }
                } else {
                    NSLog("INIT AppModel: ⚠️ Could not parse commitmentCreatedAt: \(commitmentCreatedAtString)")
                }
            } else {
                // No commitmentCreatedAt - this shouldn't happen with the updated RPC, but treat as no commitment to be safe
                NSLog("INIT AppModel: ⚠️ Commitment found but no commitmentCreatedAt field (RPC may not be updated), treating as no commitment, navigating to setup")
                navigate(.setup)
                return
            }
            
            // Additional check: Verify monitoring is actually active
            // If there's a commitment but monitoring isn't active, it's likely a stale/test commitment
            let isMonitoringActive = UsageTracker.shared.isMonitoringActive()
            if !isMonitoringActive {
                NSLog("INIT AppModel: ⚠️ Commitment found but monitoring is not active, treating as stale commitment, navigating to setup")
                navigate(.setup)
                return
            }
            
            // Deadline is valid and within current week - compare deadline to current time
            let timeUntilDeadline = deadline.timeIntervalSince(now)
            
            NSLog("INIT AppModel: 📅 Commitment found - deadline: \(weekEndDateString) (\(deadline)), now: \(now), time until deadline: \(Int(timeUntilDeadline / 3600)) hours")
            
            // Check if deadline has passed (with 24-hour grace period)
            // If deadline has passed and grace period has expired, go to setup (not bulletin)
            // Only go to bulletin if we're within the grace period after deadline
            if now >= deadline {
                // Deadline has passed - check if we're within grace period
                if let weekGraceExpiresAtString = weekStatus.weekGraceExpiresAt {
                    // Parse grace expiration date
                    var graceExpires: Date?
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    graceExpires = isoFormatter.date(from: weekGraceExpiresAtString)
                    
                    if graceExpires == nil {
                        isoFormatter.formatOptions = [.withInternetDateTime]
                        graceExpires = isoFormatter.date(from: weekGraceExpiresAtString)
                    }
                    
                    if let graceExpires = graceExpires, now < graceExpires {
                        // Within grace period - go to bulletin
                        NSLog("INIT AppModel: ✅ Commitment found, deadline passed but within grace period (\(weekEndDateString)), navigating to bulletin")
                        self.weekStatus = weekStatus
                        navigate(.bulletin)
                    } else {
                        // Grace period expired - commitment is over, go to setup
                        NSLog("INIT AppModel: ⚠️ Commitment found but deadline and grace period expired (\(weekEndDateString)), navigating to setup")
                        navigate(.setup)
                    }
                } else {
                    // No grace period info - if deadline passed more than 24 hours ago, go to setup
                    // Otherwise go to bulletin
                    let hoursSinceDeadline = -timeUntilDeadline / 3600.0
                    if hoursSinceDeadline > 24 {
                        // More than 24 hours past deadline - go to setup
                        NSLog("INIT AppModel: ⚠️ Commitment found but deadline passed more than 24h ago (\(weekEndDateString)), navigating to setup")
                        navigate(.setup)
                    } else {
                        // Within 24 hours of deadline - go to bulletin
                        NSLog("INIT AppModel: ✅ Commitment found, deadline passed recently (\(weekEndDateString)), navigating to bulletin")
                        self.weekStatus = weekStatus
                        navigate(.bulletin)
                    }
                }
            } else {
                // Active commitment (deadline in future) - go to monitor
                NSLog("INIT AppModel: ✅ Active commitment found (deadline: \(weekEndDateString), \(Int(timeUntilDeadline / 3600))h remaining), navigating to monitor")
                self.weekStatus = weekStatus
                authorizationAmount = Double(weekStatus.userMaxChargeCents) / 100.0
                navigate(.monitor)
            }
            
        } catch let backendError as BackendError {
            switch backendError {
            case .notAuthenticated:
                // Not authenticated - go to setup
                NSLog("INIT AppModel: ⚠️ Not authenticated, navigating to setup")
                navigate(.setup)
            case .serverError(let message) where message.contains("No week status available"):
                // No commitment exists for current week - go to setup
                NSLog("INIT AppModel: ⚠️ No commitment found for current week: \(message), navigating to setup")
                navigate(.setup)
            default:
                // Other error - go to setup
                NSLog("INIT AppModel: ⚠️ Error checking commitment: \(backendError.localizedDescription), navigating to setup")
                weekStatusError = backendError.localizedDescription
                navigate(.setup)
            }
        } catch {
            // Generic error - go to setup
            NSLog("INIT AppModel: ⚠️ Failed to check commitment: \(error.localizedDescription), navigating to setup")
            weekStatusError = error.localizedDescription
            navigate(.setup)
        }
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
    func navigateAfterYield(_ screen: AppScreen) {
        Task { @MainActor in
            await Task.yield() // Let the runloop present/dismiss system UI
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
    func fetchAuthorizationAmount() async -> Double {
        do {
            let deadline = getNextMondayNoonEST()
            let response = try await BackendClient.shared.previewMaxCharge(
                deadlineDate: deadline,
                limitMinutes: Int(limitMinutes),
                penaltyPerMinuteCents: Int(penaltyPerMinute * 100),
                selectedApps: selectedApps
            )
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
        // Only recalculate if cache is empty or expired
        let newDeadline: Date
        if let cached = cachedNextMondayNoonEST, cached > Date() {
            newDeadline = cached
        } else {
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
    case setup
    case screenTimeAccess
    case authorization
    case monitor
    case bulletin
}

