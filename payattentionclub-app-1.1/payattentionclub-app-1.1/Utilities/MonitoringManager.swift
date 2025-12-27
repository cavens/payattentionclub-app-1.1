import Foundation
import DeviceActivity
import FamilyControls

/// Manages DeviceActivityCenter to schedule monitoring
/// Creates threshold events that trigger DeviceActivityMonitorExtension callbacks
@available(iOS 16.0, *)
@MainActor
class MonitoringManager {
    static let shared = MonitoringManager()
    
    private let center = DeviceActivityCenter()
    private let activityName = DeviceActivityName("PayAttentionClub.Monitoring")
    
    // Cache for prepared thresholds
    private var cachedEvents: [DeviceActivityEvent.Name: DeviceActivityEvent]?
    private var cachedSelection: FamilyActivitySelection?
    private var isPreparingThresholds = false
    
    private init() {}
    
    /// Build threshold events using smart distribution strategy
    /// - Early dense: 1-minute steps for first 10 minutes (1, 2, 3...10)
    /// - Regular: 5-minute steps from 5 to max(limit, 600) minutes
    /// - Final dense: 1-minute steps for last 15 minutes before limit (if limit >= 20)
    /// - Total: ~140-145 events for fast startMonitoring()
    func buildEvents(limitMinutes L: Int, selection: FamilyActivitySelection) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let Lcapped = max(5, min(L, 600)) // Cap to 10h (600 minutes) for now
        
        var minutes = Set<Int>()
        
        // Early dense 1-minute steps (1..10)
        for m in 1...10 {
            minutes.insert(m)
        }
        
        // 5-minute ladder up to max(L, 600)
        let maxMins = max(Lcapped, 600)
        for m in stride(from: 5, through: maxMins, by: 5) {
            minutes.insert(m)
        }
        
        // Final dense window before limit (if L >= 20)
        if Lcapped >= 20 {
            for m in max(1, Lcapped - 15)...Lcapped {
                minutes.insert(m)
            }
        }
        
        // Convert to seconds and sort
        let thresholdsSec = minutes.sorted().map { $0 * 60 }
        
        // Build events dictionary
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for secs in thresholdsSec {
            let name = DeviceActivityEvent.Name("t_\(secs)s")
            events[name] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(second: secs)
            )
        }
        
        NSLog("MARKERS MonitoringManager: 📊 Built %d threshold events (limit: %d min, max undercount: ≤5 min)", 
              events.count, Lcapped)
        fflush(stdout)
        
        return events
    }
    
    /// Prepare thresholds asynchronously (non-blocking)
    /// Call this early (e.g., after "Commit" button) to prepare thresholds in background
    func prepareThresholds(selection: FamilyActivitySelection, limitMinutes: Int) async {
        // Check if already preparing or already cached
        if isPreparingThresholds {
            NSLog("MARKERS MonitoringManager: ⏳ Thresholds already being prepared, waiting...")
            fflush(stdout)
            // Wait for existing preparation to complete
            while isPreparingThresholds {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            return
        }
        
        // Check if cached thresholds match current selection and limit
        if let _ = cachedEvents, 
           let cachedSel = cachedSelection,
           cachedSel.applicationTokens.count == selection.applicationTokens.count &&
           cachedSel.categoryTokens.count == selection.categoryTokens.count {
            NSLog("MARKERS MonitoringManager: ✅ Using cached thresholds (selection count matches: %d apps, %d categories)", 
                  selection.applicationTokens.count, selection.categoryTokens.count)
            fflush(stdout)
            // Update cached selection to current (in case tokens changed but count same)
            await MainActor.run {
                cachedSelection = selection
            }
            return
        }
        
        isPreparingThresholds = true
        NSLog("MARKERS MonitoringManager: 🚀 Starting async threshold preparation (limit: %d min)...", limitMinutes)
        fflush(stdout)
        
        // Create events in background (off main thread)
        let events = await Task.detached(priority: .userInitiated) { [selection, limitMinutes] in
            // Build events using smart distribution
            let Lcapped = max(5, min(limitMinutes, 600))
            var minutes = Set<Int>()
            
            // Early dense 1-minute steps (1..10)
            for m in 1...10 {
                minutes.insert(m)
            }
            
            // 5-minute ladder up to max(L, 600)
            let maxMins = max(Lcapped, 600)
            for m in stride(from: 5, through: maxMins, by: 5) {
                minutes.insert(m)
            }
            
            // Final dense window before limit (if L >= 20)
            if Lcapped >= 20 {
                for m in max(1, Lcapped - 15)...Lcapped {
                    minutes.insert(m)
                }
            }
            
            // Convert to seconds and sort
            let thresholdsSec = minutes.sorted().map { $0 * 60 }
            
            // Build events dictionary
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for secs in thresholdsSec {
                let name = DeviceActivityEvent.Name("t_\(secs)s")
                events[name] = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: DateComponents(second: secs)
                )
            }
            
            return events
        }.value
        
        // Store cached events and selection
        await MainActor.run {
            cachedEvents = events
            cachedSelection = selection
            isPreparingThresholds = false
        }
        
        NSLog("MARKERS MonitoringManager: ✅ Threshold preparation complete (%d events)", events.count)
        fflush(stdout)
    }
    
    /// Check if thresholds are ready for the given selection
    func thresholdsAreReady(for selection: FamilyActivitySelection) -> Bool {
        guard let _ = cachedEvents,
              let cachedSel = cachedSelection else {
            NSLog("MARKERS MonitoringManager: ❌ No cached thresholds available")
            fflush(stdout)
            return false
        }
        
        // Check if selection count matches (simple check - tokens themselves can't be compared directly)
        let matches = cachedSel.applicationTokens.count == selection.applicationTokens.count &&
                      cachedSel.categoryTokens.count == selection.categoryTokens.count
        
        if matches {
            NSLog("MARKERS MonitoringManager: ✅ Cached thresholds ready (count matches: %d apps, %d categories)", 
                  selection.applicationTokens.count, selection.categoryTokens.count)
        } else {
            NSLog("MARKERS MonitoringManager: ⚠️ Cached thresholds don't match (cached: %d/%d, current: %d/%d)", 
                  cachedSel.applicationTokens.count, cachedSel.categoryTokens.count,
                  selection.applicationTokens.count, selection.categoryTokens.count)
        }
        fflush(stdout)
        
        return matches
    }
    
    /// Start monitoring with the selected apps (uses cached thresholds if available)
    /// Uses smart threshold distribution: ~140-145 events for fast startMonitoring()
    func startMonitoring(selection: FamilyActivitySelection, limitMinutes: Int) async {
        NSLog("MARKERS MonitoringManager: 🔵🔵🔵 Starting monitoring...")
        NSLog("MARKERS MonitoringManager: Selected apps count: %d", selection.applicationTokens.count)
        fflush(stdout)
        
        // Store selection in App Group for Monitor Extension
        storeSelectionInAppGroups(selection: selection)
        
        // Get events (use cached if available, otherwise create now)
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent]
        if thresholdsAreReady(for: selection), let cached = cachedEvents {
            NSLog("MARKERS MonitoringManager: ⚡ Using cached thresholds - instant start!")
            fflush(stdout)
            events = cached
        } else {
            NSLog("MARKERS MonitoringManager: ⚠️ No cached thresholds, creating now...")
            fflush(stdout)
            await prepareThresholds(selection: selection, limitMinutes: limitMinutes)
            events = cachedEvents ?? [:]
        }
        
        // Create a schedule that runs all day (00:00 to 23:59)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        NSLog("MARKERS MonitoringManager: 📊 Starting monitoring with %d threshold events (limit: %d min)", 
              events.count, limitMinutes)
        fflush(stdout)
        
        // Log first, middle, and last event names for verification (off main thread to avoid blocking)
        Task.detached(priority: .utility) { [events] in
            let eventNames = Array(events.keys).sorted { event1, event2 in
                let sec1 = MonitoringManager.extractSecondsFromEventNameStatic(event1.rawValue)
                let sec2 = MonitoringManager.extractSecondsFromEventNameStatic(event2.rawValue)
                return sec1 < sec2
            }
            
            if eventNames.count > 0 {
                NSLog("MARKERS MonitoringManager: First event: %@", eventNames[0].rawValue)
                if eventNames.count > 1 {
                    let middleIndex = eventNames.count / 2
                    NSLog("MARKERS MonitoringManager: Middle event: %@", eventNames[middleIndex].rawValue)
                }
                NSLog("MARKERS MonitoringManager: Last event: %@", eventNames[eventNames.count - 1].rawValue)
                fflush(stdout)
            }
        }
        
        NSLog("MARKERS MonitoringManager: ⏱️ About to call center.startMonitoring()...")
        fflush(stdout)
        
        // Call startMonitoring on main thread (required by DeviceActivityCenter)
        // With ~140 events, this should be fast (~2-3 seconds instead of 31 seconds)
        do {
            NSLog("MARKERS MonitoringManager: Attempting to start monitoring...")
            NSLog("MARKERS MonitoringManager: Activity name: %@", activityName.rawValue)
            let startHour = schedule.intervalStart.hour ?? 0
            let startMin = schedule.intervalStart.minute ?? 0
            let endHour = schedule.intervalEnd.hour ?? 23
            let endMin = schedule.intervalEnd.minute ?? 59
            NSLog("MARKERS MonitoringManager: Schedule: %02d:%02d to %02d:%02d, repeats: %@", 
                  startHour, startMin, endHour, endMin, schedule.repeats ? "YES" : "NO")
            try center.startMonitoring(activityName, during: schedule, events: events)
            NSLog("MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring with %d events", events.count)
            NSLog("MARKERS MonitoringManager: ⚠️ NOTE: Extension will be invoked when interval starts or threshold is reached")
            NSLog("MARKERS MonitoringManager: ⚠️ Look for: EXTENSION DeviceActivityMonitorExtension logs in console")
            fflush(stdout)
        } catch {
            NSLog("MARKERS MonitoringManager: ❌❌❌ FAILED to start monitoring: %@", error.localizedDescription)
            NSLog("MARKERS MonitoringManager: Error details: %@", String(describing: error))
            fflush(stdout)
        }
    }
    
    /// Debug monitoring function - starts monitoring in 1 minute, ends in 20 minutes
    /// This is a minimal test to verify extension is being invoked
    func startDebugMonitoring() async {
        let center = DeviceActivityCenter()
        
        // Log the authorization status just to be sure
        let status = AuthorizationCenter.shared.authorizationStatus
        NSLog("MARKERS MonitoringManager: FamilyControls status = %d", status.rawValue)
        
        let now = Date()
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .minute, value: 1, to: now)!
        let endDate   = calendar.date(byAdding: .minute, value: 20, to: now)!
        
        let comps: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(comps, from: startDate),
            intervalEnd:   calendar.dateComponents(comps, from: endDate),
            repeats: false
        )
        
        let activityName = DeviceActivityName("PAC.DebugActivity")
        
        do {
            NSLog("MARKERS MonitoringManager: About to call startMonitoring...")
            try center.startMonitoring(activityName, during: schedule)
            NSLog("MARKERS MonitoringManager: ✅ started debug monitoring")
            print("MARKERS MonitoringManager: ✅ started debug monitoring")
            fflush(stdout)
        } catch {
            NSLog("MARKERS MonitoringManager: ❌ failed debug monitoring: %@", error.localizedDescription)
            print("MARKERS MonitoringManager: ❌ failed debug monitoring: \(error.localizedDescription)")
            fflush(stdout)
        }
    }
    
    /// Helper to extract seconds from event name for sorting
    private func extractSecondsFromEventName(_ eventName: String) -> Int {
        return MonitoringManager.extractSecondsFromEventNameStatic(eventName)
    }
    
    /// Static helper to extract seconds from event name (can be called from nonisolated context)
    /// Supports both old format ("30sec") and new format ("t_60s")
    nonisolated private static func extractSecondsFromEventNameStatic(_ eventName: String) -> Int {
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
    
    /// Stop monitoring
    func stopMonitoring() {
        NSLog("MARKERS MonitoringManager: 🛑 Stopping monitoring before reset")
        fflush(stdout)
        center.stopMonitoring([activityName])
        NSLog("MARKERS MonitoringManager: ✅ Monitoring stopped")
        fflush(stdout)
    }
    
    /// Store FamilyActivitySelection in App Groups for Monitor Extension to read
    private func storeSelectionInAppGroups(selection: FamilyActivitySelection) {
        let appGroupIdentifier = "group.com.payattentionclub2.0.app"
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        
        // Store a flag that selection is set
        userDefaults.set(true, forKey: "monitoringSelectionSet")
        userDefaults.synchronize()
    }
}
