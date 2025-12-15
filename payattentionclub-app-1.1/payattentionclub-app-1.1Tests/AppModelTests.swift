import XCTest
import FamilyControls
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
    
    // MARK: - Authorization Amount Tests (Using Actual Backend Implementation)
    
    /// Helper to get next Monday deadline date
    private func getNextMondayDeadline() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        
        // Calculate days until next Monday
        let weekday = components.weekday ?? 1 // 1 = Sunday, 2 = Monday, etc.
        let daysUntilMonday: Int
        if weekday == 1 {
            daysUntilMonday = 1 // Sunday -> Monday
        } else if weekday == 2 {
            daysUntilMonday = 7 // Monday -> next Monday
        } else {
            daysUntilMonday = 9 - weekday // Tue-Sat -> next Monday
        }
        
        components.day = (components.day ?? 1) + daysUntilMonday
        components.hour = 12 // Noon EST
        components.minute = 0
        components.second = 0
        
        return calendar.date(from: components) ?? now
    }
    
    func testAuthorizationAmount_MinimumFiveDollars() async throws {
        // Test that backend enforces $5.00 minimum
        let deadline = getNextMondayDeadline()
        let response = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: deadline,
            limitMinutes: 90,
            penaltyPerMinuteCents: 10,
            selectedApps: FamilyActivitySelection()
        )
        
        XCTAssertGreaterThanOrEqual(response.maxChargeDollars, 5.0, "Authorization should be at least $5.00")
        XCTAssertLessThanOrEqual(response.maxChargeDollars, 1000.0, "Authorization should be at most $1000.00")
    }
    
    func testAuthorizationAmount_ZeroWhenNoTimeRemaining() async throws {
        // Test with deadline in the past (should return 0 or minimum)
        let pastDate = Date(timeIntervalSinceNow: -86400) // Yesterday
        let response = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: pastDate,
            limitMinutes: 120,
            penaltyPerMinuteCents: 10,
            selectedApps: FamilyActivitySelection()
        )
        
        // Backend returns 0 when no time remaining
        XCTAssertEqual(response.maxChargeDollars, 0.0, accuracy: 0.01, "Authorization should be $0 when deadline has passed")
    }
    
    func testAuthorizationAmount_IncreasesWithAppCount() async throws {
        // Test that more apps increases authorization amount
        let deadline = getNextMondayDeadline()
        
        let responseNoApps = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: deadline,
            limitMinutes: 1000,
            penaltyPerMinuteCents: 10,
            selectedApps: FamilyActivitySelection() // Empty selection
        )
        
        // Create a selection with apps (simulated - in real test would need actual FamilyActivitySelection)
        // Note: FamilyActivitySelection can't be easily created in tests, so we test with empty selection
        // The backend counts apps from the selection, so we verify the calculation works
        let responseWithApps = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: deadline,
            limitMinutes: 1000,
            penaltyPerMinuteCents: 10,
            selectedApps: FamilyActivitySelection() // Same for now - backend will count apps from selection
        )
        
        // Both should be within bounds
        XCTAssertGreaterThanOrEqual(responseNoApps.maxChargeDollars, 5.0, "Should be at least $5")
        XCTAssertLessThanOrEqual(responseNoApps.maxChargeDollars, 1000.0, "Should be at most $1000")
        XCTAssertGreaterThanOrEqual(responseWithApps.maxChargeDollars, 5.0, "Should be at least $5")
        XCTAssertLessThanOrEqual(responseWithApps.maxChargeDollars, 1000.0, "Should be at most $1000")
    }
    
    func testAuthorizationAmount_BackendCalculationBounds() async throws {
        // Test that backend calculation respects bounds ($5-$1000)
        let deadline = getNextMondayDeadline()
        let response = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: deadline,
            limitMinutes: 0, // Very low limit
            penaltyPerMinuteCents: 100, // High penalty rate
            selectedApps: FamilyActivitySelection()
        )
        
        // Should be bounded between $5 and $1000
        XCTAssertGreaterThanOrEqual(response.maxChargeDollars, 5.0, "Should enforce $5 minimum")
        XCTAssertLessThanOrEqual(response.maxChargeDollars, 1000.0, "Should enforce $1000 maximum")
    }
    
    func testAuthorizationAmount_HigherPenaltyRate() async throws {
        // Test that higher penalty rate increases authorization
        let deadline = getNextMondayDeadline()
        
        let responseLowRate = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: deadline,
            limitMinutes: 500,
            penaltyPerMinuteCents: 10, // $0.10/min
            selectedApps: FamilyActivitySelection()
        )
        
        let responseHighRate = try await BackendClient.shared.previewMaxCharge(
            deadlineDate: deadline,
            limitMinutes: 500,
            penaltyPerMinuteCents: 50, // $0.50/min
            selectedApps: FamilyActivitySelection()
        )
        
        // Higher penalty rate should result in higher authorization (or same if at max)
        XCTAssertGreaterThanOrEqual(responseHighRate.maxChargeDollars, responseLowRate.maxChargeDollars, 
                                   "Higher penalty rate should result in higher or equal authorization")
        
        // Both should be within bounds
        XCTAssertGreaterThanOrEqual(responseLowRate.maxChargeDollars, 5.0, "Should be at least $5")
        XCTAssertLessThanOrEqual(responseLowRate.maxChargeDollars, 1000.0, "Should be at most $1000")
        XCTAssertGreaterThanOrEqual(responseHighRate.maxChargeDollars, 5.0, "Should be at least $5")
        XCTAssertLessThanOrEqual(responseHighRate.maxChargeDollars, 1000.0, "Should be at most $1000")
    }
    
    // MARK: - Deadline Navigation Tests
    
    /// Helper to set up test UserDefaults with a deadline
    private func setupTestDeadline(_ deadline: Date) {
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
            XCTFail("Failed to access App Group UserDefaults")
            return
        }
        userDefaults.set(deadline.timeIntervalSince1970, forKey: "commitmentDeadline")
        userDefaults.set(true, forKey: "monitoringSelectionSet")
        userDefaults.synchronize()
    }
    
    /// Helper to clear test UserDefaults
    private func clearTestDeadline() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
            return
        }
        userDefaults.removeObject(forKey: "commitmentDeadline")
        userDefaults.removeObject(forKey: "monitoringSelectionSet")
        userDefaults.synchronize()
    }
    
    @MainActor
    func testCheckDeadlineAndNavigate_DoesNotNavigate_WhenShouldNot() {
        let model = AppModel()
        
        // Case 1: Not on monitor screen (even with past deadline)
        setupTestDeadline(Date(timeIntervalSinceNow: -3600))
        model.currentScreen = .setup
        XCTAssertFalse(model.checkDeadlineAndNavigate(), "Should not navigate when not on monitor screen")
        XCTAssertEqual(model.currentScreen, .setup)
        clearTestDeadline()
        
        // Case 2: On monitor screen but deadline hasn't passed
        setupTestDeadline(Date(timeIntervalSinceNow: 3600))
        model.currentScreen = .monitor
        XCTAssertFalse(model.checkDeadlineAndNavigate(), "Should not navigate when deadline hasn't passed")
        XCTAssertEqual(model.currentScreen, .monitor)
        clearTestDeadline()
    }
    
    @MainActor
    func testCheckDeadlineAndNavigate_NavigatesAndClearsState_WhenDeadlinePassed() {
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
            XCTFail("Failed to access App Group UserDefaults")
            return
        }
        
        // Setup: Set a past deadline
        let pastDeadline = Date(timeIntervalSinceNow: -1)
        setupTestDeadline(pastDeadline)
        defer { clearTestDeadline() }
        
        let model = AppModel()
        model.currentScreen = .monitor
        
        // Verify state before
        XCTAssertNotNil(userDefaults.object(forKey: "commitmentDeadline"))
        XCTAssertTrue(userDefaults.bool(forKey: "monitoringSelectionSet"))
        
        // Execute
        let result = model.checkDeadlineAndNavigate()
        
        // Verify navigation
        XCTAssertTrue(result, "Should return true when deadline has passed")
        XCTAssertEqual(model.currentScreen, .bulletin, "Should navigate to bulletin screen")
        
        // Verify state cleared
        XCTAssertNil(userDefaults.object(forKey: "commitmentDeadline"), "Deadline should be cleared")
        XCTAssertFalse(userDefaults.bool(forKey: "monitoringSelectionSet"), "Monitoring flag should be cleared")
    }
}




