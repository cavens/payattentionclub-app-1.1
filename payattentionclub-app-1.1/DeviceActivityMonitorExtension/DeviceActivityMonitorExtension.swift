import DeviceActivity
import Foundation

/// Represents a single threshold event with timestamp and consumed minutes
/// Stored in App Group to track usage history
struct ThresholdHistoryEntry: Codable {
    /// Timestamp when threshold was reached (TimeInterval since 1970)
    let timestamp: TimeInterval
    
    /// Consumed minutes at this threshold
    let consumedMinutes: Double
    
    /// Seconds value from the threshold event
    let seconds: Int
    
    /// Create a new threshold history entry
    init(timestamp: TimeInterval, consumedMinutes: Double, seconds: Int) {
        self.timestamp = timestamp
        self.consumedMinutes = consumedMinutes
        self.seconds = seconds
    }
}

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
        
        // Clear threshold history when interval starts (new commitment period)
        clearThresholdHistory()
        
        // Store interval start time in App Group
        storeIntervalStart(activity: activity)
        
        // CRITICAL: Clear baseline when interval starts
        // The baseline will be set from the FIRST threshold event's absolute seconds
        // This ensures we use actual Screen Time usage, not a potentially corrupted consumedMinutes value
        clearIntervalBaseline()
        NSLog("MARKERS MonitorExtension: 📊 Cleared interval baseline (will be set from first threshold event)")
        fflush(stdout)
        
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
        
        // Extract seconds from event name (this is cumulative Screen Time usage)
        let absoluteSeconds = extractSecondsFromEvent(event.rawValue)
        let absoluteConsumedMinutes = Double(absoluteSeconds) / 60.0
        
        // CRITICAL: Get or set baseline from first threshold event
        // DeviceActivity threshold events are cumulative (total Screen Time usage),
        // not relative to commitment start. We use the FIRST threshold event's absolute seconds
        // as the baseline, ensuring we track actual Screen Time, not corrupted consumedMinutes values.
        //
        // IMPORTANT: The threshold event name (e.g., "t_60s") represents the threshold value we set,
        // which corresponds to total usage since commitment start. The absoluteSeconds from the event
        // is the cumulative Screen Time (including pre-commitment usage). We use the threshold value
        // (extracted from event name) as the relative usage, not the difference from baseline.
        let baselineSeconds = getIntervalBaselineSeconds()
        let isFirstThreshold = (baselineSeconds == 0)
        
        let relativeSeconds: Int
        let relativeConsumedMinutes: Double
        
        if isFirstThreshold {
            // This is the first threshold event - use it as the baseline
            // Store the absolute seconds as baseline for future calculations
            storeIntervalBaselineSeconds(absoluteSeconds)
            // For the first threshold, relative usage equals the threshold value
            // (e.g., if first threshold is at 1 minute, user has used 1 minute total)
            relativeSeconds = absoluteSeconds
            relativeConsumedMinutes = absoluteConsumedMinutes
            NSLog("MARKERS MonitorExtension: 🎯 FIRST THRESHOLD - Setting baseline to %d sec (%.1f min), relative usage: %d sec (%.1f min)", 
                  absoluteSeconds, absoluteConsumedMinutes, relativeSeconds, relativeConsumedMinutes)
        } else {
            // Subsequent threshold event - the threshold value (absoluteSeconds from event name)
            // represents total usage since commitment start, not the difference from baseline.
            // The baseline is used only for validation/gap detection, not for calculating relative usage.
            // We use the threshold value directly as relative usage (total since commitment start).
            relativeSeconds = absoluteSeconds
            relativeConsumedMinutes = absoluteConsumedMinutes
            NSLog("MARKERS MonitorExtension: 📊 SUBSEQUENT THRESHOLD - Baseline: %d sec, threshold value: %d sec (%.1f min), relative usage: %d sec (%.1f min)", 
                  baselineSeconds, absoluteSeconds, absoluteConsumedMinutes, relativeSeconds, relativeConsumedMinutes)
        }
        
        // Get last threshold seconds to detect gaps
        let lastSeconds = getLastThresholdSeconds()
        
        // Detect gaps (with new variable intervals, gaps can be up to 5 minutes)
        if lastSeconds > 0 && relativeSeconds > lastSeconds {
            let gapSeconds = relativeSeconds - lastSeconds
            // With new strategy: gaps can be up to 5 minutes (300 seconds) in middle, 1 minute (60 seconds) at start/end
            if gapSeconds > 300 {
                NSLog("MARKERS MonitorExtension: ⚠️⚠️⚠️ LARGE GAP DETECTED! Last threshold: %d sec, current: %d sec. Gap: %d seconds (%.1f minutes)", 
                      lastSeconds, relativeSeconds, gapSeconds, Double(gapSeconds) / 60.0)
                fflush(stdout)
            }
        }
        
        // Log threshold (show both absolute and relative)
        NSLog("MARKERS MonitorExtension: 🔔 Threshold: %@ (absolute: %d sec = %.1f min, baseline: %d sec = %.1f min, relative: %d sec = %.1f min)", 
              event.rawValue, absoluteSeconds, absoluteConsumedMinutes, baselineSeconds, Double(baselineSeconds) / 60.0, relativeSeconds, relativeConsumedMinutes)
        fflush(stdout)
        
        // Store RELATIVE consumed minutes in App Group (usage since commitment start)
        let timestamp = Date().timeIntervalSince1970
        storeConsumedMinutes(relativeConsumedMinutes)
        storeLastThresholdEvent(event.rawValue)
        storeLastThresholdTimestamp(timestamp)
        storeLastThresholdSeconds(relativeSeconds)
        
        // Store threshold in history for deadline lookup (use relative values)
        storeThresholdInHistory(timestamp: timestamp, consumedMinutes: relativeConsumedMinutes, seconds: relativeSeconds)
        
        NSLog("MARKERS MonitorExtension: ✅ Stored: consumedMinutes=%.1f (relative), seconds=%d (relative), timestamp=%.0f", 
              relativeConsumedMinutes, relativeSeconds, timestamp)
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
    
    // MARK: - Interval Baseline Tracking
    
    /// Store baseline seconds from first threshold event (to calculate relative usage)
    /// The baseline is the absolute Screen Time seconds from the first threshold event
    private func storeIntervalBaselineSeconds(_ baselineSeconds: Int) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.set(baselineSeconds, forKey: "intervalBaselineSeconds")
        userDefaults.synchronize()
    }
    
    /// Get baseline seconds for current interval (to calculate relative usage)
    /// Returns 0 if baseline not yet set (first threshold event)
    private func getIntervalBaselineSeconds() -> Int {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0
        }
        return userDefaults.integer(forKey: "intervalBaselineSeconds")
    }
    
    /// Clear baseline when interval starts (will be set from first threshold event)
    private func clearIntervalBaseline() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "intervalBaselineSeconds")
        userDefaults.synchronize()
    }
    
    // MARK: - Threshold History Storage
    
    /// Store threshold event in history array
    /// History is used to find consumedMinutes at deadline time even if app was killed
    private func storeThresholdInHistory(timestamp: TimeInterval, consumedMinutes: Double, seconds: Int) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        
        // Create new entry
        let entry = ThresholdHistoryEntry(
            timestamp: timestamp,
            consumedMinutes: consumedMinutes,
            seconds: seconds
        )
        
        // Read existing history
        var history: [ThresholdHistoryEntry] = []
        if let historyData = userDefaults.data(forKey: "thresholdHistory") {
            if let decoded = try? JSONDecoder().decode([ThresholdHistoryEntry].self, from: historyData) {
                history = decoded
            }
        }
        
        // Append new entry
        history.append(entry)
        
        // Limit history size to prevent unbounded growth (keep last 200 entries)
        // This should be more than enough for a week of usage (even with 1-minute thresholds)
        let maxHistorySize = 200
        if history.count > maxHistorySize {
            history = Array(history.suffix(maxHistorySize))
        }
        
        // Store updated history
        if let encoded = try? JSONEncoder().encode(history) {
            userDefaults.set(encoded, forKey: "thresholdHistory")
            userDefaults.synchronize()
        }
    }
    
    /// Clear threshold history (called when interval starts)
    private func clearThresholdHistory() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "thresholdHistory")
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
