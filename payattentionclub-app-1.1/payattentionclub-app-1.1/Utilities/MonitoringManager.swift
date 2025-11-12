import Foundation
import DeviceActivity
import FamilyControls
import os.log

/// Manages DeviceActivityCenter to schedule monitoring
/// Creates threshold events that trigger DeviceActivityMonitorExtension callbacks
@available(iOS 16.0, *)
@MainActor
class MonitoringManager {
    static let shared = MonitoringManager()
    private let logger = Logger(subsystem: "com.payattentionclub.app", category: "MonitoringManager")
    
    private let center = DeviceActivityCenter()
    private let activityName = DeviceActivityName("PayAttentionClub.Monitoring")
    
    private init() {}
    
    /// Start monitoring with the selected apps and create threshold events
    /// Events will fire at 1min, 5min, 10min, 15min, 30min, 60min intervals
    func startMonitoring(selection: FamilyActivitySelection) {
        NSLog("MARKERS MonitoringManager: 🔵🔵🔵 Starting monitoring...")
        print("MARKERS MonitoringManager: 🔵🔵🔵 Starting monitoring...")
        logger.info("MARKERS MonitoringManager: 🔵🔵🔵 Starting monitoring...")
        NSLog("MARKERS MonitoringManager: Selected apps count: %d", selection.applicationTokens.count)
        print("MARKERS MonitoringManager: Selected apps count: \(selection.applicationTokens.count)")
        fflush(stdout)
        
        // Store selection in App Group for Monitor Extension
        storeSelectionInAppGroups(selection: selection)
        
        // Create a schedule that runs all day (00:00 to 23:59)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        // Create threshold events at various intervals
        // These will trigger eventDidReachThreshold in Monitor Extension
        // NOTE: 1min threshold for faster testing - remove in production if desired
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            DeviceActivityEvent.Name("1min"): DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: 1)
            ),
            DeviceActivityEvent.Name("5min"): DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: 5)
            ),
            DeviceActivityEvent.Name("10min"): DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: 10)
            ),
            DeviceActivityEvent.Name("15min"): DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: 15)
            ),
            DeviceActivityEvent.Name("30min"): DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: 30)
            ),
            DeviceActivityEvent.Name("60min"): DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(hour: 1)
            )
        ]
        
        do {
            NSLog("MARKERS MonitoringManager: Attempting to start monitoring...")
            print("MARKERS MonitoringManager: Attempting to start monitoring...")
            try center.startMonitoring(activityName, during: schedule, events: events)
            NSLog("MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring with %d events", events.count)
            print("MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring with \(events.count) events")
            logger.info("MARKERS MonitoringManager: ✅✅✅ SUCCESS - Started monitoring")
            fflush(stdout)
        } catch {
            NSLog("MARKERS MonitoringManager: ❌❌❌ FAILED to start monitoring: %@", error.localizedDescription)
            print("MARKERS MonitoringManager: ❌❌❌ FAILED to start monitoring: \(error.localizedDescription)")
            logger.error("MARKERS MonitoringManager: ❌❌❌ FAILED to start monitoring: \(error.localizedDescription)")
            fflush(stdout)
        }
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

