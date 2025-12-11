import Foundation

/// Utility for date calculations - extracted for testability
enum DateCalculator {
    
    // MARK: - Deadline Calculation
    
    /// Calculate next Monday noon EST from a given date
    /// - Parameter from: The reference date
    /// - Returns: The next Monday at 12:00 PM EST
    static func calculateNextMondayNoonEST(from date: Date = Date()) -> Date {
        var estCalendar = Calendar.current
        estCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        
        var components = estCalendar.dateComponents([.year, .month, .day, .weekday, .hour], from: date)
        
        if let weekday = components.weekday {
            let daysUntilMonday = (9 - weekday) % 7
            if daysUntilMonday == 0 && (components.hour ?? 0) < 12 {
                // Today is Monday and before noon, use today
                components.hour = 12
                components.minute = 0
                components.second = 0
            } else {
                // Find next Monday
                let daysToAdd = daysUntilMonday == 0 ? 7 : daysUntilMonday
                components.day = (components.day ?? 0) + daysToAdd
                components.hour = 12
                components.minute = 0
                components.second = 0
            }
        }
        
        return estCalendar.date(from: components) ?? date.addingTimeInterval(7 * 24 * 60 * 60)
    }
    
    // MARK: - Countdown Formatting
    
    /// Format time interval as DD:HH:MM:SS countdown string
    /// - Parameter timeInterval: Time interval in seconds
    /// - Returns: Formatted string like "02:14:30:45"
    static func formatCountdown(timeInterval: TimeInterval) -> String {
        guard timeInterval > 0 else {
            return "00:00:00:00"
        }
        
        let totalSeconds = Int(timeInterval)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
    }
    
    /// Calculate minutes remaining until a deadline
    /// - Parameters:
    ///   - from: The current date
    ///   - to: The deadline date
    /// - Returns: Minutes remaining (0 if deadline has passed)
    static func minutesRemaining(from: Date, to deadline: Date) -> Double {
        let interval = deadline.timeIntervalSince(from)
        return max(0, interval / 60.0)
    }
}



