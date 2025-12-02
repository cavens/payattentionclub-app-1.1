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
    /// The deadline date (next Monday before noon) - when the commitment ends
    /// Note: The commitment actually starts when the user commits (current_date in backend)
    let weekStartDate: String  // Kept as weekStartDate to match Edge Function API
    let limitMinutes: Int
    let penaltyPerMinuteCents: Int
    let appsToLimit: AppsToLimit
    
    // Explicitly implement encoding to ensure nonisolated conformance
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekStartDate, forKey: .weekStartDate)
        try container.encode(limitMinutes, forKey: .limitMinutes)
        try container.encode(penaltyPerMinuteCents, forKey: .penaltyPerMinuteCents)
        try container.encode(appsToLimit, forKey: .appsToLimit)
    }
    
    enum CodingKeys: String, CodingKey {
        case weekStartDate
        case limitMinutes
        case penaltyPerMinuteCents
        case appsToLimit
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

struct SyncDailyUsageResponse: Codable, Sendable {
    let syncedCount: Int?
    let failedCount: Int?
    let syncedDates: [String]?
    let failedDates: [String]?
    let errors: [String]?
    let processedWeeks: [String]?
    
    enum CodingKeys: String, CodingKey {
        case syncedCount = "synced_count"
        case failedCount = "failed_count"
        case syncedDates = "synced_dates"
        case failedDates = "failed_dates"
        case errors
        case processedWeeks = "processed_weeks"
    }
}

// MARK: - Response Models

struct BillingStatusResponse: Codable {
    let hasPaymentMethod: Bool
    let needsSetupIntent: Bool
    let setupIntentClientSecret: String?
    let stripeCustomerId: String?
    
    enum CodingKeys: String, CodingKey {
        case hasPaymentMethod = "has_payment_method"
        case needsSetupIntent = "needs_setup_intent"
        case setupIntentClientSecret = "setup_intent_client_secret"
        case stripeCustomerId = "stripe_customer_id"
    }
    
    // Custom decoder to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode fields, use defaults if missing
        hasPaymentMethod = try container.decodeIfPresent(Bool.self, forKey: .hasPaymentMethod) ?? false
        needsSetupIntent = try container.decodeIfPresent(Bool.self, forKey: .needsSetupIntent) ?? false
        setupIntentClientSecret = try container.decodeIfPresent(String.self, forKey: .setupIntentClientSecret)
        stripeCustomerId = try container.decodeIfPresent(String.self, forKey: .stripeCustomerId)
    }
}

struct ConfirmSetupIntentResponse: Codable, Sendable {
    let success: Bool
    let setupIntentId: String?
    let paymentMethodId: String?
    let alreadyConfirmed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case success
        case setupIntentId
        case paymentMethodId
        case alreadyConfirmed
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        setupIntentId = try container.decodeIfPresent(String.self, forKey: .setupIntentId)
        paymentMethodId = try container.decodeIfPresent(String.self, forKey: .paymentMethodId)
        alreadyConfirmed = try container.decodeIfPresent(Bool.self, forKey: .alreadyConfirmed)
    }
}

struct CommitmentResponse: Codable, Sendable {
    let commitmentId: String
    /// The date when the commitment actually started (when user committed)
    /// Maps to `week_start_date` column in database (legacy naming)
    let startDate: String
    /// The deadline when the commitment ends (next Monday before noon)
    /// Maps to `week_end_date` column in database (legacy naming)
    let deadlineDate: String
    let status: String
    let maxChargeCents: Int
    
    enum CodingKeys: String, CodingKey {
        case commitmentId = "id"  // RPC function returns 'id' from commitments table
        case startDate = "week_start_date"  // Database column name (legacy)
        case deadlineDate = "week_end_date"  // Database column name (legacy)
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
            supabaseKey: SupabaseConfig.anonKey,
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
    /// - Returns: The authenticated session
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        return session
    }
    
    /// Sign out the current user
    func signOut() async throws {
        try await supabase.auth.signOut()
    }
    
    // MARK: - API Methods
    
    /// 1. Check billing status and create SetupIntent if needed
    /// Calls: billing-status Edge Function
    /// - Throws: BackendError.notAuthenticated if user is not signed in
    func checkBillingStatus() async throws -> BillingStatusResponse {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        NSLog("BILLING BackendClient: Calling billing-status Edge Function...")
        
        do {
            // Note: supabase.functions.invoke() directly decodes, so we can't easily see raw JSON
            // But the custom decoder will handle missing fields gracefully
            let response: BillingStatusResponse = try await supabase.functions.invoke(
                "billing-status",
                options: FunctionInvokeOptions(
                    body: EmptyBody()
                )
            )
            
            NSLog("BILLING BackendClient: ✅ Successfully decoded BillingStatusResponse")
            NSLog("BILLING BackendClient: hasPaymentMethod: \(response.hasPaymentMethod) (may be default false if missing)")
            NSLog("BILLING BackendClient: needsSetupIntent: \(response.needsSetupIntent) (may be default false if missing)")
            NSLog("BILLING BackendClient: setupIntentClientSecret: \(response.setupIntentClientSecret ?? "nil")")
            NSLog("BILLING BackendClient: stripeCustomerId: \(response.stripeCustomerId ?? "nil")")
            
            return response
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
    
    /// 1.5. Confirm SetupIntent with Apple Pay PaymentMethod
    /// Calls: rapid-service Edge Function (Supabase auto-renamed from confirm-setup-intent)
    /// - Parameters:
    ///   - clientSecret: The SetupIntent client secret
    ///   - paymentMethodId: Stripe PaymentMethod ID (created from Apple Pay token)
    /// - Returns: `true` if confirmation successful
    /// - Throws: BackendError if confirmation fails
    nonisolated func confirmSetupIntentWithApplePay(
        clientSecret: String,
        paymentMethodId: String
    ) async throws -> Bool {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        NSLog("APPLEPAY BackendClient: Confirming SetupIntent with PaymentMethod ID: \(paymentMethodId)")
        
        struct ConfirmSetupIntentBody: Encodable, Sendable {
            let clientSecret: String
            let paymentMethodId: String
        }
        
        let requestBody = ConfirmSetupIntentBody(
            clientSecret: clientSecret,
            paymentMethodId: paymentMethodId
        )
        
        return try await Task.detached(priority: .userInitiated) { [supabase] in
            do {
                // Call Edge Function to confirm SetupIntent
                // Note: Function name is "rapid-service" (Supabase auto-renamed it)
                let response: ConfirmSetupIntentResponse = try await supabase.functions.invoke(
                    "rapid-service",
                    options: FunctionInvokeOptions(
                        body: requestBody
                    )
                )
                
                NSLog("APPLEPAY BackendClient: ✅ SetupIntent confirmation result: \(response.success)")
                return response.success
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
    ///   - weekStartDate: The deadline date (next Monday before noon) when the commitment ends
    ///                    Note: The commitment actually starts NOW (when user commits), not on this date
    ///   - limitMinutes: Daily time limit in minutes
    ///   - penaltyPerMinuteCents: Penalty per minute in cents (e.g., 10 = $0.10)
    ///   - selectedApps: FamilyActivitySelection containing apps and categories to limit
    /// - Returns: CommitmentResponse with commitment details
    /// - Throws: BackendError.notAuthenticated if user is not signed in
    nonisolated func createCommitment(
        weekStartDate: Date,  // Actually the deadline, not the start date
        limitMinutes: Int,
        penaltyPerMinuteCents: Int,
        selectedApps: FamilyActivitySelection
    ) async throws -> CommitmentResponse {
        // Check authentication first
        guard await isAuthenticated else {
            throw BackendError.notAuthenticated
        }
        
        // Format date as ISO string (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York") // EST
        let weekStartDateString = dateFormatter.string(from: weekStartDate)
        
        // Call Edge Function instead of RPC to avoid Supabase SDK auto-decoding issues
        // The Edge Function calls the RPC function and returns JSON properly
        let task = Task.detached(priority: .userInitiated) { [supabase, weekStartDateString, limitMinutes, penaltyPerMinuteCents] in
            // Create AppsToLimit inside detached task (nonisolated)
            // Backend expects apps_to_limit as JSONB object with app_bundle_ids and categories arrays
            let appsToLimit = AppsToLimit(
                appBundleIds: [], // Cannot extract bundle IDs from opaque tokens
                categories: []    // Cannot extract category identifiers from opaque tokens
            )
            
            // Create request body for Edge Function
            let requestBody = CreateCommitmentEdgeFunctionBody(
                weekStartDate: weekStartDateString,
                limitMinutes: limitMinutes,
                penaltyPerMinuteCents: penaltyPerMinuteCents,
                appsToLimit: appsToLimit
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

