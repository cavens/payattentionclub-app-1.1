# How to Test admin-close-week-now

## ⚠️ Easier Option Available!

**You don't need JWT tokens!** Call `weekly-close` directly instead:
- See `HOW_TO_TEST_WEEKLY_CLOSE_DIRECT.md` for the easier method
- No authentication needed!

---

## Prerequisites (Only if using admin-close-week-now)

1. **You must be authenticated** - Need a valid JWT token
2. **Your user must be a test user** - `is_test_user = true` in `users` table
3. **Function must be deployed** - ✅ Already deployed

---

## Method 1: Via Supabase Dashboard (Easiest) ⭐

### Step 1: Get Your JWT Token

**Option A: From your iOS app**
- Sign in with Apple in your app
- Get the access token from `AuthenticationManager` or `BackendClient`
- Copy the token

**Option B: From Supabase Dashboard**
1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/auth/users
2. Find your user
3. Click "..." → "Generate JWT token"
4. Copy the token

### Step 2: Invoke the Function

1. Go to: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions
2. Click on `admin-close-week-now`
3. Click **"Invoke function"** button
4. Select **"POST"** method
5. In **Headers**, add:
   ```
   Authorization: Bearer YOUR_JWT_TOKEN_HERE
   ```
6. In **Body**, leave empty `{}` or:
   ```json
   {}
   ```
7. Click **"Invoke"**
8. See the response in the output panel below

### Expected Response

```json
{
  "ok": true,
  "message": "Weekly close triggered",
  "triggeredBy": "your-email@example.com",
  "result": {
    "weekDeadline": "2024-11-18",
    "poolTotalCents": 0,
    "chargedUsers": 0,
    "succeededPayments": 0,
    "requiresActionPayments": 0,
    "failedPayments": 0,
    "results": []
  }
}
```

---

## Method 2: Via curl (Terminal)

### Step 1: Get Your JWT Token
(Use one of the methods above)

### Step 2: Run curl Command

```bash
curl -X POST \
  'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/admin-close-week-now' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN_HERE' \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Replace `YOUR_JWT_TOKEN_HERE` with your actual JWT token**

### Example Output

```json
{
  "ok": true,
  "message": "Weekly close triggered",
  "triggeredBy": "user@example.com",
  "result": {
    "weekDeadline": "2024-11-18",
    "poolTotalCents": 0,
    "chargedUsers": 0,
    "succeededPayments": 0,
    "requiresActionPayments": 0,
    "failedPayments": 0,
    "results": []
  }
}
```

---

## Method 3: Via Your iOS App (Swift)

Add this to your `BackendClient.swift` or create a test view:

```swift
func adminCloseWeekNow() async throws -> AdminCloseWeekNowResponse {
    guard let session = try await currentSession else {
        throw BackendError.notAuthenticated
    }
    
    let url = URL(string: "\(Config.supabaseURL)/functions/v1/admin-close-week-now")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = "{}".data(using: .utf8)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
        throw BackendError.unknown
    }
    
    guard httpResponse.statusCode == 200 else {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw BackendError.httpError(httpResponse.statusCode, errorMessage)
    }
    
    return try JSONDecoder().decode(AdminCloseWeekNowResponse.self, from: data)
}

struct AdminCloseWeekNowResponse: Codable {
    let ok: Bool
    let message: String
    let triggeredBy: String
    let result: WeeklyCloseResult
}

struct WeeklyCloseResult: Codable {
    let weekDeadline: String
    let poolTotalCents: Int
    let chargedUsers: Int
    let succeededPayments: Int
    let requiresActionPayments: Int
    let failedPayments: Int
    let results: [PaymentResult]
}

struct PaymentResult: Codable {
    let userId: String?
    let success: Bool?
    let paymentIntentId: String?
    let status: String?
    let amountCents: Int?
    let error: String?
}
```

---

## Troubleshooting

### Error: "Missing Authorization header"
- **Fix:** Add `Authorization: Bearer YOUR_JWT_TOKEN` header

### Error: "Not authenticated"
- **Fix:** Your JWT token is invalid or expired. Get a new one.

### Error: "Forbidden" (403)
- **Fix:** Your user doesn't have `is_test_user = true`
- **Solution:** Update your user in the database:
  ```sql
  UPDATE users 
  SET is_test_user = true 
  WHERE id = 'your-user-id';
  ```

### Error: "User not found in public.users"
- **Fix:** Make sure your user exists in the `users` table (not just `auth.users`)

### No Output / Empty Response
- **Check:** Supabase Dashboard → Functions → `admin-close-week-now` → Logs
- **Check:** Supabase Dashboard → Functions → `weekly-close` → Logs
- Look for error messages or console.log output

---

## What to Check After Running

1. **Response Status:** Should be `200 OK`
2. **Result Object:** Contains `weekDeadline`, `poolTotalCents`, etc.
3. **Logs:** Check Supabase Dashboard logs for detailed output
4. **Database:** Check if `weekly_pools` was updated, `user_week_penalties` created, etc.

---

## Quick Test Checklist

- [ ] User is authenticated (has valid JWT)
- [ ] User has `is_test_user = true` in database
- [ ] Function is deployed (✅ Done)
- [ ] Call function with POST method
- [ ] Include Authorization header
- [ ] Check response for `result` object
- [ ] Check logs if no output

---

## Next Steps After Testing

Once you see the output:
1. Verify the `weekDeadline` is correct
2. Check if `poolTotalCents` matches expected values
3. Verify `chargedUsers` count
4. Check if payments were created in `payments` table
5. Verify `weekly_pools` status is "closed"

