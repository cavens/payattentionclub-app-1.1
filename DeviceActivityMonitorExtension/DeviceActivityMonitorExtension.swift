import DeviceActivity
import Foundation
import os.log

/// DeviceActivityMonitorExtension receives callbacks when usage thresholds are reached
/// Writes usage data to App Group so main app can read it
@available(iOS 16.0, *)
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    private let logger = Logger(subsystem: "com.payattentionclub.app.monitor", category: "MonitorExtension")
    
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        
        NSLog("MARKERS MonitorExtension: 🟢 intervalDidStart for %@", activity.rawValue)
        print("MARKERS MonitorExtension: 🟢 intervalDidStart for \(activity.rawValue)")
        logger.info("MARKERS MonitorExtension: 🟢 intervalDidStart for \(activity.rawValue)")
        fflush(stdout)
        
        // Store interval start time in App Group
        storeIntervalStart(activity: activity)
        
        // Reset consumed minutes when interval starts
        storeConsumedMinutes(0.0)
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        
        NSLog("MARKERS MonitorExtension: 🔴 intervalDidEnd for %@", activity.rawValue)
        
        // Store interval end time
        storeIntervalEnd(activity: activity)
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        NSLog("MARKERS MonitorExtension: ⚠️⚠️⚠️ THRESHOLD REACHED!")
        print("MARKERS MonitorExtension: ⚠️⚠️⚠️ THRESHOLD REACHED!")
        logger.critical("MARKERS MonitorExtension: ⚠️⚠️⚠️ THRESHOLD REACHED!")
        
        NSLog("MARKERS MonitorExtension: Event: %@", event.rawValue)
        print("MARKERS MonitorExtension: Event: \(event.rawValue)")
        
        NSLog("MARKERS MonitorExtension: Activity: %@", activity.rawValue)
        print("MARKERS MonitorExtension: Activity: \(activity.rawValue)")
        fflush(stdout)
        
        // Extract minutes from event name (e.g., "5min", "10min", "15min")
        let consumedMinutes = extractMinutesFromEvent(event.rawValue)
        
        NSLog("MARKERS MonitorExtension: Extracted minutes: %.1f", consumedMinutes)
        print("MARKERS MonitorExtension: Extracted minutes: \(consumedMinutes)")
        fflush(stdout)
        
        // Store consumed minutes in App Group
        let timestamp = Date().timeIntervalSince1970
        storeConsumedMinutes(consumedMinutes)
        storeLastThresholdEvent(event.rawValue)
        storeLastThresholdTimestamp(timestamp)
        
        NSLog("MARKERS MonitorExtension: ✅ Stored in App Group: consumedMinutes=%.1f, timestamp=%.0f", consumedMinutes, timestamp)
        print("MARKERS MonitorExtension: ✅ Stored in App Group: consumedMinutes=\(consumedMinutes), timestamp=\(timestamp)")
        logger.info("MARKERS MonitorExtension: ✅ Stored in App Group: consumedMinutes=\(consumedMinutes)")
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
    
    // MARK: - Helpers
    
    private func extractMinutesFromEvent(_ eventName: String) -> Double {
        // Extract number from event name (e.g., "5min" -> 5.0, "10min" -> 10.0)
        let pattern = #"(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: eventName, range: NSRange(eventName.startIndex..., in: eventName)),
           let range = Range(match.range(at: 1), in: eventName),
           let minutes = Double(eventName[range]) {
            return minutes
        }
        return 0.0
    }
}

