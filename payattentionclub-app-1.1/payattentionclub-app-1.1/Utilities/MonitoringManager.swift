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
        
        return events
    }
    
    /// Prepare thresholds asynchronously (non-blocking)
    /// Call this early (e.g., after "Commit" button) to prepare thresholds in background
    func prepareThresholds(selection: FamilyActivitySelection, limitMinutes: Int) async {
        // Check if already preparing or already cached
        if isPreparingThresholds {
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
            // Update cached selection to current (in case tokens changed but count same)
            await MainActor.run {
                cachedSelection = selection
            }
            return
        }
        
        isPreparingThresholds = true
        
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
    }
    
    /// Check if thresholds are ready for the given selection
    func thresholdsAreReady(for selection: FamilyActivitySelection) -> Bool {
        guard let _ = cachedEvents,
              let cachedSel = cachedSelection else {
            return false
        }
        
        // Check if selection count matches (simple check - tokens themselves can't be compared directly)
        return cachedSel.applicationTokens.count == selection.applicationTokens.count &&
               cachedSel.categoryTokens.count == selection.categoryTokens.count
    }
    
    /// Start monitoring with the selected apps (uses cached thresholds if available)
    /// Uses smart threshold distribution: ~140-145 events for fast startMonitoring()
    func startMonitoring(selection: FamilyActivitySelection, limitMinutes: Int) async {
        // Store selection in App Group for Monitor Extension
        storeSelectionInAppGroups(selection: selection)
        
        // Get events (use cached if available, otherwise create now)
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent]
        if thresholdsAreReady(for: selection), let cached = cachedEvents {
            events = cached
        } else {
            await prepareThresholds(selection: selection, limitMinutes: limitMinutes)
            events = cachedEvents ?? [:]
        }
        
        // Create a schedule that runs all day (00:00 to 23:59)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
            #if DEBUG
            NSLog("MonitoringManager: Started monitoring with %d events", events.count)
            #endif
        } catch {
            #if DEBUG
            NSLog("MonitoringManager: Failed to start monitoring: %@", error.localizedDescription)
            #endif
        }
    }
    
    /// Debug monitoring function - starts monitoring in 1 minute, ends in 20 minutes
    func startDebugMonitoring() async {
        let center = DeviceActivityCenter()
        
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
            try center.startMonitoring(activityName, during: schedule)
            #if DEBUG
            NSLog("MonitoringManager: Started debug monitoring")
            #endif
        } catch {
            #if DEBUG
            NSLog("MonitoringManager: Failed debug monitoring: %@", error.localizedDescription)
            #endif
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
        center.stopMonitoring([activityName])
    }
    
    /// Store FamilyActivitySelection in App Groups for Monitor Extension to read
    private func storeSelectionInAppGroups(selection: FamilyActivitySelection) {
        let appGroupIdentifier = "group.com.payattentionclub.app"
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        
        // Store a flag that selection is set
        userDefaults.set(true, forKey: "monitoringSelectionSet")
        userDefaults.synchronize()
    }
}
