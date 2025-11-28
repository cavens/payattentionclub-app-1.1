import DeviceActivity
import Foundation

/// DeviceActivityMonitorExtension receives callbacks when usage thresholds are reached
/// Writes usage data to App Group so main app can read it
@available(iOS 16.0, *)
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    
    // MARK: - Rate Limiting (Step 5)
    
    /// Track last report timestamp to prevent duplicate reports
    private var lastReportTimestamp: TimeInterval = 0
    
    /// Minimum interval between reports (5 minutes = 300 seconds)
    /// Prevents duplicate reports when multiple thresholds fire quickly
    private let minReportInterval: TimeInterval = 300
    
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
        
        // Reset rate limiting when interval starts (allow first report of new interval)
        lastReportTimestamp = 0
        
        // TEST: Try network access (Step 0 - Network Test)
        testNetworkAccess()
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
        
        // Report usage to backend (with rate limiting) - Step 6
        if shouldReportUsage() {
            NSLog("EXTENSION MonitorExtension: 📤 Reporting usage to backend...")
            fflush(stdout)
            
            // Quick network test: Try simple GET request first
            Task {
                await quickNetworkTest()
                await reportUsageToBackend(consumedMinutes: consumedMinutes)
            }
        } else {
            let timeUntilNextReport = minReportInterval - (Date().timeIntervalSince1970 - lastReportTimestamp)
            NSLog("EXTENSION MonitorExtension: ⏸️ Skipping report (rate limited, next report in %.0f seconds)", timeUntilNextReport)
            fflush(stdout)
        }
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
    
    // MARK: - Network Test (Step 0)
    
    /// Test if the extension can make network calls
    /// This is Step 0 of the network reporting implementation plan
    /// Logs results to system console (view via Console.app)
    private func testNetworkAccess() {
        NSLog("EXTENSION NetworkTest: 🧪 Starting network access test...")
        fflush(stdout)
        
        Task {
            // Test 1: Simple GET request to httpbin.org
            let testURL = URL(string: "https://httpbin.org/get")!
            var request = URLRequest(url: testURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            
            do {
                NSLog("EXTENSION NetworkTest: 📤 Attempting GET request to https://httpbin.org/get...")
                fflush(stdout)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    
                    if statusCode == 200 {
                        NSLog("EXTENSION NetworkTest: ✅ SUCCESS! Status: %d", statusCode)
                        NSLog("EXTENSION NetworkTest: ✅ Network access is WORKING - extension CAN make HTTP requests")
                        NSLog("EXTENSION NetworkTest: Response preview: %@", String(responseString.prefix(200)))
                        fflush(stdout)
                    } else {
                        NSLog("EXTENSION NetworkTest: ⚠️ Unexpected status code: %d", statusCode)
                        NSLog("EXTENSION NetworkTest: Response: %@", responseString)
                        fflush(stdout)
                    }
                } else {
                    NSLog("EXTENSION NetworkTest: ⚠️ Response is not HTTPURLResponse")
                    fflush(stdout)
                }
            } catch {
                NSLog("EXTENSION NetworkTest: ❌ FAILED - Network request error: %@", error.localizedDescription)
                NSLog("EXTENSION NetworkTest: ❌ Error details: %@", String(describing: error))
                NSLog("EXTENSION NetworkTest: ❌ This extension CANNOT make network calls (or network is unavailable)")
                fflush(stdout)
                
                // Check if it's a specific error type
                if let urlError = error as? URLError {
                    NSLog("EXTENSION NetworkTest: ❌ URLError code: %d, domain: %@", urlError.code.rawValue, urlError.localizedDescription)
                    fflush(stdout)
                }
            }
            
            // Test 2: Try POST request (simulating what we'd do for rpc_report_usage)
            NSLog("EXTENSION NetworkTest: 🧪 Testing POST request (simulating backend call)...")
            fflush(stdout)
            
            let postURL = URL(string: "https://httpbin.org/post")!
            var postRequest = URLRequest(url: postURL)
            postRequest.httpMethod = "POST"
            postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            postRequest.timeoutInterval = 10.0
            
            let testBody: [String: Any] = [
                "test": "network_access",
                "timestamp": Date().timeIntervalSince1970
            ]
            
            do {
                postRequest.httpBody = try JSONSerialization.data(withJSONObject: testBody)
                
                let (_, postResponse) = try await URLSession.shared.data(for: postRequest)
                
                if let httpResponse = postResponse as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        NSLog("EXTENSION NetworkTest: ✅ POST request SUCCESS! Status: %d", httpResponse.statusCode)
                        NSLog("EXTENSION NetworkTest: ✅ Extension CAN make POST requests with JSON body")
                        fflush(stdout)
                    } else {
                        NSLog("EXTENSION NetworkTest: ⚠️ POST request returned status: %d", httpResponse.statusCode)
                        fflush(stdout)
                    }
                }
            } catch {
                NSLog("EXTENSION NetworkTest: ❌ POST request FAILED: %@", error.localizedDescription)
                fflush(stdout)
            }
            
            NSLog("EXTENSION NetworkTest: 🏁 Network test complete. Check logs above for results.")
            fflush(stdout)
        }
    }
    
    // MARK: - Rate Limiting Helpers (Step 5)
    
    /// Check if we should report usage based on rate limiting
    /// Returns true if at least 5 minutes have passed since last report
    /// This prevents duplicate reports when multiple thresholds fire quickly
    private func shouldReportUsage() -> Bool {
        let now = Date().timeIntervalSince1970
        let timeSinceLastReport = now - lastReportTimestamp
        
        // Only report if at least 5 minutes have passed since last report
        return timeSinceLastReport >= minReportInterval
    }
    
    // MARK: - Network Diagnostics
    
    /// Quick network test to verify basic connectivity
    /// Tests if extension can still make simple HTTP requests
    private func quickNetworkTest() async {
        let testURL = URL(string: "https://httpbin.org/get")!
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        let startTime = Date().timeIntervalSince1970
        NSLog("EXTENSION NetworkTest: 🧪 Quick test - Starting GET request...")
        fflush(stdout)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince1970 - startTime
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    NSLog("EXTENSION NetworkTest: ✅ Quick test SUCCESS! Status: %d, Duration: %.3fs", httpResponse.statusCode, duration)
                    fflush(stdout)
                } else {
                    NSLog("EXTENSION NetworkTest: ⚠️ Quick test returned status: %d, Duration: %.3fs", httpResponse.statusCode, duration)
                    fflush(stdout)
                }
            }
        } catch {
            let duration = Date().timeIntervalSince1970 - startTime
            NSLog("EXTENSION NetworkTest: ❌ Quick test FAILED! Error: %@, Duration: %.3fs", error.localizedDescription, duration)
            if let urlError = error as? URLError {
                NSLog("EXTENSION NetworkTest: URLError code: %d", urlError.code.rawValue)
            }
            fflush(stdout)
        }
    }
    
    // MARK: - Backend Reporting (Step 6)
    
    /// Report usage to backend when thresholds are hit
    /// Called from eventDidReachThreshold() with rate limiting
    private func reportUsageToBackend(consumedMinutes: Double) async {
        // Get deadline from App Group
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let deadlineTimestamp = userDefaults.object(forKey: "commitmentDeadline") as? TimeInterval else {
            NSLog("EXTENSION MonitorExtension: ❌ No deadline found, skipping report")
            fflush(stdout)
            return
        }
        
        // Get baseline from App Group (stored when commitment is created)
        let baselineMinutes = userDefaults.double(forKey: "baselineTimeSpent") / 60.0
        
        // Calculate used minutes (consumed - baseline)
        // Note: Currently baseline is always 0, but this ensures consistency if baseline logic changes
        let usedMinutes = max(0, Int(consumedMinutes - baselineMinutes))
        
        let deadline = Date(timeIntervalSince1970: deadlineTimestamp)
        let today = Date()
        
        NSLog("EXTENSION MonitorExtension: 📊 Reporting - consumed: %.1f min, baseline: %.1f min, used: %d min", 
              consumedMinutes, baselineMinutes, usedMinutes)
        fflush(stdout)
        
        // Report to backend
        await ExtensionBackendClient.shared.reportUsage(
            date: today,
            weekStartDate: deadline,
            usedMinutes: usedMinutes
        )
        
        // Update last report timestamp
        lastReportTimestamp = Date().timeIntervalSince1970
        NSLog("EXTENSION MonitorExtension: ✅ Report timestamp updated")
        fflush(stdout)
    }
}
