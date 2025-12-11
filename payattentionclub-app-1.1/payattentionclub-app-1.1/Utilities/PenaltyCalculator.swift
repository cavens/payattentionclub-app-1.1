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
    
    /// DEPRECATED: Authorization amount is now calculated by the backend via rpc_preview_max_charge
    /// This local version is kept only for unit tests but will NOT match the backend formula.
    /// The backend formula uses realistic usage caps and bounds ($5-$100).
    /// 
    /// @available(*, deprecated, message: "Use BackendClient.previewMaxCharge() instead")
    static func calculateAuthorizationAmount(
        minutesRemaining: Double,
        limitMinutes: Double,
        penaltyPerMinute: Double,
        appCount: Int
    ) -> Double {
        // DEPRECATED: This formula is intentionally simple and does NOT match backend.
        // The real formula is in supabase/remote_rpcs/calculate_max_charge_cents.sql
        guard minutesRemaining > 0 else { return 0 }
        
        // Return a simplified estimate - real value comes from backend
        // Backend formula: realistic daily usage cap, bounded $5-$100
        let estimate = 5.0 + Double(appCount) * 2.0 + (penaltyPerMinute * 10.0)
        return min(100.0, max(5.0, estimate))
    }
}



