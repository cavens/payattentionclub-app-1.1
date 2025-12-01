import DeviceActivity
import Foundation
import UserNotifications

/// Local copy of DailyUsageEntry for extension target
struct ExtensionDailyUsageEntry: Codable {
    let date: String
    let totalMinutes: Double
    let baselineMinutes: Double
    let lastUpdatedAt: TimeInterval
    var synced: Bool
    let weekStartDate: String
    let commitmentId: String
    
    var usedMinutes: Int {
        max(0, Int(totalMinutes - baselineMinutes))
    }
}

@available(iOS 16.0, *)
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    
    // Serial queue to ensure only one threshold is processed at a time
    // This prevents race conditions when multiple extension instances process the same threshold
    private static let processingQueue = DispatchQueue(label: "com.payattentionclub.extension.processing", qos: .userInitiated)
    
    override init() {
        super.init()
        NSLog("MONITOR_EXT: 🚀 init")
        print("MONITOR_EXT: 🚀 init")
        fflush(stdout)
    }
    
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        NSLog("MONITOR_EXT: 🟢 intervalDidStart \(activity.rawValue)")
        print("MONITOR_EXT: 🟢 intervalDidStart \(activity.rawValue)")
        fflush(stdout)
        
        // Reset last threshold tracking when interval starts (new day/week)
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "last_threshold_seconds")
        userDefaults.removeObject(forKey: "last_processed_threshold_seconds")
        userDefaults.synchronize()
        NSLog("MONITOR_EXT: 🔄 Reset threshold tracking at interval start")
        print("MONITOR_EXT: 🔄 Reset threshold tracking at interval start")
        fflush(stdout)
        
        // TEMP: visible proof-of-life via local notification
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "PAC Monitor started"
            content.body = "Activity: \(activity.rawValue)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            let request = UNNotificationRequest(
                identifier: "pac_monitor_test_interval",
                content: content,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        NSLog("MONITOR_EXT: 🔔 eventDidReachThreshold \(event.rawValue)")
        print("MONITOR_EXT: 🔔 eventDidReachThreshold \(event.rawValue)")
        fflush(stdout)
        
        // Extract seconds from event name (e.g., "t_300s" -> 300)
        // NOTE: This is the CUMULATIVE threshold value, not the delta
        let thresholdSeconds = extractSeconds(from: event.rawValue)
        let thresholdMinutes = Double(thresholdSeconds) / 60.0
        
        NSLog("MONITOR_EXT: 📊 Threshold reached - thresholdSeconds: \(thresholdSeconds)s = \(thresholdMinutes) min")
        print("MONITOR_EXT: 📊 Threshold reached - thresholdSeconds: \(thresholdSeconds)s = \(thresholdMinutes) min")
        fflush(stdout)
        
        // Update daily usage entry (will calculate delta inside)
        // Use serial queue synchronously to prevent concurrent processing of same threshold
        // This ensures only one threshold is processed at a time, preventing race conditions
        Self.processingQueue.sync {
            self.updateDailyUsageEntry(thresholdSeconds: thresholdSeconds)
        }
    }
    
    /// Extract seconds from event name (e.g., "t_300s" -> 300)
    private func extractSeconds(from eventName: String) -> Int {
        // Remove "t_" prefix and "s" suffix
        let cleaned = eventName.replacingOccurrences(of: "t_", with: "")
            .replacingOccurrences(of: "s", with: "")
        return Int(cleaned) ?? 0
    }
    
    /// Update daily usage entry in App Group
    /// - Parameter thresholdSeconds: The cumulative threshold value in seconds (e.g., 300 = 5 minutes total consumed)
    private func updateDailyUsageEntry(thresholdSeconds: Int) {
        NSLog("MONITOR_EXT: 📝 updateDailyUsageEntry called with thresholdSeconds: \(thresholdSeconds)")
        print("MONITOR_EXT: 📝 updateDailyUsageEntry called with thresholdSeconds: \(thresholdSeconds)")
        fflush(stdout)
        
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("MONITOR_EXT: ❌ Failed to access App Group '\(appGroupIdentifier)'")
            print("MONITOR_EXT: ❌ Failed to access App Group '\(appGroupIdentifier)'")
            fflush(stdout)
            return
        }
        
        // CRITICAL: Atomic idempotency check - must happen FIRST before any other processing
        // Use a serial queue to ensure only one thread processes at a time
        let idempotencyKey = "last_processed_threshold_seconds"
        let lastProcessedThreshold = userDefaults.integer(forKey: idempotencyKey)
        
        // Check if already processed
        if thresholdSeconds == lastProcessedThreshold && lastProcessedThreshold > 0 {
            NSLog("MONITOR_EXT: ⏭️ Already processed threshold \(thresholdSeconds)s, skipping duplicate")
            print("MONITOR_EXT: ⏭️ Already processed threshold \(thresholdSeconds)s, skipping duplicate")
            fflush(stdout)
            return
        }
        
        // Mark as processing IMMEDIATELY (atomic check-and-set)
        // This prevents other concurrent calls from processing the same threshold
        userDefaults.set(thresholdSeconds, forKey: idempotencyKey)
        userDefaults.synchronize() // Force immediate write
        
        NSLog("MONITOR_EXT: ✅ Successfully accessed App Group")
        print("MONITOR_EXT: ✅ Successfully accessed App Group")
        fflush(stdout)
        
        // Read required data from App Group
        let baselineTimeSpent = userDefaults.double(forKey: "baselineTimeSpent")
        let baselineMinutes = baselineTimeSpent / 60.0
        NSLog("MONITOR_EXT: 📊 Baseline: \(baselineTimeSpent)s = \(baselineMinutes) min")
        print("MONITOR_EXT: 📊 Baseline: \(baselineTimeSpent)s = \(baselineMinutes) min")
        fflush(stdout)
        
        // Diagnostic: List all keys in App Group
        let allKeys = userDefaults.dictionaryRepresentation().keys
        NSLog("MONITOR_EXT: 🔍 All App Group keys (\(allKeys.count) total): \(Array(allKeys).sorted())")
        print("MONITOR_EXT: 🔍 All App Group keys (\(allKeys.count) total): \(Array(allKeys).sorted())")
        fflush(stdout)
        
        guard let commitmentId = userDefaults.string(forKey: "commitmentId") else {
            NSLog("MONITOR_EXT: ⚠️ No commitmentId found in App Group")
            print("MONITOR_EXT: ⚠️ No commitmentId found in App Group")
            NSLog("MONITOR_EXT: 🔍 Checking for similar keys...")
            let relatedKeys = allKeys.filter { $0.lowercased().contains("commit") || $0.lowercased().contains("id") }
            NSLog("MONITOR_EXT: 📋 Related keys: \(Array(relatedKeys))")
            print("MONITOR_EXT: 📋 Related keys: \(Array(relatedKeys))")
            fflush(stdout)
            // Clear the processing flag since we're aborting
            userDefaults.removeObject(forKey: idempotencyKey)
            userDefaults.synchronize()
            return
        }
        
        NSLog("MONITOR_EXT: ✅ Found commitmentId: \(commitmentId)")
        print("MONITOR_EXT: ✅ Found commitmentId: \(commitmentId)")
        fflush(stdout)
        
        // Get week start date (commitment deadline) - stored as timestamp
        let deadlineTimestamp = userDefaults.double(forKey: "commitmentDeadline")
        guard deadlineTimestamp > 0 else {
            NSLog("MONITOR_EXT: ⚠️ No commitmentDeadline found in App Group (timestamp: \(deadlineTimestamp))")
            print("MONITOR_EXT: ⚠️ No commitmentDeadline found in App Group (timestamp: \(deadlineTimestamp))")
            NSLog("MONITOR_EXT: 🔍 Checking all keys in App Group...")
            let allKeys = userDefaults.dictionaryRepresentation().keys
            NSLog("MONITOR_EXT: 📋 Sample keys: \(Array(allKeys.prefix(10)))")
            print("MONITOR_EXT: 📋 Sample keys: \(Array(allKeys.prefix(10)))")
            fflush(stdout)
            // Clear the processing flag since we're aborting
            userDefaults.removeObject(forKey: idempotencyKey)
            userDefaults.synchronize()
            return
        }
        
        // Convert timestamp to Date, then to YYYY-MM-DD string
        let deadlineDate = Date(timeIntervalSince1970: deadlineTimestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let deadlineString = dateFormatter.string(from: deadlineDate)
        
        NSLog("MONITOR_EXT: ✅ Found commitmentDeadline: \(deadlineString) (timestamp: \(deadlineTimestamp))")
        print("MONITOR_EXT: ✅ Found commitmentDeadline: \(deadlineString) (timestamp: \(deadlineTimestamp))")
        fflush(stdout)
        
        // Get current date (reuse same dateFormatter)
        let today = dateFormatter.string(from: Date())
        
        // Read last threshold value to calculate delta
        // IMPORTANT: Thresholds are CUMULATIVE (total consumed), so we need to calculate delta
        let lastThresholdKey = "last_threshold_seconds"
        let lastThresholdSeconds = userDefaults.integer(forKey: lastThresholdKey)
        
        // Special handling for first threshold after commitment creation
        // If this is the first threshold (lastThresholdSeconds == 0) and it's very large (> 10 minutes),
        // it likely represents pre-commitment usage. We should treat it as baseline and not count it.
        if lastThresholdSeconds == 0 && thresholdSeconds > 600 {
            NSLog("MONITOR_EXT: ⚠️ First threshold is very large (\(thresholdSeconds)s = \(thresholdSeconds/60) min) - likely pre-commitment usage")
            print("MONITOR_EXT: ⚠️ First threshold is very large (\(thresholdSeconds)s = \(thresholdSeconds/60) min) - likely pre-commitment usage")
            NSLog("MONITOR_EXT: 📝 Storing as baseline threshold, not counting as consumption")
            print("MONITOR_EXT: 📝 Storing as baseline threshold, not counting as consumption")
            fflush(stdout)
            // Store this threshold as the baseline, but don't count it as consumption
            userDefaults.set(thresholdSeconds, forKey: lastThresholdKey)
            userDefaults.synchronize()
            // Clear processing flag since we're done
            userDefaults.removeObject(forKey: idempotencyKey)
            userDefaults.synchronize()
            return
        }
        
        // Calculate delta: current threshold - last threshold = time consumed since last threshold
        let deltaSeconds = max(0, thresholdSeconds - lastThresholdSeconds)
        let deltaMinutes = Double(deltaSeconds) / 60.0
        
        NSLog("MONITOR_EXT: 📊 Delta calculation - lastThreshold: \(lastThresholdSeconds)s, currentThreshold: \(thresholdSeconds)s, delta: \(deltaSeconds)s = \(deltaMinutes) min")
        print("MONITOR_EXT: 📊 Delta calculation - lastThreshold: \(lastThresholdSeconds)s, currentThreshold: \(thresholdSeconds)s, delta: \(deltaSeconds)s = \(deltaMinutes) min")
        fflush(stdout)
        
        if deltaSeconds == 0 {
            NSLog("MONITOR_EXT: ⚠️ No delta, skipping update (last: \(lastThresholdSeconds)s, current: \(thresholdSeconds)s)")
            print("MONITOR_EXT: ⚠️ No delta, skipping update (last: \(lastThresholdSeconds)s, current: \(thresholdSeconds)s)")
            fflush(stdout)
            return
        }
        
        // Read existing entry or create new one
        let entryKey = "daily_usage_\(today)"
        var entry: ExtensionDailyUsageEntry
        
        if let existingData = userDefaults.data(forKey: entryKey),
           let decoded = try? JSONDecoder().decode(ExtensionDailyUsageEntry.self, from: existingData) {
            // Update existing entry
            let newTotalMinutes = decoded.totalMinutes + deltaMinutes
            entry = ExtensionDailyUsageEntry(
                date: today,
                totalMinutes: newTotalMinutes,
                baselineMinutes: baselineMinutes,
                lastUpdatedAt: Date().timeIntervalSince1970,
                synced: false,
                weekStartDate: deadlineString,
                commitmentId: commitmentId
            )
            NSLog("MONITOR_EXT: 📝 Updated daily usage entry for \(today): +\(deltaMinutes) min (total: \(newTotalMinutes) min)")
            print("MONITOR_EXT: 📝 Updated daily usage entry for \(today): +\(deltaMinutes) min (total: \(newTotalMinutes) min)")
            fflush(stdout)
        } else {
            // Create new entry
            entry = ExtensionDailyUsageEntry(
                date: today,
                totalMinutes: deltaMinutes,
                baselineMinutes: baselineMinutes,
                lastUpdatedAt: Date().timeIntervalSince1970,
                synced: false,
                weekStartDate: deadlineString,
                commitmentId: commitmentId
            )
            NSLog("MONITOR_EXT: ✨ Created new daily usage entry for \(today): \(deltaMinutes) min")
            print("MONITOR_EXT: ✨ Created new daily usage entry for \(today): \(deltaMinutes) min")
            fflush(stdout)
        }
        
        // Store entry
        NSLog("MONITOR_EXT: 💾 Attempting to encode and store entry...")
        print("MONITOR_EXT: 💾 Attempting to encode and store entry...")
        fflush(stdout)
        do {
            let encoded = try JSONEncoder().encode(entry)
            userDefaults.set(encoded, forKey: entryKey)
            // Store current threshold value for next delta calculation
            userDefaults.set(thresholdSeconds, forKey: lastThresholdKey)
            // Processing flag already set at the start, just ensure it's persisted
            userDefaults.synchronize()
            NSLog("MONITOR_EXT: ✅ Stored daily usage entry: date=\(today), total=\(entry.totalMinutes) min, used=\(entry.usedMinutes) min, synced=NO")
            print("MONITOR_EXT: ✅ Stored daily usage entry: date=\(today), total=\(entry.totalMinutes) min, used=\(entry.usedMinutes) min, synced=NO")
            fflush(stdout)
        } catch {
            NSLog("MONITOR_EXT: ❌ Failed to encode daily usage entry: \(error.localizedDescription)")
            print("MONITOR_EXT: ❌ Failed to encode daily usage entry: \(error.localizedDescription)")
            NSLog("MONITOR_EXT: 🔍 Entry details: date=\(entry.date), totalMinutes=\(entry.totalMinutes), baselineMinutes=\(entry.baselineMinutes)")
            print("MONITOR_EXT: 🔍 Entry details: date=\(entry.date), totalMinutes=\(entry.totalMinutes), baselineMinutes=\(entry.baselineMinutes)")
            fflush(stdout)
        }
    }
}
