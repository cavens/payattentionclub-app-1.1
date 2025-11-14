import Foundation
import Supabase
import Auth

/// Client for interacting with PAC backend (Supabase)
@MainActor
class BackendClient {
    static let shared = BackendClient()
    
    private let supabase: SupabaseClient
    
    private init() {
        // Initialize Supabase client
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectURL)!,
            supabaseKey: SupabaseConfig.anonKey
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
    
    // MARK: - API Methods
    
    /// 1. Check billing status and create SetupIntent if needed
    /// Calls: billing-status Edge Function
    func checkBillingStatus() async throws -> BillingStatusResponse {
        struct EmptyBody: Encodable {}
        
        let response = try await supabase.functions.invoke(
            "billing-status",
            options: FunctionInvokeOptions(
                body: EmptyBody()
            )
        )
        
        let data = response.data
        return try JSONDecoder().decode(BillingStatusResponse.self, from: data)
    }
    
    /// 2. Create a weekly commitment
    /// Calls: rpc_create_commitment
    func createCommitment(
        weekStartDate: Date,
        limitMinutes: Int,
        penaltyPerMinuteCents: Int,
        appsToLimit: AppsToLimit
    ) async throws -> CommitmentResponse {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekStartString = dateFormatter.string(from: weekStartDate)
        
        struct CreateCommitmentParams: Encodable {
            let weekStartDate: String
            let limitMinutes: Int
            let penaltyPerMinuteCents: Int
            let appsToLimit: AppsToLimit
            
            enum CodingKeys: String, CodingKey {
                case weekStartDate = "week_start_date"
                case limitMinutes = "limit_minutes"
                case penaltyPerMinuteCents = "penalty_per_minute_cents"
                case appsToLimit = "apps_to_limit"
            }
        }
        
        let params = CreateCommitmentParams(
            weekStartDate: weekStartString,
            limitMinutes: limitMinutes,
            penaltyPerMinuteCents: penaltyPerMinuteCents,
            appsToLimit: appsToLimit
        )
        
        let response = try await supabase.rpc("create_commitment", params: params).execute()
        let data = response.data
        return try JSONDecoder().decode(CommitmentResponse.self, from: data)
    }
    
    /// 3. Report daily usage
    /// Calls: rpc_report_usage
    func reportUsage(
        date: Date,
        weekStartDate: Date,
        usedMinutes: Int
    ) async throws -> UsageReportResponse {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let weekStartString = dateFormatter.string(from: weekStartDate)
        
        struct ReportUsageParams: Encodable {
            let date: String
            let weekStartDate: String
            let usedMinutes: Int
            
            enum CodingKeys: String, CodingKey {
                case date
                case weekStartDate = "week_start_date"
                case usedMinutes = "used_minutes"
            }
        }
        
        let params = ReportUsageParams(
            date: dateString,
            weekStartDate: weekStartString,
            usedMinutes: usedMinutes
        )
        
        let response = try await supabase.rpc("report_usage", params: params).execute()
        let data = response.data
        return try JSONDecoder().decode(UsageReportResponse.self, from: data)
    }
    
    /// 4. Update monitoring status
    /// Calls: rpc_update_monitoring_status
    func updateMonitoringStatus(
        commitmentId: String,
        monitoringStatus: MonitoringStatus
    ) async throws {
        struct UpdateMonitoringStatusParams: Encodable {
            let commitmentId: String
            let monitoringStatus: String
            
            enum CodingKeys: String, CodingKey {
                case commitmentId = "commitment_id"
                case monitoringStatus = "monitoring_status"
            }
        }
        
        let params = UpdateMonitoringStatusParams(
            commitmentId: commitmentId,
            monitoringStatus: monitoringStatus.rawValue
        )
        
        _ = try await supabase.rpc("update_monitoring_status", params: params).execute()
    }
    
    /// 5. Get weekly status for bulletin
    /// Calls: rpc_get_week_status
    func getWeekStatus(weekStartDate: Date) async throws -> WeekStatusResponse {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekStartString = dateFormatter.string(from: weekStartDate)
        
        struct GetWeekStatusParams: Encodable {
            let weekStartDate: String
            
            enum CodingKeys: String, CodingKey {
                case weekStartDate = "week_start_date"
            }
        }
        
        let params = GetWeekStatusParams(weekStartDate: weekStartString)
        
        let response = try await supabase.rpc("get_week_status", params: params).execute()
        let data = response.data
        return try JSONDecoder().decode(WeekStatusResponse.self, from: data)
    }
    
    /// Dev-only: Close week now (admin function)
    func adminCloseWeekNow() async throws {
        struct EmptyBody: Encodable {}
        
        let response = try await supabase.functions.invoke(
            "admin-close-week-now",
            options: FunctionInvokeOptions(
                body: EmptyBody()
            )
        )
        
        // Just verify it succeeded (200 OK)
        guard (200...299).contains(response.status) else {
            throw BackendError.serverError("Failed to close week: HTTP \(response.status)")
        }
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
}

struct CommitmentResponse: Codable {
    let commitmentId: String
    let weekStartDate: String
    let weekEndDate: String
    let status: String
    let maxChargeCents: Int
    
    enum CodingKeys: String, CodingKey {
        case commitmentId = "commitment_id"
        case weekStartDate = "week_start_date"
        case weekEndDate = "week_end_date"
        case status
        case maxChargeCents = "max_charge_cents"
    }
}

struct UsageReportResponse: Codable {
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
}

struct WeekStatusResponse: Codable {
    let weekStartDate: String
    let weekEndDate: String
    let user: UserWeekStatus
    let pool: PoolStatus
    
    enum CodingKeys: String, CodingKey {
        case weekStartDate = "weekStartDate"
        case weekEndDate = "weekEndDate"
        case user
        case pool
    }
}

struct UserWeekStatus: Codable {
    let totalPenaltyCents: Int
    let status: String
    let maxChargeCents: Int
    
    enum CodingKeys: String, CodingKey {
        case totalPenaltyCents = "totalPenaltyCents"
        case status
        case maxChargeCents = "maxChargeCents"
    }
}

struct PoolStatus: Codable {
    let totalPenaltyCents: Int
    let status: String
    let instagramPostUrl: String?
    let instagramImageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case totalPenaltyCents = "totalPenaltyCents"
        case status
        case instagramPostUrl = "instagramPostUrl"
        case instagramImageUrl = "instagramImageUrl"
    }
}

// MARK: - Helper Models

struct AppsToLimit: Codable {
    let appBundleIds: [String]
    let categories: [String]
    
    enum CodingKeys: String, CodingKey {
        case appBundleIds = "appBundleIds"
        case categories
    }
}

enum MonitoringStatus: String, Codable {
    case ok = "ok"
    case revoked = "revoked"
    case notGranted = "not_granted"
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
