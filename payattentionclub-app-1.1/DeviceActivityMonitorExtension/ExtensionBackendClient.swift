import Foundation

/// Lightweight backend client for DeviceActivityMonitorExtension
/// Cannot use Supabase SDK (too heavy, requires main app context)
/// Makes direct HTTP requests to Supabase REST API
@available(iOS 16.0, *)
class ExtensionBackendClient {
    static let shared = ExtensionBackendClient()
    
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    private let supabaseURL = "https://whdftvcrtrsnefhprebj.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZGZ0dmNydHJzbmVmaHByZWJqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMwNDc0NjUsImV4cCI6MjA3ODYyMzQ2NX0.T1Vz087udE-PywR5KfjXqDzORHSIggXw0uCu8zYGIxE"
    
    private init() {}
    
    /// Report usage to backend
    /// Called from extension when thresholds are hit
    /// - Parameters:
    ///   - date: The date for this usage report (typically today)
    ///   - weekStartDate: The week start date (deadline) for the commitment
    ///   - usedMinutes: Total minutes used today (consumed - baseline)
    func reportUsage(
        date: Date,
        weekStartDate: Date,
        usedMinutes: Int
    ) async {
        // 1. Get commitment ID from App Group
        guard let commitmentId = getCommitmentId() else {
            NSLog("EXTENSION ExtensionBackendClient: ❌ No commitment ID found")
            return
        }
        
        // 2. Get auth token from App Group
        guard let accessToken = getAccessToken() else {
            NSLog("EXTENSION ExtensionBackendClient: ❌ No access token found")
            return
        }
        
        // 3. Format dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        let dateString = dateFormatter.string(from: date)
        let weekStartDateString = dateFormatter.string(from: weekStartDate)
        
        NSLog("EXTENSION ExtensionBackendClient: 📤 Reporting usage - date: \(dateString), weekStartDate: \(weekStartDateString), usedMinutes: \(usedMinutes), commitmentId: \(commitmentId)")
        
        // 4. Build RPC request
        let urlString = "\(supabaseURL)/rest/v1/rpc/rpc_report_usage"
        NSLog("EXTENSION ExtensionBackendClient: 🔗 Request URL: \(urlString)")
        fflush(stdout)
        
        guard let url = URL(string: urlString) else {
            NSLog("EXTENSION ExtensionBackendClient: ❌ Invalid URL: \(urlString)")
            fflush(stdout)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=representation", forHTTPHeaderField: "prefer")
        request.timeoutInterval = 10.0
        
        NSLog("EXTENSION ExtensionBackendClient: 📋 Headers - Content-Type: application/json, Accept: application/json, prefer: return=representation")
        NSLog("EXTENSION ExtensionBackendClient: 🔑 Auth token length: \(accessToken.count) chars, prefix: \(accessToken.prefix(20))...")
        fflush(stdout)
        
        let body: [String: Any] = [
            "p_date": dateString,
            "p_week_start_date": weekStartDateString,
            "p_used_minutes": usedMinutes
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                NSLog("EXTENSION ExtensionBackendClient: 📦 Request body: \(bodyString)")
            }
            NSLog("EXTENSION ExtensionBackendClient: 📦 Request body size: \(request.httpBody?.count ?? 0) bytes")
            fflush(stdout)
        } catch {
            NSLog("EXTENSION ExtensionBackendClient: ❌ Failed to encode request body: \(error)")
            fflush(stdout)
            return
        }
        
        // 5. Make request
        let requestStartTime = Date().timeIntervalSince1970
        NSLog("EXTENSION ExtensionBackendClient: ⏱️ Starting request at \(requestStartTime)")
        fflush(stdout)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let requestDuration = Date().timeIntervalSince1970 - requestStartTime
            NSLog("EXTENSION ExtensionBackendClient: ⏱️ Request completed in \(requestDuration)s")
            fflush(stdout)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    NSLog("EXTENSION ExtensionBackendClient: ✅ Successfully reported usage - \(usedMinutes) min for date \(dateString)")
                    
                    // Log response data for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        NSLog("EXTENSION ExtensionBackendClient: Response: \(responseString.prefix(200))")
                    }
                } else {
                    let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                    NSLog("EXTENSION ExtensionBackendClient: ❌ Failed to report usage - Status: \(httpResponse.statusCode), Error: \(errorString)")
                }
            }
        } catch {
            let requestDuration = Date().timeIntervalSince1970 - requestStartTime
            NSLog("EXTENSION ExtensionBackendClient: ⏱️ Request failed after \(requestDuration)s")
            NSLog("EXTENSION ExtensionBackendClient: ❌ Network error reporting usage: \(error.localizedDescription)")
            NSLog("EXTENSION ExtensionBackendClient: ❌ Error type: \(type(of: error))")
            
            if let urlError = error as? URLError {
                NSLog("EXTENSION ExtensionBackendClient: URLError code: \(urlError.code.rawValue)")
                NSLog("EXTENSION ExtensionBackendClient: URLError description: \(urlError.localizedDescription)")
            }
            
            // Log NSError details if available
            let nsError = error as NSError
            NSLog("EXTENSION ExtensionBackendClient: NSError domain: \(nsError.domain)")
            NSLog("EXTENSION ExtensionBackendClient: NSError code: \(nsError.code)")
            NSLog("EXTENSION ExtensionBackendClient: NSError userInfo: \(nsError.userInfo)")
            if let failureReason = nsError.localizedFailureReason {
                NSLog("EXTENSION ExtensionBackendClient: NSError failure reason: \(failureReason)")
            }
            if let recoverySuggestion = nsError.localizedRecoverySuggestion {
                NSLog("EXTENSION ExtensionBackendClient: NSError recovery suggestion: \(recoverySuggestion)")
            }
            fflush(stdout)
        }
    }
    
    // MARK: - App Group Helpers
    
    /// Get commitment ID from App Group
    private func getCommitmentId() -> String? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return userDefaults.string(forKey: "commitmentId")
    }
    
    /// Get access token from App Group
    private func getAccessToken() -> String? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return userDefaults.string(forKey: "supabaseAccessToken")
    }
    
    /// Get baseline time from App Group (in seconds)
    /// Used to calculate usedMinutes = consumedMinutes - baselineMinutes
    private func getBaselineTime() -> TimeInterval {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return 0.0
        }
        return userDefaults.double(forKey: "baselineTimeSpent")
    }
}

