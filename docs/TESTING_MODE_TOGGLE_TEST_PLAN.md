# Testing Mode Toggle - Complete Test Plan

## Overview

This document outlines comprehensive tests to verify that the mode toggle functionality works correctly, updating both `app_config` and Edge Function secrets.

## Test Scenarios

### Test 1: Basic Toggle Test

**Objective**: Verify the toggle button updates both locations

**Steps**:
1. Open testing dashboard
2. Check current testing mode status
3. Click toggle button
4. Verify response shows both updates succeeded

**Expected Result**:
```json
{
  "success": true,
  "testing_mode": true,
  "app_config_updated": true,
  "secret_updated": true  // ✅ This should be true
}
```

**Verification**:
- Check Supabase Dashboard → Edge Functions → Settings → Secrets
- Look for `TESTING_MODE` secret
- Value should match `app_config.testing_mode`

---

### Test 2: Toggle Back and Forth

**Objective**: Verify toggle works in both directions

**Steps**:
1. Toggle ON (if currently OFF)
2. Verify both locations updated
3. Toggle OFF
4. Verify both locations updated again

**Expected Result**: Both toggles should succeed with `secret_updated: true`

---

### Test 3: Database Verification

**Objective**: Verify database state matches

**SQL Query**:
```sql
-- Check app_config
SELECT key, value, updated_at 
FROM app_config 
WHERE key = 'testing_mode';

-- Check PAT is configured
SELECT 
  CASE 
    WHEN EXISTS (SELECT 1 FROM app_config WHERE key = 'supabase_access_token' AND value IS NOT NULL)
    THEN '✅ PAT configured'
    ELSE '❌ PAT missing'
  END AS pat_status;
```

**Expected Result**: 
- `testing_mode` value should match current state
- PAT should be configured

---

### Test 4: Edge Function Secret Verification

**Objective**: Verify Edge Function can read updated secret

**Manual Check**:
1. Go to: https://supabase.com/dashboard/project/YOUR_PROJECT_REF/settings/functions
2. Find `TESTING_MODE` secret
3. Verify value matches `app_config.testing_mode`

**Expected Result**: Values should match

---

### Test 5: Edge Function Behavior Test

**Objective**: Verify Edge Functions actually use the updated secret

**Steps**:
1. Toggle testing mode ON
2. Call an Edge Function that checks `TESTING_MODE`
3. Verify it behaves as if testing mode is ON
4. Toggle testing mode OFF
5. Call the same Edge Function
6. Verify it behaves as if testing mode is OFF

**Note**: Edge Functions read `TESTING_MODE` at startup, so they may need to be restarted or wait for cold start to see changes.

---

### Test 6: Cron Job Behavior

**Objective**: Verify cron jobs respect testing mode

**Steps**:
1. Toggle testing mode ON
2. Check that `Testing-Settlement` cron runs (if scheduled)
3. Check that `Weekly-Settlement` cron is skipped
4. Toggle testing mode OFF
5. Check that `Weekly-Settlement` cron runs
6. Check that `Testing-Settlement` cron is skipped

**SQL Check**:
```sql
-- Check cron job status
SELECT jobname, schedule, active
FROM cron.job
WHERE jobname IN ('Testing-Settlement', 'Weekly-Settlement');
```

---

### Test 7: Error Handling

**Objective**: Verify graceful handling when PAT is missing

**Steps**:
1. Temporarily remove PAT from `app_config`
2. Try to toggle mode
3. Verify `app_config` still updates
4. Verify `secret_updated` is false
5. Verify warning message is shown
6. Restore PAT

**Expected Result**:
```json
{
  "success": true,
  "app_config_updated": true,
  "secret_updated": false,
  "warning": "⚠️ Testing mode updated in database, but Edge Function secret update failed..."
}
```

---

## Automated Test Script

Run the complete test suite:

```bash
cd payattentionclub-app-1.1
deno run --allow-net --allow-env scripts/test_mode_toggle_complete.ts
```

This script will:
1. Check initial state
2. Toggle mode
3. Verify updates
4. Toggle back
5. Verify final state
6. Report summary

---

## Manual Testing Checklist

- [ ] Toggle button appears in dashboard
- [ ] Toggle updates `app_config.testing_mode`
- [ ] Toggle updates Edge Function secret `TESTING_MODE`
- [ ] Both updates happen atomically (or with clear status)
- [ ] Error messages are clear if PAT is missing
- [ ] Toggle works in both directions (ON → OFF → ON)
- [ ] Edge Functions read updated secret (may require restart)
- [ ] Cron jobs respect testing mode

---

## Troubleshooting

### Secret not updating

1. **Check PAT is configured**:
   ```sql
   SELECT key, LENGTH(value) as token_length
   FROM app_config
   WHERE key = 'supabase_access_token';
   ```

2. **Check update-secret function logs**:
   - Go to Supabase Dashboard → Edge Functions → update-secret → Logs
   - Look for errors or warnings

3. **Verify PAT is valid**:
   - Go to https://supabase.com/dashboard/account/tokens
   - Check if token is still active
   - Generate new one if needed

### app_config updates but secret doesn't

- PAT might be missing or invalid
- Management API might be down
- Check function logs for specific error

### Both update but Edge Functions don't see change

- Edge Functions read secrets at startup
- May need to wait for cold start
- Or manually restart/redeploy function

---

## Success Criteria

✅ All tests pass  
✅ Toggle updates both locations  
✅ No errors in function logs  
✅ Edge Functions behave correctly  
✅ Cron jobs respect mode  

