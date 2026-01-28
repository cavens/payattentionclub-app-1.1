import Foundation
import UserNotifications
import UIKit
import os.log

/// Manages local notifications for limit exceedances and approaching limits
@MainActor
class NotificationManager {
    static let shared = NotificationManager()
    private let logger = Logger(subsystem: "com.payattentionclub2.0.app", category: "NotificationManager")
    
    // Notification identifiers
    private enum NotificationID {
        static let approachingLimit = "approaching_limit"
        static let limitReached = "limit_reached"
        static let firstPenalty = "first_penalty"
        static let penaltyMilestone = "penalty_milestone_"
    }
    
    // Track notification states to avoid duplicates
    private var hasNotifiedApproachingLimit = false
    private var hasNotifiedLimitReached = false
    private var hasNotifiedFirstPenalty = false // Track if we've notified for first $0.50 penalty
    private var lastPenaltyMilestoneNotified: Int = 0 // Track last $10 milestone notified
    
    // Notification title options (5 per type)
    private let approachingLimitTitles = [
        "One more cat video will do...",
        "Just one more scroll...",
        "One more episode couldn't hurt...",
        "Just one more, promise?",
        "One more level to beat..."
    ]
    
    private let limitReachedTitles = [
        "Oops, you did it...",
        "Well, that happened...",
        "You went and did it...",
        "There it is...",
        "And there we go..."
    ]
    
    private let firstPenaltyTitles = [
        "Thanks for the $0.50!",
        "Your $0.50 is noted...",
        "First contribution received!",
        "Thanks for playing along!",
        "Your generosity is noted..."
    ]
    
    private let penaltyMilestoneTitles = [
        "Another $10, thanks!",
        "$10 milestone unlocked!",
        "Thanks for the extra $10!",
        "You're really helping out!",
        "Another $10 contribution!"
    ]
    
    private init() {}
    
    // MARK: - Permission Request
    
    /// Request notification permissions from the user
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                logger.info("✅ Notification permission granted")
            } else {
                logger.info("❌ Notification permission denied")
            }
            return granted
        } catch {
            logger.error("❌ Error requesting notification permission: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check if notification permissions are granted
    func checkPermissionStatus() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let isAuthorized = settings.authorizationStatus == .authorized
        
        switch settings.authorizationStatus {
        case .authorized:
            logger.info("✅ Notification permission: authorized")
        case .denied:
            logger.warning("⚠️ Notification permission: denied")
        case .notDetermined:
            logger.warning("⚠️ Notification permission: not determined")
        case .provisional:
            logger.info("ℹ️ Notification permission: provisional")
        case .ephemeral:
            logger.info("ℹ️ Notification permission: ephemeral")
        @unknown default:
            logger.warning("⚠️ Notification permission: unknown status")
        }
        
        return isAuthorized
    }
    
    // MARK: - Notification Checking
    
    /// Check usage and send notifications if thresholds are met
    /// Should be called whenever usage is updated
    func checkAndNotifyIfNeeded(
        currentUsageSeconds: Int,
        baselineUsageSeconds: Int,
        limitMinutes: Double,
        penaltyPerMinute: Double
    ) async {
        logger.info("🔔 checkAndNotifyIfNeeded called - usage: \(currentUsageSeconds)s, baseline: \(baselineUsageSeconds)s, limit: \(limitMinutes)min")
        
        // Check permission first
        let hasPermission = await checkPermissionStatus()
        guard hasPermission else {
            logger.warning("⚠️ Notification permission not granted - skipping notification check")
            return
        }
        
        // Calculate usage in minutes
        let usageMinutes = Double(currentUsageSeconds - baselineUsageSeconds) / 60.0
        let limitMinutesValue = limitMinutes
        
        // Calculate penalty
        let excessMinutes = max(0, usageMinutes - limitMinutesValue)
        let currentPenalty = excessMinutes * penaltyPerMinute
        
        logger.info("📊 Usage check - usageMinutes: \(usageMinutes), limit: \(limitMinutesValue), penalty: $\(String(format: "%.2f", currentPenalty))")
        NSLog("NOTIFICATION NotificationManager: 🔍 DIAGNOSTIC - INPUT VALUES - currentUsageSeconds: \(currentUsageSeconds)s, baselineUsageSeconds: \(baselineUsageSeconds)s, limitMinutes: \(limitMinutesValue)min")
        NSLog("NOTIFICATION NotificationManager: 🔍 DIAGNOSTIC - CALCULATED - usageMinutes: \(usageMinutes) (from \(currentUsageSeconds)s - \(baselineUsageSeconds)s), limit: \(limitMinutesValue)min, penalty: $\(String(format: "%.2f", currentPenalty))")
        NSLog("NOTIFICATION NotificationManager: 🔍 DIAGNOSTIC - Notification flags - approaching: \(hasNotifiedApproachingLimit), limitReached: \(hasNotifiedLimitReached), firstPenalty: \(hasNotifiedFirstPenalty), lastMilestone: \(lastPenaltyMilestoneNotified)")
        
        // Check for approaching limit (80-90% of limit)
        let approachingThreshold = limitMinutesValue * 0.8
        let limitReachedThreshold = limitMinutesValue
        
        NSLog("NOTIFICATION NotificationManager: 🔍 DIAGNOSTIC - Thresholds - approaching: \(approachingThreshold)min, limitReached: \(limitReachedThreshold)min")
        
        if usageMinutes >= approachingThreshold && !hasNotifiedApproachingLimit {
            let minutesRemaining = max(0, limitMinutesValue - usageMinutes)
            logger.info("🚨 Approaching limit threshold reached: \(usageMinutes) >= \(approachingThreshold), remaining: \(minutesRemaining) min")
            NSLog("NOTIFICATION NotificationManager: 🚨 SENDING approaching limit notification - usage: \(usageMinutes)min >= threshold: \(approachingThreshold)min")
            await sendApproachingLimitNotification(minutesRemaining: Int(minutesRemaining))
            hasNotifiedApproachingLimit = true
        } else if usageMinutes >= approachingThreshold {
            logger.debug("⏭️ Approaching limit already notified")
            NSLog("NOTIFICATION NotificationManager: ⏭️ Approaching limit already notified (flag: \(hasNotifiedApproachingLimit))")
        } else {
            NSLog("NOTIFICATION NotificationManager: ⏭️ Approaching limit not reached yet - usage: \(usageMinutes)min < threshold: \(approachingThreshold)min")
        }
        
        // Check for limit reached
        if usageMinutes >= limitReachedThreshold && !hasNotifiedLimitReached {
            logger.info("🚨 Limit reached threshold: \(usageMinutes) >= \(limitReachedThreshold)")
            NSLog("NOTIFICATION NotificationManager: 🚨 SENDING limit reached notification - usage: \(usageMinutes)min >= threshold: \(limitReachedThreshold)min")
            await sendLimitReachedNotification()
            hasNotifiedLimitReached = true
        } else if usageMinutes >= limitReachedThreshold {
            logger.debug("⏭️ Limit reached already notified")
            NSLog("NOTIFICATION NotificationManager: ⏭️ Limit reached already notified (flag: \(hasNotifiedLimitReached))")
        } else {
            NSLog("NOTIFICATION NotificationManager: ⏭️ Limit not reached yet - usage: \(usageMinutes)min < threshold: \(limitReachedThreshold)min")
        }
        
        // Check for first penalty ($0.50 threshold) - useful for testing and early warning
        if currentPenalty >= 0.50 && !hasNotifiedFirstPenalty {
            logger.info("🚨 First penalty threshold reached: $\(String(format: "%.2f", currentPenalty))")
            NSLog("NOTIFICATION NotificationManager: 🚨 SENDING first penalty notification - penalty: $\(String(format: "%.2f", currentPenalty))")
            await sendFirstPenaltyNotification(
                exceededBy: excessMinutes,
                currentPenalty: currentPenalty
            )
            hasNotifiedFirstPenalty = true
        } else if currentPenalty >= 0.50 {
            logger.debug("⏭️ First penalty already notified")
            NSLog("NOTIFICATION NotificationManager: ⏭️ First penalty already notified (flag: \(hasNotifiedFirstPenalty), penalty: $\(String(format: "%.2f", currentPenalty)))")
        } else {
            NSLog("NOTIFICATION NotificationManager: ⏭️ First penalty not reached yet - penalty: $\(String(format: "%.2f", currentPenalty)) < $0.50")
        }
        
        // Check for penalty milestones ($10 increments)
        if currentPenalty > 0 {
            let milestone = Int(currentPenalty / 10.0) // Which $10 milestone (1, 2, 3, etc.)
            if milestone > lastPenaltyMilestoneNotified {
                logger.info("🚨 Penalty milestone reached: milestone \(milestone), penalty: $\(String(format: "%.2f", currentPenalty))")
                await sendPenaltyMilestoneNotification(
                    exceededBy: excessMinutes,
                    currentPenalty: currentPenalty
                )
                lastPenaltyMilestoneNotified = milestone
            }
        }
    }
    
    // MARK: - Notification Sending
    
    private func sendApproachingLimitNotification(minutesRemaining: Int) async {
        let content = UNMutableNotificationContent()
        // Randomly select one of 5 title options
        content.title = approachingLimitTitles.randomElement() ?? approachingLimitTitles[0]
        content.body = "" // Titles only
        content.sound = .default
        
        // Use unique identifier with timestamp to prevent conflicts
        let uniqueId = "\(NotificationID.approachingLimit)_\(Date().timeIntervalSince1970)"
        
        // Use very short delay (0.2 seconds) - nil trigger doesn't work reliably in foreground
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: uniqueId,
            content: content,
            trigger: trigger
        )
        
        do {
            // Check app state before adding
            let appState = UIApplication.shared.applicationState
            NSLog("NOTIFICATION NotificationManager: 📱 App state when adding notification: \(appState.rawValue) (0=active, 1=inactive, 2=background)")
            
            // Check notification settings
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            NSLog("NOTIFICATION NotificationManager: ⚙️ Notification settings - authorization: \(settings.authorizationStatus.rawValue), alert: \(settings.alertSetting.rawValue), sound: \(settings.soundSetting.rawValue)")
            
            // Verify delegate is set
            if center.delegate === NotificationDelegate.shared {
                NSLog("NOTIFICATION NotificationManager: ✅ Delegate is correctly set")
            } else {
                NSLog("NOTIFICATION NotificationManager: ❌ ERROR - Delegate is NOT set correctly!")
            }
            
            try await center.add(request)
            logger.info("📢 Sent approaching limit notification: \(minutesRemaining) min remaining (ID: \(uniqueId))")
            NSLog("NOTIFICATION NotificationManager: 📢 Added approaching limit notification: \(uniqueId)")
            
            // Verify it was added by checking pending notifications
            let pending = await center.pendingNotificationRequests()
            let found = pending.contains(where: { $0.identifier == uniqueId })
            NSLog("NOTIFICATION NotificationManager: 🔍 Verification - notification in pending list: \(found), total pending: \(pending.count)")
            
            // Check delivered notifications (if any)
            let delivered = await center.deliveredNotifications()
            NSLog("NOTIFICATION NotificationManager: 📬 Delivered notifications count: \(delivered.count)")
            
        } catch {
            logger.error("❌ Failed to send approaching limit notification: \(error.localizedDescription)")
            NSLog("NOTIFICATION NotificationManager: ❌ Error: \(error.localizedDescription)")
        }
    }
    
    private func sendLimitReachedNotification() async {
        let content = UNMutableNotificationContent()
        // Randomly select one of 5 title options
        content.title = limitReachedTitles.randomElement() ?? limitReachedTitles[0]
        content.body = "" // Titles only
        content.sound = .default
        
        // Use unique identifier with timestamp to prevent conflicts
        let uniqueId = "\(NotificationID.limitReached)_\(Date().timeIntervalSince1970)"
        
        // Use very short delay (0.2 seconds) - nil trigger doesn't work reliably in foreground
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: uniqueId,
            content: content,
            trigger: trigger
        )
        
        do {
            // Check app state before adding
            let appState = UIApplication.shared.applicationState
            NSLog("NOTIFICATION NotificationManager: 📱 App state when adding notification: \(appState.rawValue) (0=active, 1=inactive, 2=background)")
            
            let center = UNUserNotificationCenter.current()
            try await center.add(request)
            logger.info("📢 Sent limit reached notification (ID: \(uniqueId))")
            NSLog("NOTIFICATION NotificationManager: 📢 Added limit reached notification: \(uniqueId)")
            
            // Verify it was added
            let pending = await center.pendingNotificationRequests()
            let found = pending.contains(where: { $0.identifier == uniqueId })
            NSLog("NOTIFICATION NotificationManager: 🔍 Verification - notification in pending list: \(found), total pending: \(pending.count)")
            
        } catch {
            logger.error("❌ Failed to send limit reached notification: \(error.localizedDescription)")
            NSLog("NOTIFICATION NotificationManager: ❌ Error: \(error.localizedDescription)")
        }
    }
    
    private func sendFirstPenaltyNotification(exceededBy: Double, currentPenalty: Double) async {
        let content = UNMutableNotificationContent()
        // Randomly select one of 5 title options and replace $0.50 with actual penalty amount
        let baseTitle = firstPenaltyTitles.randomElement() ?? firstPenaltyTitles[0]
        // Replace "$0.50" with actual penalty amount dynamically
        let penaltyString = String(format: "$%.2f", currentPenalty)
        content.title = baseTitle.replacingOccurrences(of: "$0.50", with: penaltyString)
        content.body = "" // Titles only
        content.sound = .default
        
        // Use unique identifier with timestamp to prevent conflicts
        let uniqueId = "\(NotificationID.firstPenalty)_\(Date().timeIntervalSince1970)"
        
        // Use very short delay (0.2 seconds) - nil trigger doesn't work reliably in foreground
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: uniqueId,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📢 Sent first penalty notification: $\(String(format: "%.2f", currentPenalty)) (ID: \(uniqueId))")
            NSLog("NOTIFICATION NotificationManager: 📢 Added first penalty notification: \(uniqueId)")
        } catch {
            logger.error("❌ Failed to send first penalty notification: \(error.localizedDescription)")
            NSLog("NOTIFICATION NotificationManager: ❌ Error: \(error.localizedDescription)")
        }
    }
    
    private func sendPenaltyMilestoneNotification(exceededBy: Double, currentPenalty: Double) async {
        let content = UNMutableNotificationContent()
        // Randomly select one of 5 title options and replace $10 with actual milestone amount
        let milestoneAmount = Int(currentPenalty / 10.0) * 10
        let baseTitle = penaltyMilestoneTitles.randomElement() ?? penaltyMilestoneTitles[0]
        // Replace "$10" with actual milestone amount dynamically
        content.title = baseTitle.replacingOccurrences(of: "$10", with: "$\(milestoneAmount)")
        content.body = "" // Titles only
        content.sound = .default
        
        // Use unique identifier with timestamp to prevent conflicts
        let milestone = Int(currentPenalty / 10.0)
        let uniqueId = "\(NotificationID.penaltyMilestone)\(milestone)_\(Date().timeIntervalSince1970)"
        
        // Use very short delay (0.2 seconds) - nil trigger doesn't work reliably in foreground
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(
            identifier: uniqueId,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📢 Sent penalty milestone notification: $\(String(format: "%.2f", currentPenalty)) (ID: \(uniqueId))")
            NSLog("NOTIFICATION NotificationManager: 📢 Added penalty milestone notification: \(uniqueId)")
        } catch {
            logger.error("❌ Failed to send penalty milestone notification: \(error.localizedDescription)")
            NSLog("NOTIFICATION NotificationManager: ❌ Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Reset State
    
    /// Reset notification state (call when starting a new commitment)
    func resetNotificationState() {
        hasNotifiedApproachingLimit = false
        hasNotifiedLimitReached = false
        hasNotifiedFirstPenalty = false
        lastPenaltyMilestoneNotified = 0
        logger.info("🔄 Reset notification state for new commitment")
    }
    
    /// Cancel all pending notifications
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        logger.info("🗑️ Cancelled all pending notifications")
    }
}

