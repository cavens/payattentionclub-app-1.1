import Foundation

/// Utility for penalty calculations - extracted for testability
/// These are pure functions that can be unit tested independently
enum PenaltyCalculator {
    
    // MARK: - Penalty Calculation
    
    /// Calculate penalty for excess usage
    /// - Parameters:
    ///   - usageMinutes: Total minutes used
    ///   - limitMinutes: Daily/weekly limit in minutes
    ///   - penaltyPerMinute: Penalty rate per minute (e.g., 0.10 for $0.10)
    /// - Returns: Total penalty in dollars
    static func calculatePenalty(
        usageMinutes: Double,
        limitMinutes: Double,
        penaltyPerMinute: Double
    ) -> Double {
        let excessMinutes = max(0, usageMinutes - limitMinutes)
        return excessMinutes * penaltyPerMinute
    }
    
    /// Calculate penalty from seconds (convenience method used by AppModel)
    /// - Parameters:
    ///   - currentUsageSeconds: Current usage in seconds
    ///   - baselineUsageSeconds: Baseline (locked in) usage in seconds
    ///   - limitMinutes: Limit in minutes
    ///   - penaltyPerMinute: Penalty rate per minute
    /// - Returns: Total penalty in dollars
    static func calculatePenaltyFromSeconds(
        currentUsageSeconds: Int,
        baselineUsageSeconds: Int,
        limitMinutes: Double,
        penaltyPerMinute: Double
    ) -> Double {
        let usageMinutes = Double(currentUsageSeconds - baselineUsageSeconds) / 60.0
        return calculatePenalty(
            usageMinutes: usageMinutes,
            limitMinutes: limitMinutes,
            penaltyPerMinute: penaltyPerMinute
        )
    }
    
    // MARK: - Authorization Calculation
    
    /// Calculate maximum authorization amount (mirrors rpc_create_commitment max_charge_cents)
    /// - Parameters:
    ///   - minutesRemaining: Minutes until deadline
    ///   - limitMinutes: User's time limit in minutes
    ///   - penaltyPerMinute: Penalty rate per minute (e.g., 0.10 for $0.10)
    ///   - appCount: Number of apps/categories selected for monitoring
    /// - Returns: Authorization amount in dollars (minimum $5.00 if time remaining, else $0)
    static func calculateAuthorizationAmount(
        minutesRemaining: Double,
        limitMinutes: Double,
        penaltyPerMinute: Double,
        appCount: Int
    ) -> Double {
        guard minutesRemaining > 0 else { return 0 }
        
        let riskFactor = 1.0 + 0.1 * Double(appCount)
        let potentialOverage = max(0, minutesRemaining - limitMinutes)
        let cents = potentialOverage * (penaltyPerMinute * 100.0) * riskFactor
        let roundedCents = max(500, floor(max(0, cents))) // Minimum $5.00
        
        return roundedCents / 100.0
    }
}



