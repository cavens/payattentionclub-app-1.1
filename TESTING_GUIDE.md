# Testing Guide

Frontend-to-backend integration testing guide for PayAttentionClub.

## How to Test Phase 2: `checkBillingStatus()`

### Step 1: Access the Test View

1. **Run the app** in Xcode (simulator or device)
2. Navigate to the **Setup** screen
3. You'll see a **🧪 Test Backend (Temporary)** button
4. Tap it to open the Backend Test view

### Step 2: Run the Test

1. In the Backend Test view, tap **"Test Backend"** button
2. The app will:
   - Show a loading indicator
   - Make a network call to `billing-status` Edge Function
   - Display results (success or error)

### Step 3: Check Results

#### ✅ Success Case
If the backend is working, you'll see:
- **Duration**: How long the call took (e.g., "0.45s")
- **hasPaymentMethod**: Boolean value
- **needsSetupIntent**: Boolean value  
- **setupIntentClientSecret**: String or "nil"
- **stripeCustomerId**: String or "nil"

#### ❌ Error Case
If something fails, you'll see:
- **Duration**: How long before error occurred
- **Error Type**: The Swift error type
- **Description**: Human-readable error message
- **Full Error**: Complete error details

### Step 4: Check Console Logs

Open **Console** in Xcode (View → Debug Area → Activate Console) and filter for:
```
BACKEND_TEST
```

You'll see detailed logs:
- `BACKEND_TEST: Starting checkBillingStatus() test`
- `BACKEND_TEST: Calling BackendClient.shared.checkBillingStatus()`
- `BACKEND_TEST: ✅ Success!` (or `❌ Error`)
- Response details

### Common Error Scenarios

#### 1. **Function Not Found** (404)
```
Error: Function not found
```
**Meaning**: The `billing-status` Edge Function doesn't exist in Supabase
**Fix**: Deploy the Edge Function in Supabase

#### 2. **Network Error** (No Internet)
```
URLError: The Internet connection appears to be offline
```
**Meaning**: No internet connection
**Fix**: Check your network connection

#### 3. **Authentication Error** (401)
```
Error: Unauthorized
```
**Meaning**: User is not authenticated
**Fix**: This is expected if Sign in with Apple isn't set up yet

#### 4. **Timeout**
```
URLError: The request timed out
```
**Meaning**: Backend took too long to respond
**Fix**: Check if backend is running/deployed

### What Success Looks Like

If everything works, you should see:
```
✅ Success:
Duration: 0.45s

hasPaymentMethod: false
needsSetupIntent: true
setupIntentClientSecret: seti_xxxxx...
stripeCustomerId: cus_xxxxx...
```

### After Testing

Once you've verified the backend works:

1. **Remove the test code**:
   - Delete `Views/BackendTestView.swift`
   - Remove `.backendTest` case from `AppScreen` enum
   - Remove test button from `SetupView.swift`
   - Remove test case from `RootRouterView`

2. **Or keep it** for future testing (just hide the button)

---

## Testing Checklist

- [x] App compiles without errors ✅
- [x] Test view appears when tapping test button ✅ (Test infrastructure was removed after completion)
- [x] "Test Backend" button works ✅ (Test infrastructure was removed after completion)
- [x] Network call is made (check console logs) ✅
- [x] Response is received (success or error) ✅
- [x] Results are displayed correctly ✅
- [x] Console logs show detailed information ✅
- [x] Test code cleanup completed ✅ (BackendTestView.swift removed, .backendTest case removed from AppScreen)

**Status**: ✅ Phase 2 testing completed - Test infrastructure has been cleaned up as per "After Testing" section.

---

## Next Steps After Successful Test

Once `checkBillingStatus()` works:
- ✅ Phase 2 is complete
- ✅ Backend connectivity is verified
- ✅ Ready to proceed with Phase 3 (RPC methods)

## Additional Testing Status

Based on `docs/TEST_IMPLEMENTATION_PLAN.md`:

**✅ Completed:**
- Backend tests (Phase 2): All test files created and working
- Config setup (Phase 1): Config.swift and test configs complete
- Test cleanup infrastructure: RPC functions for test data management

**⏳ In Progress / Pending:**
- iOS Unit Tests (Phase 3): Some test files exist but not all:
  - ✅ `AppModelAuthorizationTests.swift` exists
  - ✅ `BackendClientAuthorizationTests.swift` exists
  - ✅ `AuthorizationIntegrationTests.swift` exists
  - ❌ `AppModelTests.swift` - missing
  - ❌ `BackendClientTests.swift` - missing (parsing tests)
  - ❌ `DateUtilsTests.swift` - missing
- iOS UI Tests (Phase 4): Not started
- Dev Menu (Phase 5): Not started
- Master Test Script (Phase 6): Script exists but may need updates

