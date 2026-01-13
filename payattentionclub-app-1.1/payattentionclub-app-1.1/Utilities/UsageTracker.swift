import Foundation
import os.log

/// Utility for reading and writing usage data to App Group
/// Data is written by DeviceActivityMonitorExtension and read by main app
@MainActor
class UsageTracker {
    static let shared = UsageTracker()
    private let logger = Logger(subsystem: "com.payattentionclub2.0.app", category: "UsageTracker")
    
    private let appGroupIdentifier = "group.com.payattentionclub2.0.app"
    
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
    
    /// Reset consumed minutes to 0
    /// This should be called when creating a new commitment to clear any leftover data
    /// Also clears the interval baseline so the extension can track a fresh baseline from the first threshold event
    func resetConsumedMinutes() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(0.0, forKey: "consumedMinutes")
        // Also clear interval baseline (in seconds) so extension can track fresh baseline from first threshold event
        userDefaults.removeObject(forKey: "intervalBaselineSeconds")
        userDefaults.synchronize()
        NSLog("RESET UsageTracker: ✅ Reset consumedMinutes to 0.0 and cleared interval baseline")
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
    
    /// Store commitment ID when "Lock in" is pressed
    func storeCommitmentId(_ commitmentId: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(commitmentId, forKey: "commitmentId")
        userDefaults.synchronize()
    }
    
    /// Get commitment ID
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getCommitmentId() -> String? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return userDefaults.string(forKey: "commitmentId")
    }
    
    /// Store consumedMinutes at deadline time (to prevent post-deadline usage from being included)
    func storeConsumedMinutesAtDeadline(_ minutes: Double) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(minutes, forKey: "consumedMinutesAtDeadline")
        userDefaults.synchronize()
    }
    
    /// Get consumedMinutes at deadline time (to prevent post-deadline usage from being included)
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getConsumedMinutesAtDeadline() -> Double? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        let minutes = userDefaults.double(forKey: "consumedMinutesAtDeadline")
        return minutes > 0 ? minutes : nil
    }
    
    // MARK: - Threshold History
    
    /// Get threshold history from App Group
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getThresholdHistory() -> [ThresholdHistoryEntry] {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return []
        }
        
        guard let historyData = userDefaults.data(forKey: "thresholdHistory") else {
            return []
        }
        
        if let history = try? JSONDecoder().decode([ThresholdHistoryEntry].self, from: historyData) {
            return history
        }
        
        return []
    }
    
    /// Find the last threshold that occurred before the deadline
    /// Returns the consumedMinutes value from that threshold
    /// This allows us to get accurate usage even if the app was killed before deadline
    /// nonisolated: UserDefaults reads are thread-safe, can be called from any thread
    nonisolated func getConsumedMinutesAtDeadlineFromHistory(deadline: Date) -> Double? {
        let deadlineTimestamp = deadline.timeIntervalSince1970
        let history = getThresholdHistory()
        
        // Find the last threshold where timestamp < deadline
        let preDeadlineThresholds = history.filter { $0.timestamp < deadlineTimestamp }
        
        guard let lastThreshold = preDeadlineThresholds.last else {
            // No thresholds found before deadline
            return nil
        }
        
        return lastThreshold.consumedMinutes
    }
    
    /// Clear expired monitoring state (called when deadline has passed)
    func clearExpiredMonitoringState() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "monitoringSelectionSet")
        userDefaults.removeObject(forKey: "commitmentDeadline")
        userDefaults.removeObject(forKey: "commitmentId")
        userDefaults.removeObject(forKey: "consumedMinutesAtDeadline")
        userDefaults.removeObject(forKey: "thresholdHistory") // Clear threshold history when commitment expires
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
            return false
        }
        
        let flagIsSet = userDefaults.bool(forKey: "monitoringSelectionSet")
        
        // If flag is not set, monitoring is not active
        if !flagIsSet {
            return false
        }
        
        // Flag is set - check if deadline exists
        let deadline = getCommitmentDeadline()
        if deadline == nil {
            // Flag is set but no deadline stored - this is an orphaned state
            // Clear it and treat as inactive
            clearExpiredMonitoringState()
            return false
        }
        
        // Check if deadline has passed
        let deadlinePassed = isCommitmentDeadlinePassed()
        
        if deadlinePassed {
            // Deadline has passed - clear expired state
            clearExpiredMonitoringState()
            return false
        }
        
        // Flag is set and deadline hasn't passed
        return true
    }
}

