import XCTest
@testable import payattentionclub_app_1_1

/// Unit tests for response model decoding
@MainActor
final class BackendClientTests: XCTestCase {
    
    // MARK: - BillingStatusResponse Decoding
    
    func testBillingStatusResponse_FullPayload() throws {
        let json = """
        {
            "has_payment_method": true,
            "needs_setup_intent": false,
            "setup_intent_client_secret": "seti_123_secret_456",
            "stripe_customer_id": "cus_abc123"
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(BillingStatusResponse.self, from: data)
        
        XCTAssertTrue(response.hasPaymentMethod)
        XCTAssertFalse(response.needsSetupIntent)
        XCTAssertEqual(response.setupIntentClientSecret, "seti_123_secret_456")
        XCTAssertEqual(response.stripeCustomerId, "cus_abc123")
    }
    
    func testBillingStatusResponse_MissingOptionalFields() throws {
        let json = """
        {
            "has_payment_method": false,
            "needs_setup_intent": true
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(BillingStatusResponse.self, from: data)
        
        XCTAssertFalse(response.hasPaymentMethod)
        XCTAssertTrue(response.needsSetupIntent)
        XCTAssertNil(response.setupIntentClientSecret)
        XCTAssertNil(response.stripeCustomerId)
    }
    
    func testBillingStatusResponse_DefaultsForMissingFields() throws {
        // Edge case: completely empty response (uses defaults)
        let json = "{}"
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(BillingStatusResponse.self, from: data)
        
        XCTAssertFalse(response.hasPaymentMethod, "Should default to false")
        XCTAssertFalse(response.needsSetupIntent, "Should default to false")
    }
    
    // MARK: - CommitmentResponse Decoding
    
    func testCommitmentResponse_FullPayload() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "week_start_date": "2025-12-08",
            "week_end_date": "2025-12-15",
            "status": "active",
            "max_charge_cents": 5000
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CommitmentResponse.self, from: data)
        
        XCTAssertEqual(response.commitmentId, "123E4567-E89B-12D3-A456-426614174000")
        XCTAssertEqual(response.startDate, "2025-12-08")
        XCTAssertEqual(response.deadlineDate, "2025-12-15")
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.maxChargeCents, 5000)
    }
    
    func testCommitmentResponse_StringUUID() throws {
        let json = """
        {
            "id": "abc-123-def",
            "week_start_date": "2025-12-08",
            "week_end_date": "2025-12-15",
            "status": "active",
            "max_charge_cents": 1000
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(CommitmentResponse.self, from: data)
        
        XCTAssertEqual(response.commitmentId, "abc-123-def")
    }
    
    // MARK: - UsageReportResponse Decoding
    
    func testUsageReportResponse_FullPayload() throws {
        let json = """
        {
            "date": "2025-12-10",
            "limit_minutes": 120,
            "used_minutes": 150,
            "exceeded_minutes": 30,
            "penalty_cents": 300,
            "user_week_total_cents": 500,
            "pool_total_cents": 2500
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageReportResponse.self, from: data)
        
        XCTAssertEqual(response.date, "2025-12-10")
        XCTAssertEqual(response.limitMinutes, 120)
        XCTAssertEqual(response.usedMinutes, 150)
        XCTAssertEqual(response.exceededMinutes, 30)
        XCTAssertEqual(response.penaltyCents, 300)
        XCTAssertEqual(response.userWeekTotalCents, 500)
        XCTAssertEqual(response.poolTotalCents, 2500)
    }
    
    func testUsageReportResponse_ZeroValues() throws {
        let json = """
        {
            "date": "2025-12-10",
            "limit_minutes": 120,
            "used_minutes": 60,
            "exceeded_minutes": 0,
            "penalty_cents": 0,
            "user_week_total_cents": 0,
            "pool_total_cents": 0
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageReportResponse.self, from: data)
        
        XCTAssertEqual(response.exceededMinutes, 0)
        XCTAssertEqual(response.penaltyCents, 0)
    }
    
    // MARK: - SyncDailyUsageResponse Decoding
    
    func testSyncDailyUsageResponse_FullPayload() throws {
        let json = """
        {
            "synced_count": 3,
            "failed_count": 1,
            "synced_dates": ["2025-12-08", "2025-12-09", "2025-12-10"],
            "failed_dates": ["2025-12-07"],
            "errors": ["Commitment not found for date"],
            "processed_weeks": ["2025-12-08"]
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SyncDailyUsageResponse.self, from: data)
        
        XCTAssertEqual(response.syncedCount, 3)
        XCTAssertEqual(response.failedCount, 1)
        XCTAssertEqual(response.syncedDates?.count, 3)
        XCTAssertEqual(response.failedDates?.first, "2025-12-07")
        XCTAssertEqual(response.errors?.first, "Commitment not found for date")
    }
    
    func testSyncDailyUsageResponse_EmptyArrays() throws {
        let json = """
        {
            "synced_count": 0,
            "failed_count": 0,
            "synced_dates": [],
            "failed_dates": [],
            "errors": [],
            "processed_weeks": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SyncDailyUsageResponse.self, from: data)
        
        XCTAssertEqual(response.syncedCount, 0)
        XCTAssertEqual(response.syncedDates?.count, 0)
    }
    
    func testSyncDailyUsageResponse_NullFields() throws {
        let json = """
        {
            "synced_count": 2,
            "failed_count": null,
            "synced_dates": ["2025-12-08", "2025-12-09"],
            "failed_dates": null,
            "errors": null,
            "processed_weeks": null
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SyncDailyUsageResponse.self, from: data)
        
        XCTAssertEqual(response.syncedCount, 2)
        XCTAssertNil(response.failedCount)
        XCTAssertNil(response.failedDates)
    }
    
    // MARK: - WeekStatusResponse Decoding
    
    func testWeekStatusResponse_FullPayload() throws {
        let json = """
        {
            "user_total_penalty_cents": 1500,
            "user_status": "charged",
            "user_max_charge_cents": 5000,
            "pool_total_penalty_cents": 12500,
            "pool_status": "closed",
            "pool_instagram_post_url": "https://instagram.com/p/abc123",
            "pool_instagram_image_url": "https://cdn.instagram.com/image.jpg",
            "user_settlement_status": "completed",
            "charged_amount_cents": 1500,
            "actual_amount_cents": 1200,
            "refund_amount_cents": 300,
            "needs_reconciliation": true,
            "reconciliation_delta_cents": -300,
            "reconciliation_reason": "late_sync",
            "reconciliation_detected_at": "2025-12-16T12:00:00Z",
            "week_grace_expires_at": "2025-12-16T12:00:00Z",
            "week_end_date": "2025-12-15"
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WeekStatusResponse.self, from: data)
        
        XCTAssertEqual(response.userTotalPenaltyCents, 1500)
        XCTAssertEqual(response.userStatus, "charged")
        XCTAssertEqual(response.poolStatus, "closed")
        XCTAssertEqual(response.poolInstagramPostUrl, "https://instagram.com/p/abc123")
        XCTAssertTrue(response.needsReconciliation)
        XCTAssertEqual(response.reconciliationDeltaCents, -300)
        XCTAssertEqual(response.reconciliationReason, "late_sync")
    }
    
    func testWeekStatusResponse_MinimalPayload() throws {
        // Only required fields, rest should have defaults
        let json = "{}"
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WeekStatusResponse.self, from: data)
        
        XCTAssertEqual(response.userTotalPenaltyCents, 0)
        XCTAssertEqual(response.userStatus, "none")
        XCTAssertEqual(response.poolStatus, "open")
        XCTAssertEqual(response.userSettlementStatus, "pending")
        XCTAssertFalse(response.needsReconciliation)
        XCTAssertNil(response.poolInstagramPostUrl)
    }
    
    func testWeekStatusResponse_PendingStatus() throws {
        let json = """
        {
            "user_total_penalty_cents": 500,
            "user_status": "pending",
            "user_max_charge_cents": 2000,
            "pool_total_penalty_cents": 500,
            "pool_status": "open",
            "user_settlement_status": "pending",
            "charged_amount_cents": 0,
            "actual_amount_cents": 0,
            "refund_amount_cents": 0,
            "needs_reconciliation": false,
            "reconciliation_delta_cents": 0
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WeekStatusResponse.self, from: data)
        
        XCTAssertEqual(response.userStatus, "pending")
        XCTAssertEqual(response.poolStatus, "open")
        XCTAssertEqual(response.chargedAmountCents, 0)
        XCTAssertFalse(response.needsReconciliation)
    }
    
    // MARK: - ConfirmSetupIntentResponse Decoding
    
    func testConfirmSetupIntentResponse_Success() throws {
        let json = """
        {
            "success": true,
            "setupIntentId": "seti_123abc",
            "paymentMethodId": "pm_456def",
            "alreadyConfirmed": false
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ConfirmSetupIntentResponse.self, from: data)
        
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.setupIntentId, "seti_123abc")
        XCTAssertEqual(response.paymentMethodId, "pm_456def")
        XCTAssertEqual(response.alreadyConfirmed, false)
    }
    
    func testConfirmSetupIntentResponse_AlreadyConfirmed() throws {
        let json = """
        {
            "success": true,
            "alreadyConfirmed": true
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ConfirmSetupIntentResponse.self, from: data)
        
        XCTAssertTrue(response.success)
        XCTAssertTrue(response.alreadyConfirmed ?? false)
        XCTAssertNil(response.setupIntentId)
    }
    
    func testConfirmSetupIntentResponse_Failure() throws {
        let json = """
        {
            "success": false
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ConfirmSetupIntentResponse.self, from: data)
        
        XCTAssertFalse(response.success)
    }
    
    // MARK: - Edge Cases
    
    func testDecodingWithExtraFields() throws {
        // Backend might add new fields - decoder should ignore unknown fields
        let json = """
        {
            "has_payment_method": true,
            "needs_setup_intent": false,
            "some_new_field": "value",
            "another_new_field": 123
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(BillingStatusResponse.self, from: data)
        
        XCTAssertTrue(response.hasPaymentMethod)
        XCTAssertFalse(response.needsSetupIntent)
    }
}

