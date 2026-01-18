# Testing Mode to Normal Mode Transition: Risk Analysis

**Date**: 2026-01-18  
**Purpose**: Analyze risks when transitioning from testing mode to normal mode

---

## Overview

The system has **two separate cron job schedules** that run simultaneously:
- **Testing mode cron**: Runs frequently (every 1-2 minutes)
- **Normal mode cron**: Runs less frequently (every 10 minutes, or weekly for settlement)

Both cron jobs check `app_config.testing_mode` at runtime to determine if they should process work.

---

## Critical Risks

### 🔴 **RISK 1: Configuration Mismatch Between app_config and Environment Variables**

**Problem**:
- `app_config.testing_mode` (database) - used by cron jobs and RPC functions
- `TESTING_MODE` environment variable (Edge Function secrets) - used by Edge Functions
- These can be **out of sync**

**Impact**:
- Cron jobs check `app_config` → see normal mode
- Edge Functions check `TESTING_MODE` env var → see testing mode
- **Result**: Cron jobs run on normal schedule, but Edge Functions use testing mode timing (3 minutes, 1 minute grace)
- **Consequence**: Settlement timing completely wrong, deadlines miscalculated

**Example Scenario**:
1. `app_config.testing_mode = 'false'` (normal mode)
2. `TESTING_MODE` env var = `'true'` (testing mode)
3. Settlement cron runs on normal schedule (Tuesday 12:00 ET)
4. But `bright-service` Edge Function uses `TESTING_MODE = true`
5. Function calculates 3-minute week + 1-minute grace instead of 7-day week + 24-hour grace
6. **Result**: Settlement logic completely broken

**Mitigation**:
- ✅ **CRITICAL**: Always update BOTH locations when changing mode
- ✅ Create a script to update both simultaneously
- ✅ Add validation to check for mismatches

---

### 🔴 **RISK 2: Both Cron Jobs Run Simultaneously During Transition**

**Problem**:
- Testing mode cron: `process-reconciliation-queue-testing` (every 1 minute)
- Normal mode cron: `process-reconciliation-queue-normal` (every 10 minutes)
- **Both are always scheduled** - they check mode at runtime

**Impact**:
- If `app_config.testing_mode` changes from `'true'` to `'false'`:
  - Testing cron (every 1 min) checks mode → sees normal mode → does nothing ✅
  - Normal cron (every 10 min) checks mode → sees normal mode → processes ✅
  - **But**: There's a window where both might process the same queue entries
  - **Race condition**: Two cron jobs processing same reconciliation request

**Example Scenario**:
1. `testing_mode = 'true'` → testing cron processes queue every 1 minute
2. User changes `testing_mode = 'false'` at 10:00:00
3. At 10:00:05, testing cron runs → checks mode → sees `false` → skips ✅
4. At 10:00:10, normal cron runs → checks mode → sees `false` → processes ✅
5. **But**: If testing cron was mid-processing at 10:00:00, it might complete after mode change
6. **Result**: Potential duplicate processing

**Mitigation**:
- ✅ Queue entries use `FOR UPDATE SKIP LOCKED` - prevents concurrent processing
- ✅ Status transitions are atomic (`pending` → `processing` → `completed`)
- ⚠️ **Still risky**: If mode changes mid-execution, behavior is unpredictable

---

### 🔴 **RISK 3: Settlement Cron Job Always Runs (No Mode Check)**

**Problem**:
- Settlement cron job `run-settlement-testing` runs **every 2 minutes** regardless of mode
- It always calls `call_settlement()` which calls `bright-service` with `x-manual-trigger: true`
- `bright-service` checks `TESTING_MODE` env var, not `app_config`

**Impact**:
- In normal mode:
  - Cron runs every 2 minutes (testing schedule)
  - Calls `bright-service` with `x-manual-trigger: true`
  - `bright-service` checks `TESTING_MODE` env var
  - If `TESTING_MODE = false`, function processes normally
  - **But**: Settlement runs every 2 minutes instead of weekly!
  - **Result**: Settlement runs too frequently in normal mode

**Example Scenario**:
1. `app_config.testing_mode = 'false'` (normal mode)
2. `TESTING_MODE` env var = `'false'` (normal mode)
3. Settlement cron `run-settlement-testing` runs every 2 minutes
4. Calls `bright-service` with `x-manual-trigger: true`
5. `bright-service` processes (no testing mode check fails because env var is false)
6. **Result**: Settlement runs every 2 minutes instead of weekly (Tuesday 12:00 ET)

**Mitigation**:
- ❌ **MISSING**: Settlement cron should check `app_config.testing_mode` before running
- ❌ **MISSING**: Need separate cron jobs for testing vs normal mode settlement
- ⚠️ **CRITICAL**: This will cause settlement to run too frequently in normal mode

---

### 🟡 **RISK 4: Reconciliation Queue Processing Frequency Mismatch**

**Problem**:
- Testing mode: Queue processed every 1 minute
- Normal mode: Queue processed every 10 minutes
- Both cron jobs exist and check mode at runtime

**Impact**:
- Transition from testing → normal:
  - Testing cron stops processing (sees normal mode)
  - Normal cron starts processing (sees normal mode)
  - **Gap**: Up to 10 minutes between processing (if transition happens right after normal cron runs)
  - **Result**: Reconciliation requests may wait up to 10 minutes instead of 1 minute

**Mitigation**:
- ✅ Acceptable delay for normal mode (10 minutes is reasonable)
- ✅ Queue entries are persistent, won't be lost
- ⚠️ **Minor risk**: Users might notice slower reconciliation in normal mode

---

### 🟡 **RISK 5: Active Commitments Created in Testing Mode**

**Problem**:
- Commitments created in testing mode have:
  - `week_end_timestamp` = creation_time + 3 minutes (precise timestamp)
  - `week_end_date` = UTC date of deadline
- When switching to normal mode:
  - New commitments use normal mode (7-day week)
  - Old commitments still have testing mode deadlines (3 minutes)

**Impact**:
- If mode switches while commitments are active:
  - Old commitments: 3-minute deadline (testing mode)
  - New commitments: 7-day deadline (normal mode)
  - Settlement logic must handle both types
  - **Result**: Mixed deadline types in same system

**Example Scenario**:
1. User creates commitment at 10:00:00 in testing mode
2. Deadline: 10:03:00 (3 minutes later)
3. At 10:01:00, admin switches to normal mode
4. User creates new commitment at 10:05:00
5. New deadline: Next Monday 12:00 ET (7 days later)
6. **Result**: Two commitments with different deadline types

**Mitigation**:
- ✅ Settlement logic already handles both `week_end_timestamp` and `week_end_date`
- ✅ `isGracePeriodExpired()` checks both types
- ✅ Old commitments will settle based on their original deadline type
- ⚠️ **Minor risk**: Confusing for debugging, but functionally safe

---

### 🟡 **RISK 6: Edge Function Timing Constants Loaded at Module Init**

**Problem**:
- `_shared/timing.ts` loads `TESTING_MODE` at module initialization:
  ```typescript
  export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
  ```
- This is evaluated **once** when Edge Function starts
- If env var changes, Edge Function must be **redeployed** to pick up change

**Impact**:
- Changing `TESTING_MODE` env var requires:
  1. Update Edge Function secret
  2. Redeploy Edge Function (or wait for cold start)
  3. Update `app_config.testing_mode`
- **Gap**: Edge Functions may use old mode until redeployed
- **Result**: Temporary inconsistency between Edge Functions and database

**Example Scenario**:
1. `TESTING_MODE` env var = `'true'`, `app_config.testing_mode = 'true'`
2. Admin updates `app_config.testing_mode = 'false'` (normal mode)
3. Cron jobs immediately see normal mode ✅
4. But Edge Functions still have `TESTING_MODE = true` in memory ❌
5. **Result**: Cron jobs use normal mode, Edge Functions use testing mode
6. **Consequence**: Timing calculations are wrong

**Mitigation**:
- ✅ Edge Functions can check `app_config` at runtime (some do this)
- ⚠️ **Risk**: Not all Edge Functions check `app_config`, some use constant
- ⚠️ **Solution**: All Edge Functions should check `app_config` at runtime, not use constant

---

### 🟢 **RISK 7: Reconciliation Queue Entries Stuck in Processing**

**Problem**:
- Queue entries can be stuck in `processing` status if:
  - `quick-handler` fails silently
  - Network timeout
  - Mode changes mid-processing

**Impact**:
- During transition:
  - Entry marked `processing` by testing cron
  - Mode switches to normal
  - Normal cron sees entry as `processing` (not `pending`)
  - Entry might be stuck until retry logic kicks in (> 5 minutes)

**Mitigation**:
- ✅ Retry logic exists: `processing` entries > 5 minutes are retried
- ✅ Both cron jobs check for stale `processing` entries
- ⚠️ **Minor risk**: Slight delay in processing during transition

---

## Summary of Risks

| Risk | Severity | Likelihood | Mitigation Status |
|------|----------|------------|-------------------|
| Configuration mismatch (app_config vs env var) | 🔴 Critical | Medium | ⚠️ Manual process required |
| Both cron jobs run simultaneously | 🔴 Critical | Low | ✅ Handled by SKIP LOCKED |
| Settlement cron always runs (no mode check) | 🔴 Critical | High | ❌ **NOT MITIGATED** |
| Reconciliation frequency mismatch | 🟡 Medium | High | ✅ Acceptable delay |
| Active commitments with mixed deadlines | 🟡 Medium | Medium | ✅ Handled by logic |
| Edge Function timing constants | 🟡 Medium | Medium | ⚠️ Requires redeploy |
| Stuck queue entries | 🟢 Low | Low | ✅ Retry logic exists |

---

## Recommended Mitigation Steps

### 1. **CRITICAL: Fix Settlement Cron Job**

**Problem**: Settlement cron `run-settlement-testing` runs every 2 minutes regardless of mode.

**Solution**:
- Add mode check to `call_settlement()` function:
  ```sql
  -- Check testing_mode from app_config
  SELECT COALESCE(
    (SELECT CASE WHEN value = 'true' THEN true ELSE false END 
     FROM public.app_config WHERE key = 'testing_mode'),
    false
  ) INTO testing_mode;
  
  -- Only proceed if in testing mode
  IF NOT testing_mode THEN
    RAISE NOTICE 'Settlement cron skipped - not in testing mode';
    RETURN;
  END IF;
  ```

- **OR** create separate cron jobs:
  - `run-settlement-testing`: Every 2 minutes, checks mode, only runs if testing
  - `run-settlement-normal`: Weekly (Tuesday 12:00 ET), checks mode, only runs if normal

### 2. **Create Mode Transition Script**

**Purpose**: Update both `app_config` and Edge Function secrets atomically.

**Script should**:
1. Update `app_config.testing_mode`
2. Update `TESTING_MODE` Edge Function secret
3. Verify both are in sync
4. Log the transition

### 3. **Add Mode Validation**

**Purpose**: Detect configuration mismatches.

**Implementation**:
- Create `rpc_validate_mode_config()` function
- Checks `app_config.testing_mode` vs `TESTING_MODE` env var (via Edge Function call)
- Returns mismatch warnings
- Can be called before/after mode transitions

### 4. **Update Edge Functions to Check app_config**

**Purpose**: Make Edge Functions use runtime mode check instead of constant.

**Implementation**:
- Update `bright-service` to check `app_config` at runtime
- Pass `isTestingMode` parameter to timing functions
- Remove dependency on `TESTING_MODE` constant

---

## Transition Checklist

Before switching from testing → normal mode:

- [ ] Verify `app_config.testing_mode = 'false'`
- [ ] Verify `TESTING_MODE` env var = `'false'` in all Edge Functions
- [ ] Verify settlement cron has mode check (or create normal mode cron)
- [ ] Check for active commitments with testing mode deadlines
- [ ] Verify reconciliation queue is empty or processing
- [ ] Test mode validation function
- [ ] Monitor cron job logs after transition
- [ ] Verify settlement runs on correct schedule (weekly, not every 2 minutes)

---

## Conclusion

**Highest Risk**: Settlement cron job running every 2 minutes in normal mode (Risk #3)

**Most Likely Issue**: Configuration mismatch between `app_config` and env vars (Risk #1)

**Recommended Action**: Fix settlement cron job mode check before transitioning to normal mode.

