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
    
    init() {
        NSLog("MARKERS AppModel: init() called")
        print("MARKERS AppModel: init() called")
        fflush(stdout)
        
        // Load persisted values from App Group
        loadPersistedValues()
        
        // Auto-navigate to setup after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSLog("MARKERS AppModel: Navigating to setup")
            print("MARKERS AppModel: Navigating to setup")
            fflush(stdout)
            self.navigate(.setup)
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
    
    // MARK: - Authorization Calculation
    
    /// Calculate authorization amount based on formula
    func calculateAuthorizationAmount() -> Double {
        let now = Date()
        let nextMondayNoon = getNextMondayNoonEST()
        let hoursUntilDeadline = nextMondayNoon.timeIntervalSince(now) / 3600.0
        let hoursRemaining = max(0, hoursUntilDeadline - (limitMinutes / 60.0))
        
        let appCount = Double(selectedApps.applicationTokens.count)
        let categoryCount = Double(selectedApps.categoryTokens.count)
        let totalSelections = appCount + categoryCount
        
        // Formula components (coefficients TBD - adjust as needed)
        let timeComponent = max(0, hoursRemaining) * 0.5
        let penaltyComponent = penaltyPerMinute * 10.0
        let selectionComponent = totalSelections * 2.0
        
        let calculated = timeComponent + penaltyComponent + selectionComponent
        
        // Clamp between 5 and 1000
        return max(5.0, min(1000.0, calculated))
    }
    
    // MARK: - Date Utilities
    
    /// Get next Monday noon EST
    func getNextMondayNoonEST() -> Date {
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
    func formatCountdown() -> String {
        let now = Date()
        let nextMondayNoon = getNextMondayNoonEST()
        let timeInterval = nextMondayNoon.timeIntervalSince(now)
        
        if timeInterval <= 0 {
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
        
        limitMinutes = userDefaults.double(forKey: "limitMinutes")
        if limitMinutes == 0 {
            limitMinutes = 21 * 60 // Default
        }
        
        penaltyPerMinute = userDefaults.double(forKey: "penaltyPerMinute")
        if penaltyPerMinute == 0 {
            penaltyPerMinute = 0.10 // Default
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

