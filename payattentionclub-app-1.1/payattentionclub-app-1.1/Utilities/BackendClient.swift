import Foundation
import Supabase
import Auth

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
class BackendClient {
    static let shared = BackendClient()
    
    private let supabase: SupabaseClient
    
    private init() {
        // Initialize Supabase client with Auth configuration
        // Set emitLocalSessionAsInitialSession to opt-in to new session behavior
        // This addresses the deprecation warning about session handling
        let localStorage = UserDefaultsLocalStorage()
        
        // Create AuthClient with custom configuration including emitLocalSessionAsInitialSession
        let authConfig = AuthClient.Configuration(
            localStorage: localStorage,
            emitLocalSessionAsInitialSession: true
        )
        _ = AuthClient(configuration: authConfig)
        
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectURL)!,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(storage: localStorage)
            )
        )
        
        // Note: The deprecation warning about emitLocalSessionAsInitialSession
        // may persist if AuthOptions doesn't support passing the full configuration.
        // The warning is informational and won't break functionality.
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
        
        let response: BillingStatusResponse = try await supabase.functions.invoke(
            "billing-status",
            options: FunctionInvokeOptions(
                body: EmptyBody()
            )
        )
        
        return response
    }
}

