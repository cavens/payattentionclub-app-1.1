# Mode Transition Test Plan: Testing → Normal Mode

## Overview

This document outlines comprehensive testing to ensure the transition from testing mode to normal mode works correctly and safely.

## Critical Risks to Test

### 1. Configuration Mismatches
- **Risk**: `app_config.testing_mode` and Edge Function `TESTING_MODE` secret are out of sync
- **Impact**: Edge Functions behave differently than expected
- **Test**: Validate both locations match

### 2. Cron Job Behavior
- **Risk**: Wrong cron job runs, or both run simultaneously
- **Impact**: Settlement runs at wrong times or multiple times
- **Test**: Verify only correct cron runs based on mode

### 3. Timing Differences
- **Risk**: Code assumes testing mode timing (3 min week) in normal mode (7 day week)
- **Impact**: Calculations, deadlines, grace periods are wrong
- **Test**: Verify all timing logic respects current mode

### 4. Edge Function Cold Starts
- **Risk**: Edge Functions cache old `TESTING_MODE` value
- **Impact**: Functions use wrong mode until cold start
- **Test**: Verify functions read updated secret

### 5. Data Consistency
- **Risk**: Data created in testing mode incompatible with normal mode
- **Impact**: Errors when processing normal mode data
- **Test**: Verify data created in both modes works correctly

---

## Pre-Transition Validation

### Step 1: Run Validation Function

```sql
SELECT public.rpc_validate_mode_consistency();
```

**Expected Result:**
```json
{
  "valid": true,
  "mode": "testing",
  "app_config_mode": "true",
  "cron_jobs": {
    "testing_settlement": { "active": true },
    "weekly_settlement": { "active": true }
  },
  "issues": [],
  "warnings": []
}
```

### Step 2: Verify Current State

```sql
-- Check app_config
SELECT key, value, updated_at 
FROM app_config 
WHERE key IN ('testing_mode', 'supabase_access_token')
ORDER BY key;

-- Check cron jobs
SELECT jobname, schedule, active, command
FROM cron.job
WHERE jobname IN ('Testing-Settlement', 'Weekly-Settlement')
ORDER BY jobname;
```

### Step 3: Document Current Testing Mode Behavior

- Note current settlement schedule
- Note current week/grace period settings
- Note any test data that exists

---

## Transition Test Procedure

### Phase 1: Toggle to Normal Mode

1. **Run Pre-Transition Validation** (Step 1 above)
2. **Toggle Mode** via dashboard or command
3. **Verify Response**:
   ```json
   {
     "success": true,
     "testing_mode": false,
     "app_config_updated": true,
     "secret_updated": true  // ✅ Critical
   }
   ```
4. **Wait 5 seconds** for updates to propagate

### Phase 2: Post-Transition Validation

1. **Run Validation Function Again**:
   ```sql
   SELECT public.rpc_validate_mode_consistency();
   ```
   
   **Expected Result:**
   ```json
   {
     "valid": true,
     "mode": "normal",
     "app_config_mode": "false",
     "cron_jobs": {
       "testing_settlement": { "active": true },  // OK - will skip
       "weekly_settlement": { "active": true }    // ✅ Should be active
     },
     "issues": []
   }
   ```

2. **Verify app_config Updated**:
   ```sql
   SELECT value, updated_at 
   FROM app_config 
   WHERE key = 'testing_mode';
   -- Should show: value = 'false'
   ```

3. **Verify Edge Function Secret** (Manual Check):
   - Go to: Supabase Dashboard → Edge Functions → Settings → Secrets
   - Find `TESTING_MODE`
   - Value should be `false`

### Phase 3: Functional Testing

1. **Test Edge Function Reads Correct Mode**:
   ```bash
   # Call an Edge Function that checks TESTING_MODE
   # Verify it behaves as normal mode
   ```

2. **Test Cron Job Behavior**:
   ```sql
   -- Manually trigger call_settlement() to verify it skips in normal mode
   SELECT public.call_settlement();
   -- Should return early with notice about not being in testing mode
   ```

3. **Test Normal Mode Settlement**:
   ```sql
   -- Manually trigger normal mode settlement
   SELECT public.call_settlement_normal();
   -- Should call bright-service with correct headers
   ```

### Phase 4: Toggle Back to Testing Mode

1. **Toggle back to testing mode**
2. **Verify both locations update**
3. **Run validation function again**
4. **Verify testing mode behavior restored**

---

## Automated Test Script

```typescript
// scripts/test_mode_transition.ts
// Tests complete mode transition cycle
```

**Test Flow:**
1. Get initial state
2. Validate initial state
3. Toggle to normal mode
4. Validate normal mode
5. Test normal mode behavior
6. Toggle back to testing mode
7. Validate testing mode restored

---

## Risk Mitigation Strategies

### 1. Configuration Validation Function

**Created**: `rpc_validate_mode_consistency()`

**Purpose**: 
- Validates app_config and cron jobs are consistent
- Detects mismatches before they cause issues
- Provides actionable fix suggestions

**Usage**:
- Run before mode transitions
- Run after mode transitions
- Run periodically (e.g., daily cron)

### 2. Dual Update Verification

**Strategy**: Always update both locations atomically

**Implementation**:
- `toggle_testing_mode` updates both `app_config` and Edge Function secret
- Returns status of both updates
- Shows warning if secret update fails

### 3. Graceful Degradation

**Strategy**: If secret update fails, app_config is still updated

**Benefit**: 
- System continues to work (database functions use app_config)
- Edge Functions may use cached value until cold start
- Clear warning shows what needs manual fix

### 4. Cron Job Safety Checks

**Strategy**: Cron jobs check `app_config.testing_mode` before running

**Implementation**:
- `call_settlement()` checks `app_config.testing_mode`
- Returns early if mode doesn't match
- Prevents wrong cron from executing

### 5. Edge Function Mode Checks

**Strategy**: Edge Functions check both environment variable AND app_config

**Implementation**:
- Functions read `TESTING_MODE` env var (fast)
- Also check `app_config.testing_mode` (accurate)
- Use app_config as source of truth if env var missing

### 6. Monitoring and Alerts

**Strategy**: Detect configuration mismatches automatically

**Implementation**:
- Run `rpc_validate_mode_consistency()` daily
- Alert if `valid: false`
- Log mode transitions with timestamps

---

## Normal Mode Specific Tests

### Test 1: Week Duration

**Verify**: Week is 7 days, not 3 minutes

**Test**:
```sql
-- Check deadline calculation uses 7 days
SELECT 
  commitment_id,
  deadline_date,
  created_at,
  deadline_date - created_at AS week_duration
FROM commitments
WHERE created_at > NOW() - INTERVAL '1 day'
ORDER BY created_at DESC
LIMIT 5;
-- week_duration should be ~7 days
```

### Test 2: Grace Period

**Verify**: Grace period is 24 hours, not 1 minute

**Test**:
```sql
-- Check grace period calculation
SELECT 
  penalty_id,
  week_end_date,
  grace_period_end_date,
  grace_period_end_date - week_end_date AS grace_duration
FROM user_week_penalties
WHERE week_end_date > NOW() - INTERVAL '2 days'
ORDER BY week_end_date DESC
LIMIT 5;
-- grace_duration should be ~24 hours
```

### Test 3: Settlement Schedule

**Verify**: Settlement runs weekly, not every 3 minutes

**Test**:
```sql
-- Check cron schedule
SELECT jobname, schedule
FROM cron.job
WHERE jobname = 'Weekly-Settlement';
-- Should be: '0 12 * * 2' (Tuesday at 12:00)
```

### Test 4: Edge Function Behavior

**Verify**: Edge Functions use normal mode timing

**Test**:
- Call `super-service` (create commitment)
- Verify deadline is 7 days from now
- Call `bright-service` (settlement)
- Verify it processes full week, not 3 minutes

---

## Rollback Procedure

If normal mode has issues:

1. **Immediate Rollback**:
   ```sql
   -- Toggle back to testing mode
   UPDATE app_config 
   SET value = 'true', updated_at = NOW()
   WHERE key = 'testing_mode';
   ```

2. **Update Edge Function Secret**:
   - Go to Supabase Dashboard → Edge Functions → Settings → Secrets
   - Set `TESTING_MODE` = `true`

3. **Verify Rollback**:
   ```sql
   SELECT public.rpc_validate_mode_consistency();
   ```

4. **Test Testing Mode Works**:
   - Verify testing mode behavior restored
   - Run test settlement

---

## Success Criteria

✅ Mode toggle updates both locations  
✅ Validation function shows `valid: true`  
✅ Cron jobs behave correctly  
✅ Edge Functions read correct mode  
✅ Timing calculations use correct values  
✅ No errors in function logs  
✅ Settlement runs at correct schedule  

---

## Continuous Monitoring

### Daily Validation

Run this daily to catch configuration drift:

```sql
SELECT public.rpc_validate_mode_consistency();
```

### Alert on Issues

If `valid: false`, investigate immediately:
1. Check `issues` array for specific problems
2. Fix configuration mismatches
3. Re-run validation
4. Document root cause

---

## Next Steps

1. ✅ Create validation function (`rpc_validate_mode_consistency`)
2. ⏳ Create automated test script
3. ⏳ Set up daily validation cron job
4. ⏳ Document normal mode behavior differences
5. ⏳ Create rollback procedure checklist

