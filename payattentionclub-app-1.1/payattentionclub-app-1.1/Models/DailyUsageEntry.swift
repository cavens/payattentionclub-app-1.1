import Foundation

/// Represents a daily usage entry stored in App Group
/// Written by DeviceActivityMonitorExtension, read by main app for syncing
struct DailyUsageEntry: Codable {
    /// Date in YYYY-MM-DD format (e.g., "2025-11-27")
    let date: String
    
    /// Total minutes consumed on this day (from Screen Time)
    let totalMinutes: Double
    
    /// Baseline minutes (from when commitment was created)
    let baselineMinutes: Double
    
    /// Used minutes (total - baseline, minimum 0)
    var usedMinutes: Int {
        max(0, Int(totalMinutes - baselineMinutes))
    }
    
    /// Timestamp when this entry was last updated
    let lastUpdatedAt: TimeInterval
    
    /// Whether this entry has been synced to the backend
    var synced: Bool
    
    /// Week start date (commitment deadline) in YYYY-MM-DD format
    let weekStartDate: String
    
    /// Commitment ID this usage belongs to
    let commitmentId: String
    
    /// Create a new daily usage entry
    init(
        date: String,
        totalMinutes: Double,
        baselineMinutes: Double,
        weekStartDate: String,
        commitmentId: String,
        synced: Bool = false
    ) {
        self.date = date
        self.totalMinutes = totalMinutes
        self.baselineMinutes = baselineMinutes
        self.lastUpdatedAt = Date().timeIntervalSince1970
        self.weekStartDate = weekStartDate
        self.commitmentId = commitmentId
        self.synced = synced
    }
    
    /// Internal initializer that allows setting lastUpdatedAt (for preserving timestamp when marking as synced)
    internal init(
        date: String,
        totalMinutes: Double,
        baselineMinutes: Double,
        lastUpdatedAt: TimeInterval,
        weekStartDate: String,
        commitmentId: String,
        synced: Bool
    ) {
        self.date = date
        self.totalMinutes = totalMinutes
        self.baselineMinutes = baselineMinutes
        self.lastUpdatedAt = lastUpdatedAt
        self.weekStartDate = weekStartDate
        self.commitmentId = commitmentId
        self.synced = synced
    }
    
    /// Update this entry with new total minutes
    func updating(totalMinutes: Double) -> DailyUsageEntry {
        return DailyUsageEntry(
            date: date,
            totalMinutes: totalMinutes,
            baselineMinutes: baselineMinutes,
            weekStartDate: weekStartDate,
            commitmentId: commitmentId,
            synced: synced
        )
    }
    
    /// Mark this entry as synced (preserves lastUpdatedAt timestamp)
    func markingAsSynced() -> DailyUsageEntry {
        // Create a new entry with synced=true but preserve the original lastUpdatedAt
        return DailyUsageEntry(
            date: date,
            totalMinutes: totalMinutes,
            baselineMinutes: baselineMinutes,
            lastUpdatedAt: lastUpdatedAt, // Preserve original timestamp
            weekStartDate: weekStartDate,
            commitmentId: commitmentId,
            synced: true
        )
    }
}

// MARK: - Date Formatting Helpers

extension DailyUsageEntry {
    /// Format a Date to YYYY-MM-DD string
    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    /// Parse a YYYY-MM-DD string to Date
    static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }
}

