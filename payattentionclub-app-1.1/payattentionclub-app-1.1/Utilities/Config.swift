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

