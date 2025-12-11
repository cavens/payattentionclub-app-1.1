# DeviceActivityMonitorExtension Network Reporting Implementation Plan

## ✅ NETWORK ACCESS CONFIRMED

**Confidence Level: HIGH** - Network test completed successfully! ✅

**Test Results (Step 0):**
- ✅ GET request: Status 200 - SUCCESS
- ✅ POST request: Status 200 - SUCCESS  
- ✅ Extension CAN make HTTP requests
- ✅ Network entitlement (`com.apple.security.network.client`) is working

**What we know:**
- DeviceActivityMonitorExtension runs independently of the main app ✅
- iOS calls it when thresholds are reached (every 1-5 minutes) ✅
- Extensions CAN make HTTP requests using URLSession ✅
- Network access is confirmed and working ✅

**Status:** Ready to proceed with full implementation (Steps 1-8)

## Overview
Enable `DeviceActivityMonitorExtension` to automatically report usage to the backend when thresholds are hit, even when the main app is force-quit. This ensures usage data is always reported to the backend for accurate weekly settlements.

## Why This Might Work
- `DeviceActivityMonitorExtension` runs independently of the main app
- iOS calls it when thresholds are reached (every 1-5 minutes)
- Extensions CAN make HTTP requests using `URLSession` IF properly entitled
- This would solve the problem of missing usage data when users never reopen the app

## Fallback Plan (If Network Access is Blocked)
If testing reveals that DeviceActivityMonitorExtension cannot make network calls:
1. Update `weekly-close` Edge Function to estimate usage for ALL commitments with missing `daily_usage` records (not just revoked ones)
2. Use conservative estimation: assume user used their full limit (worst case for penalty calculation)
3. This ensures weekly settlements can proceed even without usage data

---

## Implementation Steps

### Step 0: TEST NETWORK ACCESS FIRST ✅ COMPLETE

**Before implementing the full solution, test if the extension can make network calls.**

**File:** `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`

**Add test method:**
```swift
private func testNetworkAccess() {
    Task {
        let testURL = URL(string: "https://httpbin.org/get")!
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                NSLog("EXTENSION NetworkTest: ✅ SUCCESS - Status: \(httpResponse.statusCode)")
                NSLog("EXTENSION NetworkTest: Response: \(String(data: data, encoding: .utf8) ?? "nil")")
            }
        } catch {
            NSLog("EXTENSION NetworkTest: ❌ FAILED - Error: \(error)")
            NSLog("EXTENSION NetworkTest: This extension CANNOT make network calls")
        }
    }
}
```

**Call this in `intervalDidStart()`:**
```swift
override func intervalDidStart(for activity: DeviceActivityName) {
    // ... existing code ...
    
    // TEST: Try network access
    testNetworkAccess()
}
```

**If test fails:**
1. Add network entitlement to `DeviceActivityMonitorExtension.entitlements`:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

2. Re-test
3. If still fails, proceed with Fallback Plan (backend estimation)

**If test succeeds:** Proceed with full implementation below.

---

### Step 1: Add Commitment ID Storage to UsageTracker ✅
**File:** `Utilities/UsageTracker.swift`

**Add methods:**
```swift
// MARK: - Commitment ID Storage

/// Store commitment ID when commitment is created
func storeCommitmentId(_ id: String) {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        return
    }
    userDefaults.set(id, forKey: "commitmentId")
    userDefaults.synchronize()
}

/// Get commitment ID
/// nonisolated: UserDefaults reads are thread-safe
nonisolated func getCommitmentId() -> String? {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        return nil
    }
    return userDefaults.string(forKey: "commitmentId")
}

/// Clear commitment ID when monitoring ends
func clearCommitmentId() {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
        return
    }
    userDefaults.removeObject(forKey: "commitmentId")
    userDefaults.synchronize()
}
```

**Update `clearExpiredMonitoringState()` to also clear commitment ID:**
```swift
func clearExpiredMonitoringState() {
    // ... existing code ...
    userDefaults.removeObject(forKey: "commitmentId")
    userDefaults.synchronize()
}
```

---

### Step 2: Store Commitment ID When Created ✅
**File:** `Views/AuthorizationView.swift`

**After commitment is created (around line 230):**
```swift
// Store commitment ID in App Group for extension to use
UsageTracker.shared.storeCommitmentId(commitmentResponse.commitmentId)
```

---

### Step 3: Store Auth Token in App Group ✅
**File:** `Utilities/BackendClient.swift`

**Add method to store auth token:**
```swift
/// Store current auth token in App Group for extension to use
func storeAuthTokenInAppGroup() async {
    do {
        let session = try await supabase.auth.session
        guard let accessToken = session?.accessToken else {
            NSLog("EXTENSION BackendClient: No access token to store")
            return
        }
        
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
            NSLog("EXTENSION BackendClient: Failed to access App Group")
            return
        }
        
        userDefaults.set(accessToken, forKey: "supabaseAccessToken")
        userDefaults.set(Date().timeIntervalSince1970, forKey: "supabaseAccessTokenTimestamp")
        userDefaults.synchronize()
        
        NSLog("EXTENSION BackendClient: ✅ Stored auth token in App Group")
    } catch {
        NSLog("EXTENSION BackendClient: ❌ Failed to store auth token: \(error)")
    }
}
```

**Call this after successful authentication:**
- In `signInWithApple()` after successful sign-in
- In `checkBillingStatus()` after session refresh
- After any operation that refreshes the session

---

### Step 4: Create Extension Network Client ✅
**File:** `DeviceActivityMonitorExtension/ExtensionBackendClient.swift` (NEW FILE)

**Purpose:** Lightweight HTTP client for the extension to call Supabase RPC functions

```swift
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
        
        // 4. Build RPC request
        let url = URL(string: "\(supabaseURL)/rest/v1/rpc/rpc_report_usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("prefer", forHTTPHeaderField: "return=representation")
        
        let body: [String: Any] = [
            "p_date": dateString,
            "p_week_start_date": weekStartDateString,
            "p_used_minutes": usedMinutes
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            NSLog("EXTENSION ExtensionBackendClient: ❌ Failed to encode request body: \(error)")
            return
        }
        
        // 5. Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    NSLog("EXTENSION ExtensionBackendClient: ✅ Successfully reported usage - \(usedMinutes) min")
                } else {
                    let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                    NSLog("EXTENSION ExtensionBackendClient: ❌ Failed to report usage - Status: \(httpResponse.statusCode), Error: \(errorString)")
                }
            }
        } catch {
            NSLog("EXTENSION ExtensionBackendClient: ❌ Network error reporting usage: \(error)")
        }
    }
    
    // MARK: - App Group Helpers
    
    private func getCommitmentId() -> String? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return userDefaults.string(forKey: "commitmentId")
    }
    
    private func getAccessToken() -> String? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return userDefaults.string(forKey: "supabaseAccessToken")
    }
}
```

---

### Step 5: Add Rate Limiting to Prevent Duplicate Reports ✅
**File:** `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`

**Add property to track last report time:**
```swift
private var lastReportTimestamp: TimeInterval = 0
private let minReportInterval: TimeInterval = 300 // 5 minutes minimum between reports
```

**Add method to check if we should report:**
```swift
private func shouldReportUsage() -> Bool {
    let now = Date().timeIntervalSince1970
    let timeSinceLastReport = now - lastReportTimestamp
    
    // Only report if at least 5 minutes have passed since last report
    // This prevents duplicate reports when multiple thresholds fire quickly
    return timeSinceLastReport >= minReportInterval
}
```

---

### Step 6: Integrate Reporting into Threshold Handler ✅
**File:** `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`

**Update `eventDidReachThreshold()`:**
```swift
override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    super.eventDidReachThreshold(event, activity: activity)
    
    // ... existing code to extract seconds and store in App Group ...
    
    // NEW: Report usage to backend (with rate limiting)
    if shouldReportUsage() {
        Task {
            await reportUsageToBackend(consumedMinutes: consumedMinutes)
        }
    }
}
```

**Add reporting method:**
```swift
private func reportUsageToBackend(consumedMinutes: Double) async {
    // Get deadline from App Group
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
          let deadlineTimestamp = userDefaults.object(forKey: "commitmentDeadline") as? TimeInterval else {
        NSLog("EXTENSION MonitorExtension: ❌ No deadline found, skipping report")
        return
    }
    
    // Get baseline from App Group (stored when commitment is created)
    let baselineMinutes = userDefaults.double(forKey: "baselineTimeSpent") / 60.0
    
    // Calculate used minutes (consumed - baseline)
    // Note: Currently baseline is always 0, but this ensures consistency if baseline logic changes
    let usedMinutes = max(0, Int(consumedMinutes - baselineMinutes))
    
    let deadline = Date(timeIntervalSince1970: deadlineTimestamp)
    let today = Date()
    
    // Report to backend
    await ExtensionBackendClient.shared.reportUsage(
        date: today,
        weekStartDate: deadline,
        usedMinutes: usedMinutes
    )
    
    // Update last report timestamp
    lastReportTimestamp = Date().timeIntervalSince1970
}
```

---

### Step 7: Handle Token Refresh (Optional Enhancement) ✅
**File:** `DeviceActivityMonitorExtension/ExtensionBackendClient.swift`

**Add method to refresh token if expired:**
```swift
private func isTokenExpired() -> Bool {
    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
          let timestamp = userDefaults.object(forKey: "supabaseAccessTokenTimestamp") as? TimeInterval else {
        return true
    }
    
    // Tokens typically expire after 1 hour
    // Check if token is older than 50 minutes (refresh before expiry)
    let tokenAge = Date().timeIntervalSince1970 - timestamp
    return tokenAge > 3000 // 50 minutes
}

/// Refresh token by calling Supabase auth endpoint
/// Note: This requires the refresh token, which we should also store
private func refreshToken() async -> String? {
    // TODO: Implement token refresh if needed
    // For now, extension will fail gracefully if token expires
    // Main app will refresh token when it opens
    return nil
}
```

**For now, we'll skip token refresh in extension** - if token expires, reports will fail silently. The main app will refresh the token when it opens, and catch-up reporting will handle any missed periods.

---

### Step 8: Add Error Handling & Logging ✅
**File:** `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`

**Enhance logging:**
```swift
NSLog("EXTENSION MonitorExtension: 🔔 Threshold: %@ (%d seconds = %.1f minutes)", 
      event.rawValue, seconds, consumedMinutes)
NSLog("EXTENSION MonitorExtension: ✅ Stored: consumedMinutes=%.1f, seconds=%d, timestamp=%.0f", 
      consumedMinutes, seconds, timestamp)

if shouldReportUsage() {
    NSLog("EXTENSION MonitorExtension: 📤 Reporting usage to backend...")
    Task {
        await reportUsageToBackend(consumedMinutes: consumedMinutes)
    }
} else {
    let timeUntilNextReport = minReportInterval - (Date().timeIntervalSince1970 - lastReportTimestamp)
    NSLog("EXTENSION MonitorExtension: ⏸️ Skipping report (rate limited, next report in %.0f seconds)", timeUntilNextReport)
}
```

---

## Testing Plan

### Test 1: Basic Reporting
1. Create a commitment
2. Verify commitment ID is stored in App Group
3. Verify auth token is stored in App Group
4. Trigger threshold event
5. Check logs for successful report
6. Verify data appears in `daily_usage` table

### Test 2: Rate Limiting
1. Trigger multiple thresholds quickly (< 5 minutes apart)
2. Verify only one report is sent
3. Wait 5+ minutes, trigger another threshold
4. Verify second report is sent

### Test 3: App Force-Quit
1. Create commitment
2. Force-quit app
3. Use device normally (trigger thresholds)
4. Check logs from extension (via Console.app)
5. Verify reports are still sent
6. Verify data appears in backend

### Test 4: Token Expiry
1. Wait for token to expire (or manually expire it)
2. Trigger threshold
3. Verify extension logs show token error
4. Open main app (should refresh token)
5. Trigger threshold again
6. Verify report succeeds

### Test 5: Missing Data Handling
1. Clear commitment ID from App Group
2. Trigger threshold
3. Verify extension logs show "No commitment ID" error
4. Verify no crash occurs

---

## Edge Cases & Considerations

### 1. Token Expiry
- **Problem:** Access tokens expire after ~1 hour
- **Solution:** Extension fails gracefully, main app refreshes token on open
- **Future:** Could store refresh token and implement token refresh in extension

### 2. Network Failures
- **Problem:** Extension might not have network when threshold fires
- **Solution:** Extension logs error but doesn't crash. Main app can catch up when it opens.

### 3. Duplicate Reports
- **Problem:** Multiple thresholds might fire quickly
- **Solution:** Rate limiting (5-minute minimum between reports)

### 4. Missing Commitment ID
- **Problem:** Commitment ID might not be stored
- **Solution:** Extension checks for ID and logs error if missing, doesn't crash

### 5. Date Calculation
- **Problem:** Extension needs to know "today" and "week start date"
- **Solution:** Use deadline stored in App Group, calculate today's date

### 6. Used Minutes Calculation
- **Problem:** Extension only knows consumed minutes, not baseline
- **Current State:** Baseline is always 0 (set in AuthorizationView), so `consumedMinutes` from extension matches `usedMinutes` reported by main app
- **Solution:** 
  - Store baseline in App Group (already done via `storeBaselineTime()`)
  - Extension reads baseline from App Group
  - Extension calculates: `usedMinutes = consumedMinutes - baselineMinutes`
  - This ensures consistency even if baseline logic changes in future

---

## Files to Create/Modify

### New Files:
1. `DeviceActivityMonitorExtension/ExtensionBackendClient.swift` - Network client for extension

### Modified Files:
1. `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements` - Add network entitlement (if needed)
2. `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` - Add network test + reporting logic
3. `Utilities/UsageTracker.swift` - Add commitment ID storage methods
4. `Views/AuthorizationView.swift` - Store commitment ID after creation
5. `Utilities/BackendClient.swift` - Add method to store auth token in App Group

---

## Implementation Order

1. ⚠️ **Step 0: TEST NETWORK ACCESS FIRST** - Critical! Verify extension can make HTTP requests
2. ✅ Step 1: Add commitment ID storage to UsageTracker
3. ✅ Step 2: Store commitment ID when created
4. ✅ Step 3: Store auth token in App Group
5. ✅ Step 4: Create ExtensionBackendClient
6. ✅ Step 5: Add rate limiting
7. ✅ Step 6: Integrate reporting into threshold handler
8. ✅ Step 7: (Optional) Token refresh
9. ✅ Step 8: Error handling & logging

**If Step 0 fails:** Skip to Fallback Plan (update `weekly-close` to estimate missing usage)

---

## Success Criteria

- ✅ Extension reports usage when thresholds are hit
- ✅ Reports work even when main app is force-quit
- ✅ Rate limiting prevents duplicate reports
- ✅ No crashes if data is missing
- ✅ Usage data appears in backend `daily_usage` table
- ✅ Weekly settlements can proceed even if user never opens app

---

## Notes

- Extension runs in a separate process, so logging goes to system logs (view via Console.app)
- Extension has limited execution time, so network calls must be quick
- Extension cannot show UI alerts, so errors are logged only
- Main app can still do catch-up reporting when it opens (for any missed periods)

