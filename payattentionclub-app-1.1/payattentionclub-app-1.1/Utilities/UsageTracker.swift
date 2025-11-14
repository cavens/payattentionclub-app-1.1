import Foundation
import os.log

/// Utility for reading and writing usage data to App Group
/// Data is written by DeviceActivityMonitorExtension and read by main app
@MainActor
class UsageTracker {
    static let shared = UsageTracker()
    private let logger = Logger(subsystem: "com.payattentionclub.app", category: "UsageTracker")
    
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    
    private init() {}
    
    // MARK: - Baseline Storage
    
    /// Store baseline time when "Lock in" is pressed
    func storeBaselineTime(_ time: TimeInterval) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(time, forKey: "baselineTimeSpent")
        userDefaults.set(Date().timeIntervalSince1970, forKey: "baselineTimestamp")
        userDefaults.synchronize()
    }
    
    /// Get baseline time
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getBaselineTime() -> TimeInterval {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0.0
        }
        return userDefaults.double(forKey: "baselineTimeSpent")
    }
    
    // MARK: - Monitor Extension Data Reading
    
    /// Get current consumed minutes from Monitor Extension (via App Group)
    /// This is written by Monitor Extension when thresholds are reached
    /// NOTE: No synchronize() - not needed and can block main thread
    func getConsumedMinutes() -> Double {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0.0
        }
        
        return userDefaults.double(forKey: "consumedMinutes")
    }
    
    /// Get current time spent from the last threshold event
    /// Uses smart threshold distribution: 1-min early, 5-min regular, 1-min final
    /// Max undercount: ≤5 minutes globally, ≤1 minute in early/final windows
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getCurrentTimeSpent() -> TimeInterval {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0.0
        }
        
        // Read consumed minutes from last threshold event (no synchronize() - not needed and can block)
        let consumedMinutes = userDefaults.double(forKey: "consumedMinutes")
        
        // Return consumed minutes directly (no simulation)
        // With smart threshold distribution: max undercount ≤5 min (≤1 min in early/final windows)
        return consumedMinutes * 60.0 // Convert to seconds
    }
    
    // MARK: - Commitment Deadline Storage
    
    /// Store commitment deadline when "Lock in" is pressed
    func storeCommitmentDeadline(_ deadline: Date) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(deadline.timeIntervalSince1970, forKey: "commitmentDeadline")
        userDefaults.synchronize()
    }
    
    /// Get commitment deadline
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getCommitmentDeadline() -> Date? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        let timestamp = userDefaults.double(forKey: "commitmentDeadline")
        if timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
    
    /// Check if commitment deadline has passed
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func isCommitmentDeadlinePassed() -> Bool {
        guard let deadline = getCommitmentDeadline() else {
            // No deadline stored means no active commitment
            return true
        }
        return Date() >= deadline
    }
    
    /// Clear expired monitoring state (called when deadline has passed)
    func clearExpiredMonitoringState() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "monitoringSelectionSet")
        userDefaults.removeObject(forKey: "commitmentDeadline")
        userDefaults.synchronize()
    }
    
    /// Check if monitoring flag is set (without checking deadline)
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func isMonitoringFlagSet() -> Bool {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return false
        }
        return userDefaults.bool(forKey: "monitoringSelectionSet")
    }
    
    /// Check if monitoring is active (also checks if deadline has passed)
    func isMonitoringActive() -> Bool {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("RESET UsageTracker: ❌ No UserDefaults access")
            print("RESET UsageTracker: ❌ No UserDefaults access")
            fflush(stdout)
            return false
        }
        
        let flagIsSet = userDefaults.bool(forKey: "monitoringSelectionSet")
        NSLog("RESET UsageTracker: monitoringSelectionSet flag: %@", flagIsSet ? "true" : "false")
        print("RESET UsageTracker: monitoringSelectionSet flag: \(flagIsSet)")
        fflush(stdout)
        
        // If flag is not set, monitoring is not active
        if !flagIsSet {
            NSLog("RESET UsageTracker: Monitoring flag not set, returning false")
            print("RESET UsageTracker: Monitoring flag not set, returning false")
            fflush(stdout)
            return false
        }
        
        // Flag is set - check if deadline exists
        let deadline = getCommitmentDeadline()
        if deadline == nil {
            // Flag is set but no deadline stored - this is an orphaned state
            // Clear it and treat as inactive
            NSLog("RESET UsageTracker: ⚠️ WARNING: monitoringSelectionSet is true but NO deadline stored! Clearing orphaned state.")
            print("RESET UsageTracker: ⚠️ WARNING: monitoringSelectionSet is true but NO deadline stored! Clearing orphaned state.")
            fflush(stdout)
            clearExpiredMonitoringState()
            return false
        }
        
        // Check if deadline has passed
        let deadlinePassed = isCommitmentDeadlinePassed()
        let currentDate = Date()
        NSLog("RESET UsageTracker: Deadline: %@, Current: %@, Passed: %@", String(describing: deadline!), String(describing: currentDate), deadlinePassed ? "YES" : "NO")
        print("RESET UsageTracker: Deadline: \(deadline!), Current: \(currentDate), Passed: \(deadlinePassed)")
        fflush(stdout)
        
        if deadlinePassed {
            // Deadline has passed - clear expired state
            NSLog("RESET UsageTracker: ⏰ Deadline has passed, clearing expired monitoring state")
            print("RESET UsageTracker: ⏰ Deadline has passed, clearing expired monitoring state")
            fflush(stdout)
            clearExpiredMonitoringState()
            return false
        }
        
        // Flag is set and deadline hasn't passed
        NSLog("RESET UsageTracker: ✅ Monitoring is ACTIVE (flag set, deadline not passed)")
        print("RESET UsageTracker: ✅ Monitoring is ACTIVE (flag set, deadline not passed)")
        fflush(stdout)
        return true
    }
}

