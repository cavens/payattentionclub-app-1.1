import Foundation
import UserNotifications
import UIKit
import os.log

/// Delegate to handle notification presentation when app is in foreground
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private let logger = Logger(subsystem: "com.payattentionclub2.0.app", category: "NotificationDelegate")
    
    private override init() {
        super.init()
        logger.info("🚀 NotificationDelegate initialized")
        NSLog("NOTIFICATION NotificationDelegate: 🚀 Initialized")
    }
    
    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        let title = notification.request.content.title
        let appState = UIApplication.shared.applicationState
        
        logger.info("📢 Notification will present: \(identifier) - Title: \(title)")
        NSLog("NOTIFICATION NotificationDelegate: 📢 willPresent called for: \(identifier) - Title: \(title)")
        NSLog("NOTIFICATION NotificationDelegate: 📱 App state in willPresent: \(appState.rawValue) (0=active, 1=inactive, 2=background)")
        NSLog("NOTIFICATION NotificationDelegate: ⏰ Notification date: \(notification.date)")
        NSLog("NOTIFICATION NotificationDelegate: 🔔 Notification trigger: \(String(describing: notification.request.trigger))")
        
        // Show notification as banner and play sound when app is in foreground
        let options: UNNotificationPresentationOptions
        if #available(iOS 14.0, *) {
            options = [.banner, .sound, .badge]
        } else {
            options = [.alert, .sound, .badge]
        }
        
        NSLog("NOTIFICATION NotificationDelegate: ✅ Calling completionHandler with options: \(options)")
        completionHandler(options)
        NSLog("NOTIFICATION NotificationDelegate: ✅ completionHandler called")
    }
    
    // Handle notification tap/interaction
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        logger.info("📢 Notification tapped: \(response.notification.request.identifier)")
        NSLog("NOTIFICATION NotificationDelegate: 📢 Notification tapped: \(response.notification.request.identifier)")
        completionHandler()
    }
}
