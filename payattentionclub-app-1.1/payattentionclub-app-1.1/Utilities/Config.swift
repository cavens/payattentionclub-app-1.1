import Foundation

/// Configuration for Supabase backend connection
struct SupabaseConfig {
    // TODO: Replace with your actual Supabase project URL
    // Format: https://xxxxx.supabase.co
    static let projectURL = "https://whdftvcrtrsnefhprebj.supabase.co"
    
    // TODO: Replace with your actual Supabase anon key
    // This is the public anon key from Supabase Dashboard → Settings → API
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZGZ0dmNydHJzbmVmaHByZWJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMwNDc0NjUsImV4cCI6MjA3ODYyMzQ2NX0.T1Vz087udE-PywR5KfjXqDzORHSIggXw0uCu8zYGIxE"
    
    // Environment detection (for future use)
    #if DEBUG
    static let environment = "staging"
    #else
    static let environment = "production"
    #endif
}

/// Configuration for Stripe payment processing
struct StripeConfig {
    // TODO: Replace with your Stripe publishable key
    // Get this from Stripe Dashboard → Developers → API Keys → Publishable key
    // Test mode key starts with pk_test_, production starts with pk_live_
    static let publishableKey = "pk_test_51SPVFLQcfZnqDqya4lgxkORQJQv9RAEeDfyPCs7ETZokdO8fe5k3HI84Gfpb2tpKRig3dcoBSPYVzKMpFXp048g400CCNcLahR" // Replace with actual key
    
    #if DEBUG
    static let environment = "test"
    #else
    static let environment = "production"
    #endif
}

