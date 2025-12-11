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
    
    /// Helper to add timeout to async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual operation
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            // Return first result (either operation or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private struct TimeoutError: Error {}
    
    init() {
        // Minimal initialization - just set defaults
        // Heavy work deferred to finishInitialization() which is called after UI renders
    }
    
    /// Finish initialization after UI has rendered (called from LoadingView.onAppear)
    func finishInitialization() {
        guard !isInitialized else { return }
        isInitialized = true
        
        // Initialize countdown model (deferred to avoid blocking startup)
        let deadline = getNextMondayNoonEST()
        countdownModel = CountdownModel(deadline: deadline)
        
        // Load persisted values from App Group
        loadPersistedValues()
        
        // Cache deadline date (now that countdownModel exists)
        refreshCachedDeadline()
        
        // Check if monitoring is already active - if so, navigate to monitor screen
        // Otherwise navigate to setup
        // Navigation happens immediately - don't wait for sync
        Task { @MainActor in
            // Small delay to let UI render
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Check if monitoring is active (also checks if deadline has passed)
            let isActive = UsageTracker.shared.isMonitoringActive()
            
            if isActive {
                // Monitoring is active and deadline hasn't passed - navigate to monitor screen
                await refreshUsageFromAppGroup()
                self.navigate(.monitor)
            } else {
                // No active monitoring (either not started or deadline passed) - navigate to setup
                self.navigate(.setup)
            }
        }
        
        // Sync unsynced usage entries on app launch (non-blocking, with timeout)
        // This happens in background and doesn't delay navigation
        Task { @MainActor in
            // Add timeout to prevent long delays if network is slow
            do {
                try await withTimeout(seconds: 5) {
                    try await UsageSyncManager.shared.syncToBackend()
                }
            } catch {
                #if DEBUG
                NSLog("SYNC: Failed to sync on launch (timeout or error): \(error)")
                #endif
                // Don't block app startup if sync fails or times out
            }
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
        guard url.scheme?.lowercased() == "payattentionclub" else { return }
        
        let host = url.host?.lowercased() ?? ""
        switch host {
        case "weekly-results":
            navigate(.bulletin)
        case "monitor":
            navigate(.monitor)
        default:
            break
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
            NSLog("AUTH AppModel: Failed to fetch authorization amount: \(error)")
            #endif
            // Fallback to minimum if backend call fails
            return 5.0
        }
    }
    
    /// Local fallback calculation (used only if backend is unreachable)
    /// DEPRECATED: Use fetchAuthorizationAmount() instead
    func calculateAuthorizationAmountLocal() -> Double {
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
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
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
    }
    
    func savePersistedValues() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
            return
        }
        
        userDefaults.set(limitMinutes, forKey: "limitMinutes")
        userDefaults.set(penaltyPerMinute, forKey: "penaltyPerMinute")
        userDefaults.set(baselineUsageSeconds, forKey: "baselineUsageSeconds")
        
        // Save selectedApps - persist for next commit
        if let encoded = try? JSONEncoder().encode(selectedApps) {
            userDefaults.set(encoded, forKey: "selectedApps")
        }
        
        userDefaults.synchronize()
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

