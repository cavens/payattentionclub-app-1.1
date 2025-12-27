import Foundation
import os.log

/// Centralized logging for sync operations
/// Uses os_log for better visibility in Mac Console app
struct SyncLogger {
    // Use actual bundle ID from Bundle.main for accurate Mac Console filtering
    private static let subsystem: String = {
        if let bundleId = Bundle.main.bundleIdentifier {
            return bundleId
        }
        // Fallback to expected bundle ID
        return "com.payattentionclub.payattentionclub-app-1-1"
    }()
    static let sync = OSLog(subsystem: subsystem, category: "sync")
    
    // Also create a default log for general use
    static let `default` = OSLog(subsystem: subsystem, category: "default")
    
    /// Log a sync message (visible in Mac Console)
    /// Uses public string interpolation for better visibility
    static func log(_ message: String, type: OSLogType = .info) {
        // Use os_log with public string for Mac Console visibility
        // Use .info level by default for better visibility in Console app
        os_log("%{public}@", log: sync, type: type, message)
        
        // Also use NSLog for Xcode console compatibility
        NSLog("%@", message)
        
        // Also print for immediate visibility
        print(message)
        fflush(stdout)
    }
    
    /// Log info message
    static func info(_ message: String) {
        // Use .default instead of .info for better Mac Console visibility
        // .info logs are often filtered out in Console app
        log(message, type: .default)
    }
    
    /// Log error message
    static func error(_ message: String) {
        log(message, type: .error)
    }
    
    /// Log debug message
    static func debug(_ message: String) {
        log(message, type: .debug)
    }
    
    /// Log with custom format (for better Mac Console visibility)
    static func logFormatted(_ message: String, type: OSLogType = .default) {
        let formatted = "[SYNC] \(message)"
        os_log("%{public}@", log: sync, type: type, formatted)
        NSLog("%@", formatted)
        print(formatted)
        fflush(stdout)
    }
}

