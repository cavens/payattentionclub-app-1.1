import XCTest
@testable import payattentionclub_app_1_1

/// Unit tests for penalty and authorization calculations
final class AppModelTests: XCTestCase {
    
    // MARK: - Penalty Calculation Tests
    
    func testPenaltyCalculation_UnderLimit_ReturnsZero() {
        // User used 60 minutes, limit is 120 minutes
        let penalty = PenaltyCalculator.calculatePenalty(
            usageMinutes: 60,
            limitMinutes: 120,
            penaltyPerMinute: 0.10
        )
        
        XCTAssertEqual(penalty, 0.0, "Penalty should be zero when under limit")
    }
    
    func testPenaltyCalculation_AtLimit_ReturnsZero() {
        // User used exactly 120 minutes, limit is 120 minutes
        let penalty = PenaltyCalculator.calculatePenalty(
            usageMinutes: 120,
            limitMinutes: 120,
            penaltyPerMinute: 0.10
        )
        
        XCTAssertEqual(penalty, 0.0, "Penalty should be zero when at limit")
    }
    
    func testPenaltyCalculation_OverLimit_CalculatesCorrectly() {
        // User used 150 minutes, limit is 120 minutes
        // Excess: 30 minutes * $0.10 = $3.00
        let penalty = PenaltyCalculator.calculatePenalty(
            usageMinutes: 150,
            limitMinutes: 120,
            penaltyPerMinute: 0.10
        )
        
        XCTAssertEqual(penalty, 3.0, accuracy: 0.001, "Penalty should be $3.00 for 30 minutes over")
    }
    
    func testPenaltyCalculation_DifferentRate() {
        // User used 140 minutes, limit is 120 minutes
        // Excess: 20 minutes * $0.25 = $5.00
        let penalty = PenaltyCalculator.calculatePenalty(
            usageMinutes: 140,
            limitMinutes: 120,
            penaltyPerMinute: 0.25
        )
        
        XCTAssertEqual(penalty, 5.0, accuracy: 0.001, "Penalty should be $5.00 for 20 minutes at $0.25/min")
    }
    
    func testPenaltyCalculation_LargeOverage() {
        // User used 1260 minutes (21 hours), limit is 60 minutes (1 hour)
        // Excess: 1200 minutes * $0.10 = $120.00
        let penalty = PenaltyCalculator.calculatePenalty(
            usageMinutes: 1260,
            limitMinutes: 60,
            penaltyPerMinute: 0.10
        )
        
        XCTAssertEqual(penalty, 120.0, accuracy: 0.001, "Penalty should be $120.00 for 1200 minutes over")
    }
    
    // MARK: - Penalty From Seconds Tests
    
    func testPenaltyFromSeconds_ConvertsCorrectly() {
        // Current: 10800 seconds (3 hours), Baseline: 3600 seconds (1 hour)
        // Usage: 2 hours = 120 minutes
        // Limit: 60 minutes, Excess: 60 minutes * $0.10 = $6.00
        let penalty = PenaltyCalculator.calculatePenaltyFromSeconds(
            currentUsageSeconds: 10800,
            baselineUsageSeconds: 3600,
            limitMinutes: 60,
            penaltyPerMinute: 0.10
        )
        
        XCTAssertEqual(penalty, 6.0, accuracy: 0.001, "Penalty should be $6.00")
    }
    
    func testPenaltyFromSeconds_WithZeroBaseline() {
        // Current: 7200 seconds (2 hours), Baseline: 0
        // Usage: 2 hours = 120 minutes
        // Limit: 60 minutes, Excess: 60 minutes * $0.10 = $6.00
        let penalty = PenaltyCalculator.calculatePenaltyFromSeconds(
            currentUsageSeconds: 7200,
            baselineUsageSeconds: 0,
            limitMinutes: 60,
            penaltyPerMinute: 0.10
        )
        
        XCTAssertEqual(penalty, 6.0, accuracy: 0.001, "Penalty should be $6.00")
    }
    
    // MARK: - Authorization Amount Tests
    
    func testAuthorizationAmount_MinimumFiveDollars() {
        // Even with minimal overage potential, minimum is $5.00
        let auth = PenaltyCalculator.calculateAuthorizationAmount(
            minutesRemaining: 100,
            limitMinutes: 90,
            penaltyPerMinute: 0.10,
            appCount: 0
        )
        
        XCTAssertGreaterThanOrEqual(auth, 5.0, "Authorization should be at least $5.00")
    }
    
    func testAuthorizationAmount_ZeroWhenNoTimeRemaining() {
        let auth = PenaltyCalculator.calculateAuthorizationAmount(
            minutesRemaining: 0,
            limitMinutes: 120,
            penaltyPerMinute: 0.10,
            appCount: 5
        )
        
        XCTAssertEqual(auth, 0.0, "Authorization should be $0 when no time remaining")
    }
    
    func testAuthorizationAmount_IncreasesWithAppCount() {
        let authNoApps = PenaltyCalculator.calculateAuthorizationAmount(
            minutesRemaining: 10000,
            limitMinutes: 1000,
            penaltyPerMinute: 0.10,
            appCount: 0
        )
        
        let authWithApps = PenaltyCalculator.calculateAuthorizationAmount(
            minutesRemaining: 10000,
            limitMinutes: 1000,
            penaltyPerMinute: 0.10,
            appCount: 10
        )
        
        XCTAssertGreaterThan(authWithApps, authNoApps, "Authorization should increase with more apps")
    }
    
    func testAuthorizationAmount_RiskFactorCalculation() {
        // 10 apps = risk factor of 2.0 (1.0 + 0.1 * 10)
        // Minutes remaining: 1000, Limit: 0
        // Potential overage: 1000 minutes * $0.10 * 100 = 10000 cents
        // With risk factor: 10000 * 2.0 = 20000 cents = $200.00
        let auth = PenaltyCalculator.calculateAuthorizationAmount(
            minutesRemaining: 1000,
            limitMinutes: 0,
            penaltyPerMinute: 0.10,
            appCount: 10
        )
        
        XCTAssertEqual(auth, 200.0, accuracy: 0.01, "Authorization should be $200.00 with 10 apps and 1000 min overage")
    }
    
    func testAuthorizationAmount_HigherPenaltyRate() {
        // Minutes remaining: 1000, Limit: 500
        // Potential overage: 500 minutes * $0.50 * 100 = 25000 cents
        // Risk factor 1.0 (0 apps): 25000 cents = $250.00
        let auth = PenaltyCalculator.calculateAuthorizationAmount(
            minutesRemaining: 1000,
            limitMinutes: 500,
            penaltyPerMinute: 0.50,
            appCount: 0
        )
        
        XCTAssertEqual(auth, 250.0, accuracy: 0.01, "Authorization should be $250.00 at $0.50/min rate")
    }
}

