import DeviceActivity
import Foundation

/// DeviceActivityMonitorExtension receives callbacks when usage thresholds are reached
/// Writes usage data to App Group so main app can read it
@available(iOS 16.0, *)
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroupIdentifier = "group.com.payattentionclub2.0.app"
    
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        
        NSLog("MARKERS MonitorExtension: 🟢 intervalDidStart for %@", activity.rawValue)
        fflush(stdout)
        
        // Reset sequence tracking when interval starts
        resetSequenceTracking()
        
        // Store interval start time in App Group
        storeIntervalStart(activity: activity)
        
        // Reset consumed minutes when interval starts
        storeConsumedMinutes(0.0)
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        
        NSLog("MARKERS MonitorExtension: 🔴 intervalDidEnd for %@", activity.rawValue)
        fflush(stdout)
        
        // Store interval end time
        storeIntervalEnd(activity: activity)
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        // Extract seconds from event name
        let seconds = extractSecondsFromEvent(event.rawValue)
        let consumedMinutes = Double(seconds) / 60.0
        
        // Get last threshold seconds to detect gaps
        let lastSeconds = getLastThresholdSeconds()
        
        // Detect gaps (with new variable intervals, gaps can be up to 5 minutes)
        if lastSeconds > 0 && seconds > lastSeconds {
            let gapSeconds = seconds - lastSeconds
            // With new strategy: gaps can be up to 5 minutes (300 seconds) in middle, 1 minute (60 seconds) at start/end
            if gapSeconds > 300 {
                NSLog("MARKERS MonitorExtension: ⚠️⚠️⚠️ LARGE GAP DETECTED! Last threshold: %d sec, current: %d sec. Gap: %d seconds (%.1f minutes)", 
                      lastSeconds, seconds, gapSeconds, Double(gapSeconds) / 60.0)
                fflush(stdout)
            }
        }
        
        // Log threshold
        NSLog("MARKERS MonitorExtension: 🔔 Threshold: %@ (%d seconds = %.1f minutes)", 
              event.rawValue, seconds, consumedMinutes)
        fflush(stdout)
        
        // Store consumed minutes in App Group
        let timestamp = Date().timeIntervalSince1970
        storeConsumedMinutes(consumedMinutes)
        storeLastThresholdEvent(event.rawValue)
        storeLastThresholdTimestamp(timestamp)
        storeLastThresholdSeconds(seconds)
        
        NSLog("MARKERS MonitorExtension: ✅ Stored: consumedMinutes=%.1f, seconds=%d, timestamp=%.0f", 
              consumedMinutes, seconds, timestamp)
        fflush(stdout)
    }
    
    // MARK: - App Group Storage
    
    private func storeIntervalStart(activity: DeviceActivityName) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        let timestamp = Date().timeIntervalSince1970
        userDefaults.set(timestamp, forKey: "monitorIntervalStart_\(activity.rawValue)")
        userDefaults.synchronize()
    }
    
    private func storeIntervalEnd(activity: DeviceActivityName) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        let timestamp = Date().timeIntervalSince1970
        userDefaults.set(timestamp, forKey: "monitorIntervalEnd_\(activity.rawValue)")
        userDefaults.synchronize()
    }
    
    private func storeConsumedMinutes(_ minutes: Double) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(minutes, forKey: "consumedMinutes")
        userDefaults.set(Date().timeIntervalSince1970, forKey: "consumedMinutesTimestamp")
        userDefaults.synchronize()
    }
    
    private func storeLastThresholdEvent(_ eventName: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(eventName, forKey: "lastThresholdEvent")
        userDefaults.synchronize()
    }
    
    private func storeLastThresholdTimestamp(_ timestamp: TimeInterval) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(timestamp, forKey: "lastThresholdTimestamp")
        userDefaults.synchronize()
    }
    
    private func storeLastThresholdSeconds(_ seconds: Int) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(seconds, forKey: "lastThresholdSeconds")
        userDefaults.synchronize()
    }
    
    private func getLastThresholdSeconds() -> Int {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0
        }
        return userDefaults.integer(forKey: "lastThresholdSeconds")
    }
    
    private func resetSequenceTracking() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "lastThresholdSeconds")
        userDefaults.synchronize()
    }
    
    // MARK: - Helpers
    
    private func extractSecondsFromEvent(_ eventName: String) -> Int {
        // Extract seconds from event name
        // New format: "t_60s", "t_300s", etc.
        // Old format (for compatibility): "30sec", "60sec", etc.
        
        // Try new format first: "t_60s" or "t_300s"
        let newPattern = #"t_(\d+)s"#
        if let regex = try? NSRegularExpression(pattern: newPattern),
           let match = regex.firstMatch(in: eventName, range: NSRange(eventName.startIndex..., in: eventName)),
           let range = Range(match.range(at: 1), in: eventName),
           let seconds = Int(eventName[range]) {
            return seconds
        }
        
        // Fallback to old format: "30sec" or "36000sec"
        let oldPattern = #"(\d+)sec"#
        if let regex = try? NSRegularExpression(pattern: oldPattern),
           let match = regex.firstMatch(in: eventName, range: NSRange(eventName.startIndex..., in: eventName)),
           let range = Range(match.range(at: 1), in: eventName),
           let seconds = Int(eventName[range]) {
            return seconds
        }
        
        return 0
    }
    
    private func extractMinutesFromEvent(_ eventName: String) -> Double {
        // Extract minutes from event name (for backward compatibility)
        let seconds = extractSecondsFromEvent(eventName)
        return Double(seconds) / 60.0
    }
}
