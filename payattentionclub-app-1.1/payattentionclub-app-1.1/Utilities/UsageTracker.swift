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
    func getBaselineTime() -> TimeInterval {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0.0
        }
        return userDefaults.double(forKey: "baselineTimeSpent")
    }
    
    // MARK: - Monitor Extension Data Reading
    
    /// Get current consumed minutes from Monitor Extension (via App Group)
    /// This is written by Monitor Extension when thresholds are reached
    func getConsumedMinutes() -> Double {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0.0
        }
        
        userDefaults.synchronize()
        return userDefaults.double(forKey: "consumedMinutes")
    }
    
    /// Calculate current time spent with simulation between thresholds
    /// IMPORTANT: Only simulates if we have actual threshold data (real usage detected)
    func getCurrentTimeSpent() -> TimeInterval {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("MARKERS UsageTracker: ❌ Could not access App Group")
            return 0.0
        }
        
        userDefaults.synchronize()
        
        // Read all relevant values
        let consumedMinutes = userDefaults.double(forKey: "consumedMinutes")
        let consumedMinutesTimestamp = userDefaults.double(forKey: "consumedMinutesTimestamp")
        let lastThresholdTime = userDefaults.double(forKey: "lastThresholdTimestamp")
        let lastThresholdEvent = userDefaults.string(forKey: "lastThresholdEvent") ?? "none"
        
        // Multiple logging methods to ensure visibility
        NSLog("MARKERS UsageTracker: 📊 Reading App Group data:")
        print("MARKERS UsageTracker: 📊 Reading App Group data:")
        logger.info("MARKERS UsageTracker: 📊 Reading App Group data:")
        
        NSLog("MARKERS   - consumedMinutes: %.2f", consumedMinutes)
        print("MARKERS   - consumedMinutes: \(consumedMinutes)")
        
        NSLog("MARKERS   - lastThresholdTime: %.0f", lastThresholdTime)
        print("MARKERS   - lastThresholdTime: \(lastThresholdTime)")
        
        NSLog("MARKERS   - lastThresholdEvent: %@", lastThresholdEvent)
        print("MARKERS   - lastThresholdEvent: \(lastThresholdEvent)")
        fflush(stdout)
        
        // CRITICAL: Only simulate if we have actual threshold data (real usage detected)
        // If lastThresholdTime is 0, no threshold events have fired yet = no real usage
        if lastThresholdTime > 0 && consumedMinutes > 0 {
            // We have real threshold data - simulate progress since last event
            let timeSinceLastThreshold = Date().timeIntervalSince1970 - lastThresholdTime
            let minutesSinceLastThreshold = timeSinceLastThreshold / 60.0
            
            // Only simulate if we're within a reasonable window (don't simulate forever)
            // Cap simulation at 2 minutes past last threshold (prevents runaway simulation)
            let cappedSimulation = min(minutesSinceLastThreshold, 2.0)
            let simulatedMinutes = consumedMinutes + cappedSimulation
            
            NSLog("MARKERS UsageTracker: ✅ Real usage detected - simulating: %.2f (consumed) + %.2f (since threshold) = %.2f minutes",
                  consumedMinutes, cappedSimulation, simulatedMinutes)
            print("MARKERS UsageTracker: ✅ Real usage detected - simulating: \(consumedMinutes) + \(cappedSimulation) = \(simulatedMinutes) minutes")
            fflush(stdout)
            
            return simulatedMinutes * 60.0 // Convert to seconds
        }
        
        // No threshold data yet - return 0 (no real usage detected)
        if consumedMinutes == 0 && lastThresholdTime == 0 {
            NSLog("MARKERS UsageTracker: ⚠️ No threshold events fired yet - no real usage detected")
            print("MARKERS UsageTracker: ⚠️ No threshold events fired yet - no real usage detected")
            NSLog("MARKERS UsageTracker: 💡 Make sure you're actually USING the selected apps!")
            print("MARKERS UsageTracker: 💡 Make sure you're actually USING the selected apps!")
            fflush(stdout)
        }
        
        return consumedMinutes * 60.0 // Convert to seconds (will be 0 if no events)
    }
    
    /// Check if monitoring is active
    func isMonitoringActive() -> Bool {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return false
        }
        return userDefaults.bool(forKey: "monitoringSelectionSet")
    }
}

