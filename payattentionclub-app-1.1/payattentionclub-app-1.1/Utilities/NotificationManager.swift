import Foundation
import UserNotifications
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
        return settings.authorizationStatus == .authorized
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
        // Check permission first
        let hasPermission = await checkPermissionStatus()
        guard hasPermission else {
            // Silently skip if no permission - don't spam logs
            return
        }
        
        // Calculate usage in minutes
        let usageMinutes = Double(currentUsageSeconds - baselineUsageSeconds) / 60.0
        let limitMinutesValue = limitMinutes
        
        // Calculate penalty
        let excessMinutes = max(0, usageMinutes - limitMinutesValue)
        let currentPenalty = excessMinutes * penaltyPerMinute
        
        // Check for approaching limit (80-90% of limit)
        let approachingThreshold = limitMinutesValue * 0.8
        let limitReachedThreshold = limitMinutesValue
        
        if usageMinutes >= approachingThreshold && !hasNotifiedApproachingLimit {
            let minutesRemaining = max(0, limitMinutesValue - usageMinutes)
            await sendApproachingLimitNotification(minutesRemaining: Int(minutesRemaining))
            hasNotifiedApproachingLimit = true
        }
        
        // Check for limit reached
        if usageMinutes >= limitReachedThreshold && !hasNotifiedLimitReached {
            await sendLimitReachedNotification()
            hasNotifiedLimitReached = true
        }
        
        // Check for first penalty ($0.50 threshold) - useful for testing and early warning
        if currentPenalty >= 0.50 && !hasNotifiedFirstPenalty {
            await sendFirstPenaltyNotification(
                exceededBy: excessMinutes,
                currentPenalty: currentPenalty
            )
            hasNotifiedFirstPenalty = true
        }
        
        // Check for penalty milestones ($10 increments)
        if currentPenalty > 0 {
            let milestone = Int(currentPenalty / 10.0) // Which $10 milestone (1, 2, 3, etc.)
            if milestone > lastPenaltyMilestoneNotified {
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
        
        // Send immediately (trigger with 0 seconds delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationID.approachingLimit,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📢 Sent approaching limit notification: \(minutesRemaining) min remaining")
        } catch {
            logger.error("❌ Failed to send approaching limit notification: \(error.localizedDescription)")
        }
    }
    
    private func sendLimitReachedNotification() async {
        let content = UNMutableNotificationContent()
        // Randomly select one of 5 title options
        content.title = limitReachedTitles.randomElement() ?? limitReachedTitles[0]
        content.body = "" // Titles only
        content.sound = .default
        
        // Send immediately (trigger with 0.1 seconds delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationID.limitReached,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📢 Sent limit reached notification")
        } catch {
            logger.error("❌ Failed to send limit reached notification: \(error.localizedDescription)")
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
        
        // Send immediately (trigger with 0.1 seconds delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationID.firstPenalty,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📢 Sent first penalty notification: $\(String(format: "%.2f", currentPenalty))")
        } catch {
            logger.error("❌ Failed to send first penalty notification: \(error.localizedDescription)")
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
        
        // Send immediately (trigger with 0.1 seconds delay)
        let milestone = Int(currentPenalty / 10.0)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(NotificationID.penaltyMilestone)\(milestone)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📢 Sent penalty milestone notification: $\(String(format: "%.2f", currentPenalty))")
        } catch {
            logger.error("❌ Failed to send penalty milestone notification: \(error.localizedDescription)")
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

