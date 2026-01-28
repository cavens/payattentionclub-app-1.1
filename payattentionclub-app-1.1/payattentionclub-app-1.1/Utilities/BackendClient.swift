import Foundation
import Supabase
import Auth
import FamilyControls
import PostgREST

// MARK: - Local Storage Implementation

/// Simple UserDefaults-based localStorage implementation for Supabase Auth
private final class UserDefaultsLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let userDefaults: UserDefaults
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func store(key: String, value: Data) throws {
        userDefaults.set(value, forKey: key)
        userDefaults.synchronize()
    }
    
    func retrieve(key: String) throws -> Data? {
        return userDefaults.data(forKey: key)
    }
    
    func remove(key: String) throws {
        userDefaults.removeObject(forKey: key)
        userDefaults.synchronize()
    }
}

// MARK: - Request Parameter Models

struct EmptyBody: Encodable, Sendable {}

struct AppsToLimit: Codable, Sendable {
    let appBundleIds: [String]
    let categories: [String]
    
    enum CodingKeys: String, CodingKey {
        case appBundleIds = "app_bundle_ids"
        case categories
    }
}

struct CreateCommitmentParams: Encodable, Sendable {
    let weekStartDate: String  // ISO date string (YYYY-MM-DD)
    let limitMinutes: Int
    let penaltyPerMinuteCents: Int
    let appsToLimit: AppsToLimit
    
    enum CodingKeys: String, CodingKey {
        // Backend RPC function expects parameters with p_ prefix
        case weekStartDate = "p_week_start_date"
        case limitMinutes = "p_limit_minutes"
        case penaltyPerMinuteCents = "p_penalty_per_minute_cents"
        case appsToLimit = "p_apps_to_limit"
    }
    
    // Explicitly mark encoding as nonisolated to avoid MainActor inference
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekStartDate, forKey: .weekStartDate)
        try container.encode(limitMinutes, forKey: .limitMinutes)
        try container.encode(penaltyPerMinuteCents, forKey: .penaltyPerMinuteCents)
        try container.encode(appsToLimit, forKey: .appsToLimit)
    }
}

struct CreateCommitmentEdgeFunctionBody: Encodable, Sendable {
    // Note: weekStartDate removed - backend now calculates deadline internally (single source of truth)
    let limitMinutes: Int
    let penaltyPerMinuteCents: Int
    let appCount: Int  // Explicit app count parameter (single source of truth)
    let appsToLimit: AppsToLimit
    let savedPaymentMethodId: String?
    
    // Explicitly implement encoding to ensure nonisolated conformance
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(limitMinutes, forKey: .limitMinutes)
        try container.encode(penaltyPerMinuteCents, forKey: .penaltyPerMinuteCents)
        try container.encode(appCount, forKey: .appCount)
        try container.encode(appsToLimit, forKey: .appsToLimit)
        try container.encodeIfPresent(savedPaymentMethodId, forKey: .savedPaymentMethodId)
    }
    
    enum CodingKeys: String, CodingKey {
        case limitMinutes
        case penaltyPerMinuteCents
        case appCount
        case appsToLimit
        case savedPaymentMethodId
    }
}

struct SyncDailyUsageEntryPayload: Codable, Sendable {
    let date: String
    let weekStartDate: String
    let usedMinutes: Int
    
    enum CodingKeys: String, CodingKey {
        case date
        case weekStartDate = "week_start_date"
        case usedMinutes = "used_minutes"
    }
}

struct SyncDailyUsageParams: Encodable, Sendable {
    let entries: [SyncDailyUsageEntryPayload]
    
    enum CodingKeys: String, CodingKey {
        case entries = "p_entries"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}

// ProcessedWeek represents a week that was processed during sync, including reconciliation metadata
struct ProcessedWeek: Codable, Sendable {
    let weekEndDate: String
    let totalPenaltyCents: Int?
    let needsReconciliation: Bool?
    let reconciliationDeltaCents: Int?
    
    enum CodingKeys: String, CodingKey {
        case weekEndDate = "week_end_date"
        case totalPenaltyCents = "total_penalty_cents"
        case needsReconciliation = "needs_reconciliation"
        case reconciliationDeltaCents = "reconciliation_delta_cents"
    }
}

struct SyncDailyUsageResponse: Codable, Sendable {
    let syncedCount: Int?
    let failedCount: Int?
    let syncedDates: [String]?
    let failedDates: [String]?
    let errors: [String]?
    let processedWeeks: [ProcessedWeek]?  // Changed from [String]? to match RPC response structure
    
    enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case failedCount = "failed_count"
        case syncedDates = "synced_dates"
        case failedDates = "failed_dates"
        case errors
        case processedWeeks = "processed_weeks"
    }
    
    // Explicit nonisolated decoder to avoid MainActor isolation issues in Swift 6
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncedCount = try container.decodeIfPresent(Int.self, forKey: .syncedCount)
        failedCount = try container.decodeIfPresent(Int.self, forKey: .failedCount)
        syncedDates = try container.decodeIfPresent([String].self, forKey: .syncedDates)
        failedDates = try container.decodeIfPresent([String].self, forKey: .failedDates)
        errors = try container.decodeIfPresent([String].self, forKey: .errors)
        processedWeeks = try container.decodeIfPresent([ProcessedWeek].self, forKey: .processedWeeks)
    }
}

// MARK: - Response Models

struct BillingStatusResponse: Codable {
    let hasPaymentMethod: Bool
    let needsPaymentIntent: Bool
    let paymentIntentClientSecret: String?
    let stripeCustomerId: String?
    
    enum CodingKeys: String, CodingKey {
        case hasPaymentMethod = "has_payment_method"
        case needsPaymentIntent = "needs_payment_intent"
        case paymentIntentClientSecret = "payment_intent_client_secret"
        case stripeCustomerId = "stripe_customer_id"
    }
    
    // Custom decoder to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode fields, use defaults if missing
        hasPaymentMethod = try container.decodeIfPresent(Bool.self, forKey: .hasPaymentMethod) ?? false
        needsPaymentIntent = try container.decodeIfPresent(Bool.self, forKey: .needsPaymentIntent) ?? false
        paymentIntentClientSecret = try container.decodeIfPresent(String.self, forKey: .paymentIntentClientSecret)
        stripeCustomerId = try container.decodeIfPresent(String.self, forKey: .stripeCustomerId)
    }
}

struct ConfirmPaymentIntentResponse: Codable, Sendable {
    let success: Bool
    let paymentIntentId: String?
    let paymentMethodId: String?
    let alreadyProcessed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case success
        case paymentIntentId
        case paymentMethodId
        case alreadyProcessed
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        paymentIntentId = try container.decodeIfPresent(String.self, forKey: .paymentIntentId)
        paymentMethodId = try container.decodeIfPresent(String.self, forKey: .paymentMethodId)
        alreadyProcessed = try container.decodeIfPresent(Bool.self, forKey: .alreadyProcessed)
    }
}

struct CommitmentResponse: Codable, Sendable {
    let commitmentId: String
    /// The date when the commitment actually started (when user committed)
    /// Maps to `week_start_date` column in database (legacy naming)
    let startDate: String
    /// The deadline when the commitment ends (ISO8601 timestamp)
    /// Maps to `week_end_timestamp` field in database (primary source of truth)
    let deadlineDate: String
    let status: String
    let maxChargeCents: Int
    
    enum CodingKeys: String, CodingKey {
        case commitmentId = "id"  // RPC function returns 'id' from commitments table
        case startDate = "week_start_date"  // Database column name (legacy)
        case deadlineDate = "week_end_timestamp"  // Timestamp field (primary source of truth)
        case status
        case maxChargeCents = "max_charge_cents"
    }
    
    // Explicit nonisolated decoder to avoid MainActor isolation issues in Swift 6
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try to decode as UUID first (PostgreSQL UUID type), then convert to String
        if let uuid = try? container.decode(UUID.self, forKey: .commitmentId) {
            commitmentId = uuid.uuidString
        } else {
            commitmentId = try container.decode(String.self, forKey: .commitmentId)
        }
        startDate = try container.decode(String.self, forKey: .startDate)
        deadlineDate = try container.decode(String.self, forKey: .deadlineDate)
        status = try container.decode(String.self, forKey: .status)
        maxChargeCents = try container.decode(Int.self, forKey: .maxChargeCents)
    }
}

// MARK: - Errors

enum BackendError: LocalizedError {
    case notAuthenticated
    case serverError(String)
    case decodingError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Backend Client

/// Client for interacting with PAC backend (Supabase)
/// 
/// Supabase Function Names Reference:
/// RPC Functions:
///   - rpc_create_commitment
///   - rpc_report_usage
///   - rpc_update_monitoring_status
///   - rpc_get_week_status
///   - call_weekly_close
/// Edge Functions:
///   - billing-status
///   - weekly-close
///   - stripe-webhook
///   - admin-close-week-now
class BackendClient {
    static let shared = BackendClient()
    
    private let supabase: SupabaseClient
    
    private init() {
        // Initialize Supabase client with Auth configuration
        let localStorage = UserDefaultsLocalStorage()
        
        // Opt-in to new Auth behavior immediately (silences warning)
        let authConfig = AuthClient.Configuration(
            localStorage: localStorage,
            emitLocalSessionAsInitialSession: true
        )
        _ = AuthClient(configuration: authConfig)
        
        // Opt-in to emitting the locally stored session immediately to silence warning
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: localStorage,
            emitLocalSessionAsInitialSession: true
        )
        
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectURL)!,
            supabaseKey: SupabaseConfig.publishableKey,
            options: SupabaseClientOptions(
                auth: authOptions
            )
        )
    }
    
    // MARK: - Authentication
    
    /// Get current session (if authenticated)
    var currentSession: Session? {
        get async {
            do {
                return try await supabase.auth.session
            } catch {
                return nil
            }
        }
    }
    
    /// Check if user is authenticated
    var isAuthenticated: Bool {
        get async {
            do {
                _ = try await supabase.auth.session
                return true
            } catch {
                return false
            }
        }
    }
    
    /// Sign in with Apple ID token
    /// - Parameters:
    ///   - idToken: The Apple ID token string
    ///   - nonce: The nonce used for the Apple sign-in request
    ///   - email: Optional email address from Apple credential (only available on first sign-in)
    /// - Returns: The authenticated session
    func signInWithApple(idToken: String, nonce: String, email: String?) async throws -> Session {
        // 1. Authenticate with Supabase (uses ID token, may get private relay email)
        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        
        // 2. If we have a real email from Apple credential (not private relay), update the database
        // Note: email is only provided on first sign-in when user chooses "Share My Email"
        // On subsequent sign-ins, email will be nil
        if let realEmail = email, !realEmail.contains("@privaterelay.appleid.com") {
            do {
                try await updateUserEmailIfReal(email: realEmail, userId: session.user.id)
                NSLog("AUTH BackendClient: ✅ Updated user email to real email: \(realEmail)")
            } catch {
                // Log error but don't fail authentication if email update fails
                NSLog("AUTH BackendClient: ⚠️ Failed to update user email: \(error.localizedDescription)")
            }
        } else if let email = email, email.contains("@privaterelay.appleid.com") {
            NSLog("AUTH BackendClient: 📧 User chose to hide email, using private relay: \(email)")
        } else {
            NSLog("AUTH BackendClient: 📧 No email in credential (subsequent sign-in), keeping existing email")
        }
        
        return session
    }
    
    /// Update user email in database if it's a real email (not private relay)
    /// Uses direct table update with RLS policy ensuring user can only update their own row
    /// - Parameters:
    ///   - email: The email address to update
    ///   - userId: The user ID to update
    private func updateUserEmailIfReal(email: String, userId: UUID) async throws {
        // Validate email is not empty and not a private relay
        guard !email.isEmpty, !email.contains("@privaterelay.appleid.com") else {
            NSLog("AUTH BackendClient: ⏭️ Skipping email update (empty or private relay)")
            return
        }
        
        // Direct update to public.users table
        // RLS policy "Users can update own data" ensures user can only update their own row
        struct UserEmailUpdate: Encodable {
            let email: String
            let updated_at: String
        }
        
        let update = UserEmailUpdate(
            email: email,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        _ = try await supabase
            .from("users")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        NSLog("AUTH BackendClient: ✅ Email updated successfully")
    }
    
    /// Sign out the current user
    func signOut() async throws {
        try await supabase.auth.signOut()
    }
    
    // MARK: - API Methods
    
    /// 1. Check billing status and create PaymentIntent if needed
    /// Calls: billing-status Edge Function
    /// - Parameters:
    ///   - authorizationAmountCents: The authorization amount in cents (required if payment method doesn't exist)
    /// - Throws: BackendError.notAuthenticated if user is not signed in
    func checkBillingStatus(authorizationAmountCents: Int? = nil) async throws -> BillingStatusResponse {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        NSLog("BILLING BackendClient: Calling billing-status Edge Function...")
        if let amount = authorizationAmountCents {
            NSLog("BILLING BackendClient: Authorization amount: \(amount) cents ($\(Double(amount) / 100.0))")
        }
        
        do {
            struct BillingStatusRequest: Encodable, Sendable {
                let authorizationAmountCents: Int?
                
                enum CodingKeys: String, CodingKey {
                    case authorizationAmountCents = "authorization_amount_cents"
                }
            }
            
            let requestBody = BillingStatusRequest(authorizationAmountCents: authorizationAmountCents)
            
            // Note: supabase.functions.invoke() directly decodes, so we can't easily see raw JSON
            // But the custom decoder will handle missing fields gracefully
            let response: BillingStatusResponse = try await supabase.functions.invoke(
                "billing-status",
                options: FunctionInvokeOptions(
                    body: requestBody
                )
            )
            
            NSLog("BILLING BackendClient: ✅ Successfully decoded BillingStatusResponse")
            NSLog("BILLING BackendClient: hasPaymentMethod: \(response.hasPaymentMethod)")
            NSLog("BILLING BackendClient: needsPaymentIntent: \(response.needsPaymentIntent)")
            NSLog("BILLING BackendClient: paymentIntentClientSecret: \(response.paymentIntentClientSecret ?? "nil")")
            NSLog("BILLING BackendClient: stripeCustomerId: \(response.stripeCustomerId ?? "nil")")
            
            return response
        } catch let error as FunctionsError {
            NSLog("BILLING BackendClient: ❌ Edge Function call failed: \(error)")
            NSLog("BILLING BackendClient: Error localizedDescription: \(error.localizedDescription)")
            
            // Extract detailed error message from httpError
            var errorMessage = error.localizedDescription
            var errorDetails: String? = nil
            let mirror = Mirror(reflecting: error)
            for child in mirror.children {
                if child.label == "httpError" {
                    NSLog("BILLING BackendClient: Found httpError property")
                    let httpErrorMirror = Mirror(reflecting: child.value)
                    let httpErrorChildren = Array(httpErrorMirror.children)
                    NSLog("BILLING BackendClient: httpError has \(httpErrorChildren.count) children")
                    
                    // Try to find the data element (error response body)
                    for (index, httpChild) in httpErrorChildren.enumerated() {
                        NSLog("BILLING BackendClient: httpError[\(index)]: label=\(httpChild.label ?? "nil"), type=\(type(of: httpChild.value))")
                        if let data = httpChild.value as? Data {
                            NSLog("BILLING BackendClient: Found error Data at index \(index), size: \(data.count) bytes")
                            if let errorString = String(data: data, encoding: .utf8) {
                                NSLog("BILLING BackendClient: ⚠️ ERROR RESPONSE BODY (raw): \(errorString)")
                                errorDetails = errorString
                                
                                // Try to parse as JSON
                                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    NSLog("BILLING BackendClient: ⚠️ ERROR RESPONSE (parsed JSON):")
                                    for (key, value) in errorJson {
                                        NSLog("BILLING BackendClient:   \(key): \(value)")
                                    }
                                    if let message = errorJson["error"] as? String {
                                        errorMessage = message
                                    }
                                    if let details = errorJson["details"] as? String {
                                        NSLog("BILLING BackendClient: ⚠️ ERROR DETAILS: \(details)")
                                    }
                                } else {
                                    errorMessage = errorString
                                }
                                break
                            } else {
                                NSLog("BILLING BackendClient: ⚠️ Error data is not valid UTF-8, hex: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
                            }
                        }
                    }
                }
            }
            
            throw BackendError.serverError("Edge Function error: \(errorMessage)\(errorDetails != nil ? " | Details: \(errorDetails!)" : "")")
        } catch {
            NSLog("BILLING BackendClient: ❌ Failed to decode BillingStatusResponse: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    NSLog("BILLING BackendClient: Missing key: \(key.stringValue)")
                    NSLog("BILLING BackendClient: Context: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    NSLog("BILLING BackendClient: Type mismatch: \(type)")
                    NSLog("BILLING BackendClient: Context: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    NSLog("BILLING BackendClient: Value not found: \(type)")
                    NSLog("BILLING BackendClient: Context: \(context.debugDescription)")
                case .dataCorrupted(let context):
                    NSLog("BILLING BackendClient: Data corrupted: \(context.debugDescription)")
                @unknown default:
                    NSLog("BILLING BackendClient: Unknown decoding error: \(decodingError)")
                }
            }
            throw error
        }
    }
    
    /// 1.5. Confirm PaymentIntent with Apple Pay PaymentMethod and cancel it immediately
    /// Calls: rapid-service Edge Function
    /// - Parameters:
    ///   - clientSecret: The PaymentIntent client secret
    ///   - paymentMethodId: Stripe PaymentMethod ID (created from Apple Pay token)
    /// - Returns: The saved payment method ID (from setup_future_usage)
    /// - Throws: BackendError if confirmation fails
    nonisolated func confirmPaymentIntentAndCancel(
        clientSecret: String,
        paymentMethodId: String
    ) async throws -> String {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        NSLog("APPLEPAY BackendClient: Confirming PaymentIntent with PaymentMethod ID: \(paymentMethodId)")
        NSLog("APPLEPAY BackendClient: PaymentIntent will be cancelled immediately after confirmation")
        
        struct ConfirmPaymentIntentBody: Encodable, Sendable {
            let clientSecret: String
            let paymentMethodId: String
        }
        
        let requestBody = ConfirmPaymentIntentBody(
            clientSecret: clientSecret,
            paymentMethodId: paymentMethodId
        )
        
        return try await Task.detached(priority: .userInitiated) { [supabase] in
            do {
                // Call Edge Function to confirm and cancel PaymentIntent
                let response: ConfirmPaymentIntentResponse = try await supabase.functions.invoke(
                    "rapid-service",
                    options: FunctionInvokeOptions(
                        body: requestBody
                    )
                )
                
                guard response.success, let savedPaymentMethodId = response.paymentMethodId else {
                    throw BackendError.serverError("PaymentIntent confirmation failed or payment method not saved")
                }
                
                NSLog("APPLEPAY BackendClient: ✅ PaymentIntent confirmed and cancelled")
                NSLog("APPLEPAY BackendClient: ✅ Saved payment method ID: \(savedPaymentMethodId)")
                return savedPaymentMethodId
            } catch let error as FunctionsError {
                NSLog("APPLEPAY BackendClient: ❌ Edge Function call failed: \(error)")
                
                // Extract detailed error message from httpError
                var errorMessage = error.localizedDescription
                let mirror = Mirror(reflecting: error)
                for child in mirror.children {
                    if child.label == "httpError" {
                        let httpErrorMirror = Mirror(reflecting: child.value)
                        let httpErrorChildren = Array(httpErrorMirror.children)
                        for (index, httpChild) in httpErrorChildren.enumerated() {
                            if let data = httpChild.value as? Data {
                                NSLog("APPLEPAY BackendClient: Found error Data at index \(index), size: \(data.count) bytes")
                                if let errorString = String(data: data, encoding: .utf8) {
                                    NSLog("APPLEPAY BackendClient: Error response body: \(errorString)")
                                    // Try to parse as JSON
                                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        if let message = errorJson["error"] as? String {
                                            errorMessage = message
                                        } else if let details = errorJson["details"] as? String {
                                            errorMessage = details
                                        }
                                        // Log full error details
                                        if let detailsJson = errorJson["details"] as? String,
                                           let detailsData = detailsJson.data(using: .utf8),
                                           let detailsDict = try? JSONSerialization.jsonObject(with: detailsData) as? [String: Any] {
                                            NSLog("APPLEPAY BackendClient: Stripe error details: \(detailsDict)")
                                        }
                                    } else {
                                        errorMessage = errorString
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
                
                throw BackendError.serverError("Failed to confirm payment setup: \(errorMessage)")
            } catch {
                NSLog("APPLEPAY BackendClient: ❌ Unexpected error: \(error)")
                throw BackendError.serverError("Failed to confirm payment setup: \(error.localizedDescription)")
            }
        }.value
    }
    
    /// 2. Create a commitment
    /// Calls: Edge Function which calls rpc_create_commitment RPC function
    /// - Parameters:
    ///   - limitMinutes: Daily time limit in minutes
    ///   - penaltyPerMinuteCents: Penalty per minute in cents (e.g., 10 = $0.10)
    ///   - selectedApps: FamilyActivitySelection containing apps and categories to limit
    ///   - savedPaymentMethodId: The saved payment method ID from PaymentIntent confirmation (optional)
    /// - Returns: CommitmentResponse with commitment details
    /// - Throws: BackendError.notAuthenticated if user is not signed in
    /// Note: Deadline is calculated by backend (single source of truth)
    nonisolated func createCommitment(
        limitMinutes: Int,
        penaltyPerMinuteCents: Int,
        selectedApps: FamilyActivitySelection,
        savedPaymentMethodId: String? = nil
    ) async throws -> CommitmentResponse {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        // Call Edge Function instead of RPC to avoid Supabase SDK auto-decoding issues
        // The Edge Function calls the RPC function and returns JSON properly
        // Backend calculates deadline internally (single source of truth)
        let task = Task.detached(priority: .userInitiated) { [supabase, limitMinutes, penaltyPerMinuteCents, savedPaymentMethodId, selectedApps] in
            // Extract app and category counts from FamilyActivitySelection
            // Note: We can't extract actual bundle IDs from opaque FamilyActivitySelection tokens,
            // but we can count them. The backend now uses explicit app_count parameter.
            let appCount = selectedApps.applicationTokens.count
            let categoryCount = selectedApps.categoryTokens.count
            let totalAppCount = appCount + categoryCount
            
            // Create placeholder arrays with the correct counts for storage
            // The backend only uses the array length for storage, not for calculation
            let appBundleIds = Array(repeating: "placeholder", count: appCount)
            let categories = Array(repeating: "placeholder", count: categoryCount)
            
            // Create AppsToLimit inside detached task (nonisolated)
            // Backend expects apps_to_limit as JSONB object with app_bundle_ids and categories arrays
            let appsToLimit = AppsToLimit(
                appBundleIds: appBundleIds,  // Pass correct count for storage
                categories: categories      // Pass correct count for storage
            )
            
            // Create request body for Edge Function
            // Note: weekStartDate removed - backend calculates deadline internally
            let requestBody = CreateCommitmentEdgeFunctionBody(
                limitMinutes: limitMinutes,
                penaltyPerMinuteCents: penaltyPerMinuteCents,
                appCount: totalAppCount,  // Pass explicit count (single source of truth)
                appsToLimit: appsToLimit,
                savedPaymentMethodId: savedPaymentMethodId
            )
            
            // Log the params being sent for debugging
            // Encoding happens in nonisolated context (Task.detached)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let paramsData = try? encoder.encode(requestBody)
            if let paramsData = paramsData,
               let paramsString = String(data: paramsData, encoding: .utf8) {
                NSLog("COMMITMENT BackendClient: Calling Edge Function with params: \(paramsString)")
            }
            
            // Call Edge Function via Functions API
            // Note: Function name is "super-service" (Supabase auto-renamed it)
            do {
                // Try to invoke and decode directly
                // requestBody is created in nonisolated context (Task.detached)
                let response: CommitmentResponse = try await supabase.functions.invoke(
                    "super-service",
                    options: FunctionInvokeOptions(
                        body: requestBody
                    )
                )
                
                NSLog("COMMITMENT BackendClient: ✅ Successfully decoded CommitmentResponse from Edge Function")
                return response
            } catch let error as FunctionsError {
                NSLog("COMMITMENT BackendClient: ❌ Edge Function call failed: \(error)")
                NSLog("COMMITMENT BackendClient: FunctionsError description: \(error.localizedDescription)")
                
                // Extract error message from httpError property
                var errorMessage = error.localizedDescription
                let mirror = Mirror(reflecting: error)
                for child in mirror.children {
                    if child.label == "httpError" {
                        NSLog("COMMITMENT BackendClient: Found httpError property")
                        // httpError is a tuple (code: Int, data: Data?)
                        let httpErrorMirror = Mirror(reflecting: child.value)
                        let httpErrorChildren = Array(httpErrorMirror.children)
                        NSLog("COMMITMENT BackendClient: httpError has \(httpErrorChildren.count) children")
                        // Try to find the data element
                        for (index, httpChild) in httpErrorChildren.enumerated() {
                            NSLog("COMMITMENT BackendClient: httpError[\(index)]: label=\(httpChild.label ?? "nil"), type=\(type(of: httpChild.value))")
                            if let data = httpChild.value as? Data {
                                NSLog("COMMITMENT BackendClient: Found Data at index \(index), size: \(data.count) bytes")
                                if let errorString = String(data: data, encoding: .utf8) {
                                    NSLog("COMMITMENT BackendClient: Error response body: \(errorString)")
                                    // Try to parse as JSON
                                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                       let message = errorJson["error"] as? String {
                                        errorMessage = message
                                    } else {
                                        errorMessage = errorString
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
                
                throw BackendError.serverError("Edge Function error: \(errorMessage)")
            } catch {
                NSLog("COMMITMENT BackendClient: ❌ Unexpected error: \(error)")
                NSLog("COMMITMENT BackendClient: Error type: \(type(of: error))")
                throw BackendError.serverError("Edge Function call failed: \(error.localizedDescription)")
            }
        }
        return try await task.value
    }
    
    /// 2.5. Batch sync daily usage entries
    /// Calls: rpc_sync_daily_usage (batch RPC)
    /// - Parameter entries: Array of unsynced daily usage entries from App Group
    /// - Returns: Array of date strings that were successfully synced
    nonisolated func syncDailyUsage(_ entries: [DailyUsageEntry]) async throws -> [String] {
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        guard !entries.isEmpty else {
            NSLog("SYNC BackendClient: ⚠️ syncDailyUsage() called with empty entries array")
            return []
        }
        
        let payload: [SyncDailyUsageEntryPayload] = entries.map { entry in
            let computedUsedMinutes = max(0, Int(entry.totalMinutes - entry.baselineMinutes))
            return SyncDailyUsageEntryPayload(
                date: entry.date,
                weekStartDate: entry.weekStartDate,
                usedMinutes: computedUsedMinutes
            )
        }
        
        let params = SyncDailyUsageParams(entries: payload)
        NSLog("SYNC BackendClient: 🔄 Calling rpc_sync_daily_usage with \(payload.count) entries")
        
        do {
            let builder = try supabase.rpc("rpc_sync_daily_usage", params: params)
            let response: PostgrestResponse<SyncDailyUsageResponse> = try await builder.execute()
            let value = response.value
            
            let syncedDates = value.syncedDates ?? []
            let failedDates = value.failedDates ?? []
            let errors = value.errors ?? []
            
            NSLog("SYNC BackendClient: ✅ rpc_sync_daily_usage synced \(syncedDates.count) dates, failed \(failedDates.count)")
            
            if !failedDates.isEmpty {
                NSLog("SYNC BackendClient: ⚠️ Failed dates: \(failedDates.joined(separator: ", "))")
            }
            
            if !errors.isEmpty {
                NSLog("SYNC BackendClient: ⚠️ Errors from backend: \(errors.joined(separator: "; "))")
            }
            
            return syncedDates
        } catch {
            NSLog("SYNC BackendClient: ❌ Failed to call rpc_sync_daily_usage: \(error)")
            throw BackendError.serverError("Failed to sync usage entries: \(error.localizedDescription)")
        }
    }
    
    /// 3. Report daily usage
    /// Calls: RPC function rpc_report_usage (or Edge Function if needed)
    /// - Parameters:
    ///   - date: The date for this usage report (typically today)
    ///   - weekStartDate: The week start date (deadline) for the commitment
    ///   - usedMinutes: Total minutes used today (currentUsageSeconds - baselineUsageSeconds) / 60
    /// - Returns: UsageReportResponse with daily penalty, weekly total, and pool total
    /// - Throws: BackendError if reporting fails
    nonisolated func reportUsage(
        date: Date,
        weekStartDate: Date,
        usedMinutes: Int
    ) async throws -> UsageReportResponse {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        NSLog("USAGE BackendClient: Reporting usage - date: \(date), weekStartDate: \(weekStartDate), usedMinutes: \(usedMinutes)")
        
        // Format dates as ISO strings (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York") // EST
        let dateString = dateFormatter.string(from: date)
        let weekStartDateString = dateFormatter.string(from: weekStartDate)
        
        struct ReportUsageParams: Encodable, Sendable {
            let p_date: String
            let p_week_start_date: String
            let p_used_minutes: Int
        }
        
        let params = ReportUsageParams(
            p_date: dateString,
            p_week_start_date: weekStartDateString,
            p_used_minutes: usedMinutes
        )
        
        do {
            let builder = try supabase.rpc("rpc_report_usage", params: params)
            let response: PostgrestResponse<UsageReportResponse> = try await builder.execute()
            NSLog("USAGE BackendClient: ✅ Successfully reported usage")
            return response.value
        } catch {
            NSLog("USAGE BackendClient: ❌ Failed to report usage: \(error)")
            throw BackendError.serverError("Failed to report usage: \(error.localizedDescription)")
        }
    }
    /// 4. Fetch weekly settlement + reconciliation status for the current commitment.
    /// Calls: RPC function rpc_get_week_status.
    /// - Parameter weekStartDate: Optional Monday deadline to query (defaults to backend auto-detection).
    /// - Returns: WeekStatusResponse with settlement + reconciliation metadata.
    nonisolated func fetchWeekStatus(weekStartDate: Date?) async throws -> WeekStatusResponse {
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }

        struct WeekStatusParams: Encodable, Sendable {
            let p_week_start_date: String?

            enum CodingKeys: String, CodingKey {
                case p_week_start_date
            }

            nonisolated func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let value = p_week_start_date {
                    try container.encode(value, forKey: .p_week_start_date)
                }
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        let encodedDate = weekStartDate.map { dateFormatter.string(from: $0) }
        
        // Diagnostic logging
        if let weekStartDate = weekStartDate {
            NSLog("SETTLEMENT BackendClient: 🔍 fetchWeekStatus called with weekStartDate: \(weekStartDate)")
            NSLog("SETTLEMENT BackendClient: 🔍 Converted to ET date string: \(encodedDate ?? "NULL")")
        } else {
            NSLog("SETTLEMENT BackendClient: 🔍 fetchWeekStatus called with weekStartDate: NULL (will use auto-detection)")
        }

        let params = WeekStatusParams(p_week_start_date: encodedDate)

        do {
            let builder = try supabase.rpc("rpc_get_week_status", params: params)
            let response: PostgrestResponse<[WeekStatusResponse]> = try await builder.execute()
            guard let first = response.value.first else {
                NSLog("SETTLEMENT BackendClient: ⚠️ rpc_get_week_status returned no rows for \(encodedDate ?? "auto")")
                NSLog("SETTLEMENT BackendClient: 🔍 This means no commitment was found for date: \(encodedDate ?? "auto")")
                throw BackendError.serverError("No week status available yet. Lock in a commitment first.")
            }
            NSLog("SETTLEMENT BackendClient: ✅ Loaded week status for \(encodedDate ?? "auto")")
            NSLog("SETTLEMENT BackendClient: 🔍 Response - limitMinutes: \(first.limitMinutes), penaltyPerMinuteCents: \(first.penaltyPerMinuteCents)")
            return first
        } catch {
            NSLog("SETTLEMENT BackendClient: ❌ Failed to load week status: \(error)")
            throw BackendError.serverError("Failed to load week status: \(error.localizedDescription)")
        }
    }
    
    /// 5. Preview the max charge amount before creating a commitment
    /// Calls: preview-service Edge Function (backend calculates deadline internally)
    /// - Parameters:
    ///   - limitMinutes: User's time limit in minutes
    ///   - penaltyPerMinuteCents: Penalty per minute in cents
    ///   - selectedApps: FamilyActivitySelection containing apps and categories
    /// - Returns: MaxChargePreviewResponse with the calculated amount
    /// Note: Deadline is calculated by backend (single source of truth)
    nonisolated func previewMaxCharge(
        limitMinutes: Int,
        penaltyPerMinuteCents: Int,
        selectedApps: FamilyActivitySelection
    ) async throws -> MaxChargePreviewResponse {
        // Note: This doesn't require authentication - preview is allowed before committing
        // But the actual commitment will require auth
        
        // Extract app and category counts from FamilyActivitySelection
        // Note: We can't extract actual bundle IDs from opaque tokens, but we can count them
        // The backend counts array lengths, so we create arrays with placeholder values
        // to represent the correct count
        let appCount = selectedApps.applicationTokens.count
        let categoryCount = selectedApps.categoryTokens.count
        
        // Create placeholder arrays with the correct counts
        // The backend only uses the array length, not the actual values
        let appBundleIds = Array(repeating: "placeholder", count: appCount)
        let categories = Array(repeating: "placeholder", count: categoryCount)
        
        // Create apps_to_limit structure
        let appsToLimit = AppsToLimit(
            appBundleIds: appBundleIds,
            categories: categories
        )
        
        struct PreviewParams: Encodable, Sendable {
            let limitMinutes: Int
            let penaltyPerMinuteCents: Int
            let appCount: Int
            let appsToLimit: AppsToLimit
        }
        
        let params = PreviewParams(
            limitMinutes: limitMinutes,
            penaltyPerMinuteCents: penaltyPerMinuteCents,
            appCount: appCount + categoryCount,
            appsToLimit: appsToLimit
        )
        
        NSLog("PREVIEW BackendClient: Calling preview-service Edge Function with params: limit=\(limitMinutes)min, penalty=\(penaltyPerMinuteCents)cents, apps=\(appCount), categories=\(categoryCount)")
        
        do {
            // Call Edge Function instead of RPC directly
            // Backend calculates deadline internally (single source of truth)
            let response: MaxChargePreviewResponse = try await supabase.functions.invoke(
                "preview-service",
                options: FunctionInvokeOptions(
                    body: params
                )
            )
            
            NSLog("PREVIEW BackendClient: ✅ Got max charge preview: \(response.maxChargeCents) cents ($\(response.maxChargeDollars))")
            NSLog("PREVIEW BackendClient: Deadline from backend: \(response.deadlineDate)")
            return response
        } catch {
            NSLog("PREVIEW BackendClient: ❌ Failed to preview max charge: \(error)")
            NSLog("PREVIEW BackendClient: Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                NSLog("PREVIEW BackendClient: Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
            }
            throw BackendError.serverError("Failed to preview max charge: \(error.localizedDescription)")
        }
    }
    
    /// Call admin-close-week-now edge function to trigger weekly settlement immediately
    /// Only works for test users (is_test_user = true)
    /// Calls: admin-close-week-now Edge Function
    nonisolated func callAdminCloseWeekNow() async throws -> AdminCloseWeekResponse {
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        do {
            let response: AdminCloseWeekResponse = try await supabase.functions.invoke(
                "admin-close-week-now",
                options: FunctionInvokeOptions(
                    method: .post
                )
            )
            NSLog("ADMIN BackendClient: ✅ Admin close week response: ok=\(response.ok), message=\(response.message)")
            return response
        } catch {
            NSLog("ADMIN BackendClient: ❌ Failed to call admin-close-week-now: \(error)")
            throw BackendError.serverError("Failed to trigger weekly close: \(error.localizedDescription)")
        }
    }

}

// MARK: - Max Charge Preview Response Model

struct MaxChargePreviewResponse: Codable, Sendable {
    let maxChargeCents: Int
    let maxChargeDollars: Double
    let deadlineDate: String
    let limitMinutes: Int
    let penaltyPerMinuteCents: Int
    let appCount: Int
    
    enum CodingKeys: String, CodingKey {
        case maxChargeCents = "max_charge_cents"
        case maxChargeDollars = "max_charge_dollars"
        case deadlineDate = "deadline_date"
        case limitMinutes = "limit_minutes"
        case penaltyPerMinuteCents = "penalty_per_minute_cents"
        case appCount = "app_count"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxChargeCents = try container.decode(Int.self, forKey: .maxChargeCents)
        maxChargeDollars = try container.decode(Double.self, forKey: .maxChargeDollars)
        deadlineDate = try container.decode(String.self, forKey: .deadlineDate)
        limitMinutes = try container.decode(Int.self, forKey: .limitMinutes)
        penaltyPerMinuteCents = try container.decode(Int.self, forKey: .penaltyPerMinuteCents)
        appCount = try container.decode(Int.self, forKey: .appCount)
    }
}

// MARK: - Usage Report Response Model

struct UsageReportResponse: Codable, Sendable {
    let date: String
    let limitMinutes: Int
    let usedMinutes: Int
    let exceededMinutes: Int
    let penaltyCents: Int
    let userWeekTotalCents: Int
    let poolTotalCents: Int
    
    enum CodingKeys: String, CodingKey {
        case date
        case limitMinutes = "limit_minutes"
        case usedMinutes = "used_minutes"
        case exceededMinutes = "exceeded_minutes"
        case penaltyCents = "penalty_cents"
        case userWeekTotalCents = "user_week_total_cents"
        case poolTotalCents = "pool_total_cents"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        limitMinutes = try container.decode(Int.self, forKey: .limitMinutes)
        usedMinutes = try container.decode(Int.self, forKey: .usedMinutes)
        exceededMinutes = try container.decode(Int.self, forKey: .exceededMinutes)
        penaltyCents = try container.decode(Int.self, forKey: .penaltyCents)
        userWeekTotalCents = try container.decode(Int.self, forKey: .userWeekTotalCents)
        poolTotalCents = try container.decode(Int.self, forKey: .poolTotalCents)
    }
}


struct WeekStatusResponse: Codable, Sendable, Equatable {
    let userTotalPenaltyCents: Int
    let userStatus: String
    let userMaxChargeCents: Int
    let poolTotalPenaltyCents: Int
    let poolStatus: String
    let poolInstagramPostUrl: String?
    let poolInstagramImageUrl: String?
    let userSettlementStatus: String
    let chargedAmountCents: Int
    let actualAmountCents: Int
    let refundAmountCents: Int
    let needsReconciliation: Bool
    let reconciliationDeltaCents: Int
    let reconciliationReason: String?
    let reconciliationDetectedAt: String?
    let weekGraceExpiresAt: String?
    let weekEndDate: String?
    let limitMinutes: Int
    let penaltyPerMinuteCents: Int

    enum CodingKeys: String, CodingKey {
        case userTotalPenaltyCents = "user_total_penalty_cents"
        case userStatus = "user_status"
        case userMaxChargeCents = "user_max_charge_cents"
        case poolTotalPenaltyCents = "pool_total_penalty_cents"
        case poolStatus = "pool_status"
        case poolInstagramPostUrl = "pool_instagram_post_url"
        case poolInstagramImageUrl = "pool_instagram_image_url"
        case userSettlementStatus = "user_settlement_status"
        case chargedAmountCents = "charged_amount_cents"
        case actualAmountCents = "actual_amount_cents"
        case refundAmountCents = "refund_amount_cents"
        case needsReconciliation = "needs_reconciliation"
        case reconciliationDeltaCents = "reconciliation_delta_cents"
        case reconciliationReason = "reconciliation_reason"
        case reconciliationDetectedAt = "reconciliation_detected_at"
        case weekGraceExpiresAt = "week_grace_expires_at"
        case weekEndDate = "week_end_date"
        case limitMinutes = "limit_minutes"
        case penaltyPerMinuteCents = "penalty_per_minute_cents"
    }

    nonisolated init(
        userTotalPenaltyCents: Int,
        userStatus: String,
        userMaxChargeCents: Int,
        poolTotalPenaltyCents: Int,
        poolStatus: String,
        poolInstagramPostUrl: String?,
        poolInstagramImageUrl: String?,
        userSettlementStatus: String,
        chargedAmountCents: Int,
        actualAmountCents: Int,
        refundAmountCents: Int,
        needsReconciliation: Bool,
        reconciliationDeltaCents: Int,
        reconciliationReason: String?,
        reconciliationDetectedAt: String?,
        weekGraceExpiresAt: String?,
        weekEndDate: String?,
        limitMinutes: Int,
        penaltyPerMinuteCents: Int
    ) {
        self.userTotalPenaltyCents = userTotalPenaltyCents
        self.userStatus = userStatus
        self.userMaxChargeCents = userMaxChargeCents
        self.poolTotalPenaltyCents = poolTotalPenaltyCents
        self.poolStatus = poolStatus
        self.poolInstagramPostUrl = poolInstagramPostUrl
        self.poolInstagramImageUrl = poolInstagramImageUrl
        self.userSettlementStatus = userSettlementStatus
        self.chargedAmountCents = chargedAmountCents
        self.actualAmountCents = actualAmountCents
        self.refundAmountCents = refundAmountCents
        self.needsReconciliation = needsReconciliation
        self.reconciliationDeltaCents = reconciliationDeltaCents
        self.reconciliationReason = reconciliationReason
        self.reconciliationDetectedAt = reconciliationDetectedAt
        self.weekGraceExpiresAt = weekGraceExpiresAt
        self.weekEndDate = weekEndDate
        self.limitMinutes = limitMinutes
        self.penaltyPerMinuteCents = penaltyPerMinuteCents
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userTotalPenaltyCents = try container.decodeIfPresent(Int.self, forKey: .userTotalPenaltyCents) ?? 0
        userStatus = try container.decodeIfPresent(String.self, forKey: .userStatus) ?? "none"
        userMaxChargeCents = try container.decodeIfPresent(Int.self, forKey: .userMaxChargeCents) ?? 0
        poolTotalPenaltyCents = try container.decodeIfPresent(Int.self, forKey: .poolTotalPenaltyCents) ?? 0
        poolStatus = try container.decodeIfPresent(String.self, forKey: .poolStatus) ?? "open"
        poolInstagramPostUrl = try container.decodeIfPresent(String.self, forKey: .poolInstagramPostUrl)
        poolInstagramImageUrl = try container.decodeIfPresent(String.self, forKey: .poolInstagramImageUrl)
        userSettlementStatus = try container.decodeIfPresent(String.self, forKey: .userSettlementStatus) ?? "pending"
        chargedAmountCents = try container.decodeIfPresent(Int.self, forKey: .chargedAmountCents) ?? 0
        actualAmountCents = try container.decodeIfPresent(Int.self, forKey: .actualAmountCents) ?? 0
        refundAmountCents = try container.decodeIfPresent(Int.self, forKey: .refundAmountCents) ?? 0
        needsReconciliation = try container.decodeIfPresent(Bool.self, forKey: .needsReconciliation) ?? false
        reconciliationDeltaCents = try container.decodeIfPresent(Int.self, forKey: .reconciliationDeltaCents) ?? 0
        reconciliationReason = try container.decodeIfPresent(String.self, forKey: .reconciliationReason)
        reconciliationDetectedAt = try container.decodeIfPresent(String.self, forKey: .reconciliationDetectedAt)
        weekGraceExpiresAt = try container.decodeIfPresent(String.self, forKey: .weekGraceExpiresAt)
        weekEndDate = try container.decodeIfPresent(String.self, forKey: .weekEndDate)
        limitMinutes = try container.decodeIfPresent(Int.self, forKey: .limitMinutes) ?? 0
        penaltyPerMinuteCents = try container.decodeIfPresent(Int.self, forKey: .penaltyPerMinuteCents) ?? 0
    }
    
    nonisolated static func == (lhs: WeekStatusResponse, rhs: WeekStatusResponse) -> Bool {
        return lhs.userTotalPenaltyCents == rhs.userTotalPenaltyCents &&
               lhs.userStatus == rhs.userStatus &&
               lhs.userMaxChargeCents == rhs.userMaxChargeCents &&
               lhs.poolTotalPenaltyCents == rhs.poolTotalPenaltyCents &&
               lhs.poolStatus == rhs.poolStatus &&
               lhs.poolInstagramPostUrl == rhs.poolInstagramPostUrl &&
               lhs.poolInstagramImageUrl == rhs.poolInstagramImageUrl &&
               lhs.userSettlementStatus == rhs.userSettlementStatus &&
               lhs.chargedAmountCents == rhs.chargedAmountCents &&
               lhs.actualAmountCents == rhs.actualAmountCents &&
               lhs.refundAmountCents == rhs.refundAmountCents &&
               lhs.needsReconciliation == rhs.needsReconciliation &&
               lhs.reconciliationDeltaCents == rhs.reconciliationDeltaCents &&
               lhs.reconciliationReason == rhs.reconciliationReason &&
               lhs.reconciliationDetectedAt == rhs.reconciliationDetectedAt &&
               lhs.weekGraceExpiresAt == rhs.weekGraceExpiresAt &&
               lhs.weekEndDate == rhs.weekEndDate &&
               lhs.limitMinutes == rhs.limitMinutes &&
               lhs.penaltyPerMinuteCents == rhs.penaltyPerMinuteCents
    }
}

// MARK: - Admin Close Week Response Model

struct AdminCloseWeekResponse: Codable, Sendable {
    let ok: Bool
    let message: String
    let triggeredBy: String?
    // Note: result field is ignored since we don't need to decode the nested weekly-close response
    
    enum CodingKeys: String, CodingKey {
        case ok
        case message
        case triggeredBy = "triggered_by"
        // result is intentionally omitted - we don't need it
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        message = try container.decode(String.self, forKey: .message)
        triggeredBy = try container.decodeIfPresent(String.self, forKey: .triggeredBy)
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(triggeredBy, forKey: .triggeredBy)
    }
}
