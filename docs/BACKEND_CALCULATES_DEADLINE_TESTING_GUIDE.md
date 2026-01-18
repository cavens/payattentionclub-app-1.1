# Backend Calculates Deadline - Testing Guide

**Date**: 2026-01-15  
**Purpose**: Test that backend now calculates deadlines internally (single source of truth)

---

## Changes Made

### Backend Changes

1. **New Edge Function**: `preview-service`
   - Calculates deadline internally
   - Calls `rpc_preview_max_charge` with calculated deadline
   - Testing mode: 3 minutes from now
   - Normal mode: Next Monday 12:00 ET

2. **Updated Edge Function**: `super-service`
   - Removed `weekStartDate` parameter
   - Calculates deadline internally
   - Testing mode: 3 minutes from now
   - Normal mode: Next Monday 12:00 ET

3. **RPC Function**: `rpc_preview_max_charge`
   - **No changes needed** - still accepts `p_deadline_date` parameter
   - Edge Function calculates deadline and passes it to RPC

### iOS App Changes

1. **BackendClient.previewMaxCharge()**
   - Removed `deadlineDate` parameter
   - Now calls `preview-service` Edge Function instead of RPC directly

2. **BackendClient.createCommitment()**
   - Removed `weekStartDate` parameter
   - Backend calculates deadline internally

3. **AppModel.fetchAuthorizationAmount()**
   - Removed deadline calculation
   - Calls `previewMaxCharge()` without deadline parameter

4. **AuthorizationView.lockInAndStartMonitoring()**
   - Removed deadline calculation
   - Calls `createCommitment()` without deadline parameter

---

## Testing Steps

### Step 1: Deploy Backend Changes

**Deploy Edge Functions**:
```bash
cd /Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1

# Deploy preview-service (new Edge Function)
supabase functions deploy preview-service

# Deploy super-service (updated Edge Function)
supabase functions deploy super-service
```

**Verify Deployment**:
- Check Supabase Dashboard → Edge Functions
- Both functions should be listed and active

---

### Step 2: Test Preview Max Charge (Normal Mode)

**Setup**:
1. Ensure `TESTING_MODE` is **not** set (or set to `false`)
2. Build and run iOS app

**Test**:
1. Open app
2. Navigate to setup screen
3. Select apps to limit
4. Set limit (e.g., 60 minutes)
5. Set penalty (e.g., $0.10/minute)
6. **Watch authorization amount appear** (should call preview-service)

**Expected Results**:
- ✅ Authorization amount displays correctly
- ✅ Amount matches what would be calculated for next Monday deadline
- ✅ No errors in Xcode console
- ✅ Logs show: `"PREVIEW BackendClient: Calling preview-service Edge Function"`

**Check Logs**:
```
PREVIEW BackendClient: Calling preview-service Edge Function with params: limit=60min, penalty=10cents, apps=X, categories=Y
PREVIEW BackendClient: ✅ Got max charge preview: XXXX cents ($XX.XX)
```

---

### Step 3: Test Preview Max Charge (Testing Mode)

**Setup**:
1. Set `TESTING_MODE=true` in Supabase Edge Function secrets
2. Redeploy `preview-service` Edge Function
3. Build and run iOS app

**Test**:
1. Open app
2. Navigate to setup screen
3. Select apps to limit
4. Set limit and penalty
5. **Watch authorization amount appear**

**Expected Results**:
- ✅ Authorization amount displays correctly
- ✅ Amount matches what would be calculated for 3-minute deadline
- ✅ No errors in Xcode console

**Check Backend Logs** (Supabase Dashboard → Edge Functions → preview-service → Logs):
```
preview-service: Calculated deadline date: 2026-01-15T12:03:00.000Z (testing mode: true)
```

---

### Step 4: Test Create Commitment (Normal Mode)

**Setup**:
1. Ensure `TESTING_MODE` is **not** set (or set to `false`)
2. Build and run iOS app
3. Have payment method set up

**Test**:
1. Open app
2. Navigate to setup screen
3. Select apps, set limit, set penalty
4. Tap "Lock in" button
5. Complete payment (if needed)
6. **Commitment should be created**

**Expected Results**:
- ✅ Commitment created successfully
- ✅ Deadline in response matches next Monday 12:00 ET
- ✅ Countdown shows correct time (next Monday)
- ✅ No errors in Xcode console
- ✅ Logs show: `"LOCKIN AuthorizationView: Step 2 - Calling createCommitment()... (backend will calculate deadline)"`

**Check Logs**:
```
LOCKIN AuthorizationView: Step 2 - Parameters ready - limitMinutes: 60, penaltyPerMinuteCents: 10
LOCKIN AuthorizationView: Step 2 - Calling createCommitment()... (backend will calculate deadline)
COMMITMENT BackendClient: ✅ Successfully decoded CommitmentResponse from Edge Function
AUTH AuthorizationView: ✅ Using backend deadline (date only): [date] (from [date])
```

**Verify Database**:
- Check `commitments` table
- `week_end_date` should be next Monday
- `week_end_timestamp` should be `NULL` (normal mode)

---

### Step 5: Test Create Commitment (Testing Mode)

**Setup**:
1. Set `TESTING_MODE=true` in Supabase Edge Function secrets
2. Redeploy `super-service` Edge Function
3. Build and run iOS app
4. Have payment method set up

**Test**:
1. Open app
2. Navigate to setup screen
3. Select apps, set limit, set penalty
4. Tap "Lock in" button
5. Complete payment (if needed)
6. **Commitment should be created**

**Expected Results**:
- ✅ Commitment created successfully
- ✅ Deadline in response is ISO 8601 timestamp (~3 minutes from now)
- ✅ Countdown shows ~3 minutes
- ✅ No errors in Xcode console

**Check Logs**:
```
LOCKIN AuthorizationView: Step 2 - Calling createCommitment()... (backend will calculate deadline)
COMMITMENT BackendClient: ✅ Successfully decoded CommitmentResponse from Edge Function
AUTH AuthorizationView: ✅ Using backend deadline (ISO 8601): [timestamp] (from [timestamp])
```

**Verify Database**:
- Check `commitments` table
- `week_end_date` should be today's date
- `week_end_timestamp` should be ISO timestamp (~3 minutes from creation)

---

### Step 6: Test Timing Window (Preview vs Commitment)

**Purpose**: Verify that preview and commitment can use different deadlines if user takes time to decide

**Test**:
1. Open app at 11:59 AM ET on Monday
2. Navigate to setup screen
3. Select apps, set limit, set penalty
4. **Note the authorization amount** (preview)
5. Wait 2 minutes (until 12:01 PM ET)
6. Tap "Lock in" button
7. **Note the deadline in response**

**Expected Results**:
- ✅ Preview shows amount for Monday deadline (1 minute away)
- ✅ Commitment uses next Monday deadline (7 days away)
- ✅ Authorization amounts might be different (acceptable - preview is estimate)
- ✅ No errors

**Note**: This is expected behavior - preview is just an estimate, actual commitment uses current time's deadline.

---

### Step 7: Test Edge Function Logs

**Check Supabase Dashboard**:
1. Go to Edge Functions → preview-service → Logs
2. Look for: `"preview-service: Calculated deadline date: [date] (testing mode: [true/false])"`

**Check Supabase Dashboard**:
1. Go to Edge Functions → super-service → Logs
2. Look for: `"super-service: Calculated deadline date: [date] (testing mode: [true/false])"`

**Expected Logs**:
- Normal mode: Deadline should be next Monday (YYYY-MM-DD format)
- Testing mode: Deadline should be ~3 minutes from now (ISO 8601 format)

---

## Verification Checklist

### ✅ Backend Verification

- [ ] `preview-service` Edge Function deployed
- [ ] `super-service` Edge Function deployed
- [ ] Edge Function logs show deadline calculation
- [ ] Testing mode: Deadline is ~3 minutes from now
- [ ] Normal mode: Deadline is next Monday 12:00 ET

### ✅ iOS App Verification

- [ ] App builds without errors
- [ ] Preview max charge works (no deadline parameter)
- [ ] Create commitment works (no deadline parameter)
- [ ] Countdown shows correct time
- [ ] Backend deadline is used (from response)

### ✅ Database Verification

- [ ] Commitments created with correct `week_end_date`
- [ ] Testing mode: `week_end_timestamp` is set (ISO timestamp)
- [ ] Normal mode: `week_end_timestamp` is NULL

### ✅ Consistency Verification

- [ ] Preview and commitment use same deadline calculation logic
- [ ] Testing mode works correctly (compressed timeline)
- [ ] Normal mode works correctly (next Monday)
- [ ] No deadline calculations in iOS app code

---

## Troubleshooting

### Issue: "Function not found" error

**Cause**: Edge Function not deployed

**Fix**:
```bash
supabase functions deploy preview-service
supabase functions deploy super-service
```

---

### Issue: "Missing required fields: weekStartDate"

**Cause**: Old iOS app version calling new backend

**Fix**: Update iOS app to remove `weekStartDate` parameter

---

### Issue: Preview shows wrong amount

**Cause**: Backend calculating wrong deadline

**Check**:
1. Edge Function logs for deadline calculation
2. Verify `TESTING_MODE` is set correctly
3. Check timezone handling

---

### Issue: Countdown shows wrong time

**Cause**: iOS app not using backend deadline from response

**Check**:
1. Verify `AuthorizationView` parses deadline from response
2. Check logs for: `"AUTH AuthorizationView: ✅ Using backend deadline"`
3. Verify deadline is stored in `UsageTracker`

---

## Success Criteria

✅ **All tests pass**:
- Preview works in both modes
- Commitment works in both modes
- Countdown shows correct time
- Database stores correct deadlines

✅ **No deadline calculations in iOS app**:
- `getNextMondayNoonEST()` not called for preview/commitment
- Backend is single source of truth

✅ **Consistent behavior**:
- Same deadline calculation logic in both preview and commitment
- Testing mode works correctly
- Normal mode works correctly

---

## Rollback Plan

If issues occur, rollback steps:

1. **Revert iOS app changes**:
   - Restore `deadlineDate` parameter to `previewMaxCharge()`
   - Restore `weekStartDate` parameter to `createCommitment()`
   - Restore deadline calculations in iOS app

2. **Revert backend changes**:
   - Restore `weekStartDate` parameter to `super-service`
   - Keep `preview-service` (or remove if causing issues)
   - Redeploy Edge Functions

3. **Verify**:
   - Test that old behavior works
   - Check database for correct deadlines

---

## Next Steps After Testing

1. **Monitor for 24-48 hours**:
   - Check Edge Function logs for errors
   - Monitor database for correct deadlines
   - Check user reports for issues

2. **Remove old code** (after verification):
   - Remove deadline calculation functions from iOS app (if no longer used)
   - Clean up comments and documentation

3. **Update documentation**:
   - Update API documentation
   - Update architecture diagrams
   - Update testing guides



