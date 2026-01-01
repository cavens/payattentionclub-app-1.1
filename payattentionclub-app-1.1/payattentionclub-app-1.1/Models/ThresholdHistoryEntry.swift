import Foundation

/// Represents a single threshold event with timestamp and consumed minutes
/// Stored in App Group to track usage history
struct ThresholdHistoryEntry: Codable {
    /// Timestamp when threshold was reached (TimeInterval since 1970)
    let timestamp: TimeInterval
    
    /// Consumed minutes at this threshold
    let consumedMinutes: Double
    
    /// Seconds value from the threshold event
    let seconds: Int
    
    /// Create a new threshold history entry
    init(timestamp: TimeInterval, consumedMinutes: Double, seconds: Int) {
        self.timestamp = timestamp
        self.consumedMinutes = consumedMinutes
        self.seconds = seconds
    }
}


