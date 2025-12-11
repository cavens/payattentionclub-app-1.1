import Foundation

// MARK: - Environment

/// App environment - controls which backend and payment keys are used
enum AppEnvironment: String {
    case staging
    case production
    
    var displayName: String {
        switch self {
        case .staging: return "STAGING"
        case .production: return "Production"
        }
    }
}

// MARK: - App Config

/// Central configuration for the app
/// Controls environment switching for Supabase and Stripe
struct AppConfig {
    
    /// Current environment - auto-selected based on build configuration
    /// DEBUG builds use staging, RELEASE builds use production
    static var current: AppEnvironment {
        #if DEBUG
        return .staging
        #else
        return .production
        #endif
    }
    
    /// Override environment manually (useful for testing production in debug builds)
    /// Set this in AppDelegate or early in app launch if needed
    static var overrideEnvironment: AppEnvironment? = nil
    
    /// Resolved environment (uses override if set, otherwise auto-detected)
    static var environment: AppEnvironment {
        return overrideEnvironment ?? current
    }
    
    /// True when running in staging/test mode
    static var isTestMode: Bool {
        return environment == .staging
    }
    
    /// True when running in production
    static var isProduction: Bool {
        return environment == .production
    }
}

// MARK: - Supabase Config

/// Configuration for Supabase backend connection
struct SupabaseConfig {
    
    // MARK: - Staging Environment
    private static let stagingProjectURL = "https://auqujbppoytkeqdsgrbl.supabase.co"
    private static let stagingAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF1cXVqYnBwb3l0a2VxZHNncmJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0NTc4OTYsImV4cCI6MjA4MTAzMzg5Nn0.UXUQ3AXdNLUQ8yB7x_v2oQAzFz9Vj-m07l04n-6flCQ"
    
    // MARK: - Production Environment
    private static let productionProjectURL = "https://whdftvcrtrsnefhprebj.supabase.co"
    private static let productionAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZGZ0dmNydHJzbmVmaHByZWJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMwNDc0NjUsImV4cCI6MjA3ODYyMzQ2NX0.T1Vz087udE-PywR5KfjXqDzORHSIggXw0uCu8zYGIxE"
    
    // MARK: - Active Configuration (environment-aware)
    
    /// Supabase project URL for current environment
    static var projectURL: String {
        switch AppConfig.environment {
        case .staging: return stagingProjectURL
        case .production: return productionProjectURL
        }
    }
    
    /// Supabase anon key for current environment
    static var anonKey: String {
        switch AppConfig.environment {
        case .staging: return stagingAnonKey
        case .production: return productionAnonKey
        }
    }
    
    /// Current environment name (for logging)
    static var environment: String {
        return AppConfig.environment.rawValue
    }
}

// MARK: - Stripe Config

/// Configuration for Stripe payment processing
struct StripeConfig {
    
    // MARK: - Test/Staging Environment
    private static let testPublishableKey = "pk_test_51SPVFLQcfZnqDqya4lgxkORQJQv9RAEeDfyPCs7ETZokdO8fe5k3HI84Gfpb2tpKRig3dcoBSPYVzKMpFXp048g400CCNcLahR"
    
    // MARK: - Production Environment
    // TODO: Replace with live Stripe key when ready for production
    private static let livePublishableKey = "pk_test_51SPVFLQcfZnqDqya4lgxkORQJQv9RAEeDfyPCs7ETZokdO8fe5k3HI84Gfpb2tpKRig3dcoBSPYVzKMpFXp048g400CCNcLahR"  // Still test key - replace with pk_live_ when ready
    
    // MARK: - Active Configuration (environment-aware)
    
    /// Stripe publishable key for current environment
    static var publishableKey: String {
        switch AppConfig.environment {
        case .staging: return testPublishableKey
        case .production: return livePublishableKey
        }
    }
    
    /// Current environment name (for logging)
    static var environment: String {
        return AppConfig.environment == .staging ? "test" : "production"
    }
}

