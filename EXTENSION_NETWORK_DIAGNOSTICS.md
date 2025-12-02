# Extension Network Diagnostics Plan

## Problem
Extension network requests are failing with `NSURLErrorNetworkConnectionLost` (-1005) even when app is open.

## Diagnostic Tests

### Test 1: Check if Requests Reach Supabase Backend
**Purpose:** Determine if requests are being blocked before reaching Supabase

**Steps:**
1. Go to Supabase Dashboard → Logs → API Logs
2. Filter by time period when you saw the error logs
3. Look for requests to `/rest/v1/rpc/rpc_report_usage`
4. Check if any requests appear

**Expected Results:**
- ✅ **If requests appear:** The issue is with response handling or extension termination
- ❌ **If NO requests appear:** The issue is with request sending (extension blocked, network issue, or malformed request)

**What to look for:**
- Request count
- Status codes (200, 401, 500, etc.)
- Error messages
- Request payload

---

### Test 2: Test Simple GET Request
**Purpose:** Verify basic network connectivity from extension

**What to test:**
- Make a simple GET request to `https://httpbin.org/get` (we know this worked in Step 0)
- See if it still works or if it also fails now

**Expected Results:**
- ✅ **If GET works:** Network connectivity is fine, issue is specific to POST/RPC call
- ❌ **If GET fails:** Network connectivity issue or extension restrictions

---

### Test 3: Test Supabase Health Endpoint
**Purpose:** Verify Supabase connectivity specifically

**What to test:**
- Make GET request to `https://whdftvcrtrsnefhprebj.supabase.co/rest/v1/` (Supabase REST endpoint)
- Check if we can reach Supabase at all

**Expected Results:**
- ✅ **If works:** Supabase is reachable, issue is with RPC call specifically
- ❌ **If fails:** Can't reach Supabase (network/firewall issue)

---

### Test 4: Check Request Format
**Purpose:** Verify the request we're sending is correctly formatted

**What to check:**
1. Review the request headers in `ExtensionBackendClient.swift`
2. Verify JSON body format matches what Supabase expects
3. Check if URL is correct: `https://whdftvcrtrsnefhprebj.supabase.co/rest/v1/rpc/rpc_report_usage`

**Compare with:**
- How main app calls it (via Supabase SDK)
- Supabase RPC documentation
- Check if we need different headers

**Key things to verify:**
- ✅ Authorization header format: `Bearer {token}`
- ✅ Content-Type: `application/json`
- ✅ Accept header: `application/json`
- ✅ apikey header: Present and correct
- ✅ prefer header: `return=representation` (is this needed?)
- ✅ JSON body format: `{"p_date": "...", "p_week_start_date": "...", "p_used_minutes": 15}`

---

### Test 5: Test with App Open vs Closed
**Purpose:** See if app state affects extension network access

**Test A: App Open (Backgrounded)**
1. Open app
2. Background it (don't force-quit)
3. Use limited apps
4. Check logs for network errors

**Test B: App Force-Quit**
1. Force-quit app
2. Use limited apps
3. Check logs for network errors

**Expected Results:**
- If both fail the same way → Not related to app state
- If one works and one doesn't → App state matters

---

### Test 6: Check Extension Execution Time
**Purpose:** See if extension is being terminated too quickly

**What to check:**
1. Add timing logs:
   - Log when request starts
   - Log when request completes/fails
   - Calculate duration

**Expected Results:**
- If requests fail consistently at same time (e.g., ~150ms) → Extension being killed
- If timing varies → Different issue

---

### Test 7: Test with Main App's BackendClient
**Purpose:** Compare extension call vs main app call

**What to test:**
1. Call `BackendClient.shared.reportUsage()` from main app
2. See if it succeeds
3. Compare request format/logs

**Expected Results:**
- ✅ **If main app works:** Issue is extension-specific
- ❌ **If main app also fails:** Backend issue

---

### Test 8: Check Supabase RLS Policies
**Purpose:** Verify RPC function is accessible

**What to check:**
1. Check if `rpc_report_usage` has proper permissions
2. Verify RLS policies allow authenticated users
3. Check if function is `SECURITY DEFINER` (should be)

**Expected Results:**
- If RLS is blocking → Would see 403/401 errors (not -1005)
- If function not accessible → Would see different error

---

### Test 9: Test Token Validity
**Purpose:** Verify auth token is still valid when extension uses it

**What to check:**
1. Log token when stored in App Group
2. Log token when extension reads it
3. Check if token has expired
4. Try refreshing token before making request

**Expected Results:**
- If token expired → Would see 401 errors (not -1005)
- If token invalid → Different error

---

### Test 10: Add Detailed Request Logging
**Purpose:** See exactly what's being sent

**What to add:**
- Log full request URL
- Log all headers (mask sensitive data)
- Log request body
- Log response (if any)
- Log exact error details

**Expected Results:**
- Might reveal malformed request
- Might show missing headers
- Might reveal network issue details

---

## Priority Order

1. **Test 1** (Check Supabase logs) - Most important, tells us if requests reach backend
2. **Test 2** (Simple GET) - Quick test of basic connectivity
3. **Test 4** (Request format) - Verify we're sending correct format
4. **Test 7** (Main app comparison) - See if it's extension-specific
5. **Test 10** (Detailed logging) - Get more diagnostic info

---

## What Each Test Tells Us

| Test | If Passes | If Fails | Next Step |
|------|----------|----------|-----------|
| Test 1 (Supabase logs) | Requests reach backend | Requests blocked | Check network/firewall |
| Test 2 (Simple GET) | Network works | Network blocked | Check entitlements |
| Test 4 (Request format) | Format correct | Format wrong | Fix request format |
| Test 7 (Main app) | Extension issue | Backend issue | Fix backend or extension |

---

## Quick Wins to Try First

1. **Check Supabase Dashboard logs** (5 minutes)
   - Go to Dashboard → Logs → API
   - See if requests appear

2. **Add more detailed error logging** (10 minutes)
   - Log full error details
   - Log request URL and headers
   - Log response if any

3. **Test simple GET request** (5 minutes)
   - See if basic network still works

---

## Implementation Notes

After running tests, we'll know:
- ✅ If requests reach backend → Focus on response handling
- ❌ If requests don't reach backend → Focus on request sending
- ✅ If simple GET works → Focus on POST/RPC specifics
- ❌ If simple GET fails → Focus on network/entitlements



