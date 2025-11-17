# How to Get Your JWT Token

## JWT Tokens Expire!

**Important:** JWT tokens typically expire after **1 hour**. If your token is old, you need to get a fresh one.

---

## Method 1: From Your iOS App (Easiest) ⭐

### Option A: Add Debug Code to Print Token

Add this temporary code to your app (e.g., in a test view or debug menu):

```swift
import SwiftUI

struct TokenView: View {
    @State private var token: String = "Loading..."
    
    var body: some View {
        VStack {
            Text("JWT Token:")
            Text(token)
                .font(.system(size: 10))
                .padding()
            Button("Copy Token") {
                UIPasteboard.general.string = token
            }
            Button("Refresh Token") {
                Task {
                    await loadToken()
                }
            }
        }
        .task {
            await loadToken()
        }
    }
    
    func loadToken() async {
        do {
            if let session = try await BackendClient.shared.currentSession {
                token = session.accessToken
            } else {
                token = "Not authenticated"
            }
        } catch {
            token = "Error: \(error.localizedDescription)"
        }
    }
}
```

### Option B: Use Xcode Console

Add this to your app code temporarily:

```swift
Task {
    if let session = try? await BackendClient.shared.currentSession {
        print("🔑 JWT Token: \(session.accessToken)")
        print("📅 Expires: \(session.expiresAt)")
    } else {
        print("❌ No session found")
    }
}
```

Then check Xcode console output.

---

## Method 2: From Supabase Dashboard

1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/users
2. Find your user (search by email)
3. Click the **"..."** menu (three dots)
4. Select **"Generate JWT token"**
5. Copy the token (it's valid for 1 hour)

**Note:** This creates a new token, but it might not match your app's session.

---

## Method 3: Check UserDefaults (Where Token is Stored)

The token is stored in UserDefaults. You can check it:

### In Xcode Debugger

1. Set a breakpoint in your app
2. In the debugger console, type:
   ```lldb
   po UserDefaults.standard.dictionaryRepresentation()
   ```
3. Look for keys like:
   - `supabase.auth.token`
   - `supabase.auth.refresh_token`

### Via Terminal (if app is running)

```bash
# This won't work directly, but you can add logging to your app
```

---

## Method 4: Refresh the Token

If your token expired, refresh it:

```swift
// In your app
Task {
    do {
        // This will refresh the token if needed
        let session = try await BackendClient.shared.currentSession
        print("Token: \(session.accessToken)")
    } catch {
        // Token expired, need to sign in again
        print("Need to sign in again")
    }
}
```

Or sign in again:

```swift
let session = try await AuthenticationManager.shared.signInWithApple()
print("New token: \(session.accessToken)")
```

---

## Method 5: Use Service Role Key (For Testing Only)

**⚠️ WARNING: Only for testing! Never use in production!**

If you just need to test `admin-close-week-now`, you can temporarily modify it to accept service role key:

1. Get your service role key from Supabase Dashboard → Settings → API
2. Use it in the Authorization header:
   ```
   Authorization: Bearer YOUR_SERVICE_ROLE_KEY
   ```

**But this bypasses authentication checks!** Only use for testing.

---

## Quick Test: Check if Token is Valid

### Via curl

```bash
# Replace YOUR_JWT_TOKEN with your actual token
curl -X GET \
  'https://whdftvcrtrsnefhprebj.supabase.co/rest/v1/users?select=id' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN' \
  -H 'apikey: YOUR_ANON_KEY'
```

If you get data back, token is valid. If you get 401, token is expired/invalid.

---

## Troubleshooting

### "Not authenticated" Error
- **Cause:** Token expired or invalid
- **Fix:** Get a fresh token (sign in again in app, or generate new one in dashboard)

### "Missing Authorization header"
- **Cause:** Token not included in request
- **Fix:** Make sure you're adding `Authorization: Bearer YOUR_TOKEN` header

### Token Works in App But Not in Dashboard
- **Cause:** Different sessions/tokens
- **Fix:** Use the token from your app, not a generated one from dashboard

---

## Recommended Approach

**For testing `admin-close-week-now`:**

1. **Run your iOS app**
2. **Sign in with Apple** (if not already signed in)
3. **Add temporary debug code** to print the token:
   ```swift
   if let session = try? await BackendClient.shared.currentSession {
       print("Token: \(session.accessToken)")
   }
   ```
4. **Copy the token** from Xcode console
5. **Use it in Supabase Dashboard** to invoke `admin-close-week-now`

---

## Token Storage Location

In your app, tokens are stored in:
- **UserDefaults** (via `UserDefaultsLocalStorage`)
- Key: `supabase.auth.token` (or similar)
- Contains: `access_token`, `refresh_token`, `expires_at`

The Supabase client automatically refreshes tokens when they expire (if refresh token is valid).


