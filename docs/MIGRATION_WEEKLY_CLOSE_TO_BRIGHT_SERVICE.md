# Migration Plan: weekly-close → bright-service

**Status**: 📋 Planning  
**Priority**: High  
**Date**: 2026-01-11  
**Goal**: Consolidate settlement logic into single function with minimal moving parts

---

## Executive Summary

Migrate from the legacy `weekly-close` function to `bright-service`, creating a unified settlement system that works seamlessly in both testing and normal modes with minimal code duplication.

**Key Benefits:**
- Single settlement function (no duplicate logic)
- Shared timing logic via `_shared/timing.ts`
- Easy mode switching (just `TESTING_MODE` flag)
- Minimal moving parts when toggling modes
- All fixes and improvements in one place

**Migration Safety Assessment:**
- ✅ **Safe to migrate** - Only 2 production dependencies found
- ✅ **No hidden dependencies** - Comprehensive search completed
- ✅ **Straightforward updates** - Both dependencies are simple URL changes
- ✅ **No breaking changes** - iOS app calls `admin-close-week-now` (which will be updated)
- ✅ **Backward compatible option** - Can keep `call_weekly_close()` function name

---

## Current State

### Functions

1. **`weekly-close`** (Legacy - Normal Mode)
   - Aggregates `daily_usage` into `user_week_penalties`
   - Updates `weekly_pools.total_penalty_cents`
   - Handles revoked monitoring estimation
   - Charges users (simple: charges `total_penalty_cents` directly)
   - Closes `weekly_pools` (sets `status = "closed"`)
   - **Missing**: Grace period logic, actual vs worst case, zero-amount handling, below-minimum handling

2. **`bright-service`** (New - Testing Mode)
   - Grace period checks (uses `_shared/timing.ts`)
   - Actual vs worst case charging
   - Zero-amount handling
   - Below-minimum handling
   - Synced usage detection
   - PaymentIntent creation
   - **Missing**: Revoked monitoring estimation, closing `weekly_pools`

3. **`auto-settlement-checker`** (Testing Mode Only)
   - Runs every minute via `pg_cron`
   - Finds commitments with expired grace periods
   - Calls `bright-service` to trigger settlement
   - Exits immediately if `TESTING_MODE=false` (safe for production)

4. **`testing-command-runner`** (Testing Tools)
   - Dashboard/testing tools
   - Separate from core settlement flow
   - Only works if `TESTING_MODE=true`

### Cron Jobs

- **Normal Mode**: `call_weekly_close()` → `weekly-close` (weekly, Monday 12:00 ET)
- **Testing Mode**: `auto-settlement-checker` (every minute)

### Dependencies on `weekly-close` (Verified)

**Production Dependencies (Must Update):**

1. **`call_weekly_close()` RPC Function**
   - Location: `supabase/remote_rpcs/call_weekly_close.sql`
   - Called by: `pg_cron` job (`weekly-close-staging` or `weekly-close-production`)
   - Schedule: Monday 17:00 UTC (12:00 PM EST)
   - Action Required: Update to call `bright-service` instead of `weekly-close`

2. **`admin-close-week-now` Edge Function**
   - Location: `supabase/functions/admin-close-week-now/index.ts`
   - Calls: `weekly-close` directly (line 61)
   - Used by: iOS app `BackendClient.swift` → `callAdminCloseWeekNow()`
   - Purpose: Manual trigger for test users only (`is_test_user = true`)
   - Action Required: Update to call `bright-service` instead of `weekly-close`

**Non-Production Dependencies (Update for Completeness):**

3. **`test_weekly_close.ts`**
   - Location: `supabase/tests/test_weekly_close.ts`
   - Purpose: Tests `weekly-close` behavior
   - Action Required: Update tests to use `bright-service` or mark as deprecated

4. **Cron Job Setup Scripts**
   - Location: `scripts/setup_cron_jobs.sh`
   - Purpose: Sets up `pg_cron` jobs
   - Action Required: Update to reference `bright-service` instead of `call_weekly_close()`

5. **Documentation**
   - Multiple docs reference `weekly-close` (status, plans, fixes)
   - Action Required: Update after migration

**Verified: No Other Dependencies**
- ✅ No database triggers call `weekly-close` or `call_weekly_close()`
- ✅ No other Edge Functions call `weekly-close` (checked `stripe-webhook`, `billing-status`, etc.)
- ✅ No external webhooks or APIs call `weekly-close`
- ✅ iOS app does not call `weekly-close` directly (only via `admin-close-week-now`)
- ✅ No environment variables or secrets reference `weekly-close`
- ✅ No scheduled jobs other than the `pg_cron` job mentioned above

### Shared Logic

- **`_shared/timing.ts`**: Already provides mode-aware timing helpers
  - `TESTING_MODE`: Single source of truth
  - `WEEK_DURATION_MS`: 3 minutes vs 7 days
  - `GRACE_PERIOD_MS`: 1 minute vs 24 hours
  - `getNextDeadline()`: Handles both modes
  - `getGraceDeadline()`: Handles both modes

---

## Target State

### Single Settlement Function: `bright-service`

**One function handles both modes:**

1. **Core Settlement Logic (Shared)**
   - ✅ Grace period checks (uses `_shared/timing.ts` for mode-specific timing)
   - ✅ Actual vs worst case charging
   - ✅ Zero-amount handling
   - ✅ Below-minimum handling
   - ✅ Synced usage detection
   - ✅ PaymentIntent creation and recording
   - ✅ Revoked monitoring estimation (NEW - from `weekly-close`)
   - ✅ Close `weekly_pools` (NEW - from `weekly-close`)

2. **Mode-Specific Behavior (via `TESTING_MODE` flag)**
   - Week target resolution: Testing mode uses today's UTC date; normal mode calculates previous Monday
   - Grace period calculation: Uses `getGraceDeadline()` from `_shared/timing.ts` (1 minute vs 24 hours)
   - Deadline calculation: Uses `getNextDeadline()` from `_shared/timing.ts` (3 minutes vs 7 days)

### Cron Jobs (Minimal, Mode-Specific)

**Normal Mode:**
- One cron job: Calls `bright-service` once per week
  - Schedule: Tuesday 12:00 ET (after grace period expires)
  - Calls: `POST /functions/v1/bright-service` with empty body (auto-determines week)
  - No `x-manual-trigger` header needed (normal mode doesn't check it)

**Testing Mode:**
- One cron job: Calls `auto-settlement-checker` every minute
  - Schedule: Every minute (`* * * * *`)
  - Calls: `POST /functions/v1/auto-settlement-checker` (which then calls `bright-service`)
  - `auto-settlement-checker` exits immediately if `TESTING_MODE=false` (safe for production)

### Testing Infrastructure (Separate, Optional)

**`testing-command-runner`:**
- Purpose: Dashboard/testing tools (verify results, trigger settlement manually, delete test user)
- Mode: Only works if `TESTING_MODE=true` (exits early otherwise)
- Status: Keep separate (not part of core settlement flow)

### Shared Logic (Already in Place)

**`_shared/timing.ts`:**
- `TESTING_MODE`: Single source of truth
- `WEEK_DURATION_MS`: 3 minutes vs 7 days
- `GRACE_PERIOD_MS`: 1 minute vs 24 hours
- `getNextDeadline()`: Handles both modes
- `getGraceDeadline()`: Handles both modes

**`bright-service`:**
- All settlement logic uses `_shared/timing.ts` helpers
- Mode detection via `TESTING_MODE` constant
- Week resolution adapts to mode automatically

---

## Migration Steps

### Phase 1: Enhance `bright-service` (Add Missing Features)

**Step 1.1: Add Revoked Monitoring Estimation**
- Copy logic from `weekly-close/index.ts` lines 53-100
- Add to `bright-service` before settlement loop
- Logic:
  - Find commitments with `monitoring_status = 'revoked'` for target week
  - For each revoked commitment, create estimated `daily_usage` entries
  - Estimation rule: `used_minutes = limit_minutes * 2`, `exceeded_minutes = limit_minutes`
  - Only create entries if they don't already exist

**Step 1.2: Add Close `weekly_pools`**
- Copy logic from `weekly-close/index.ts` lines 337-345
- Add to `bright-service` after settlement loop completes
- Logic:
  - Update `weekly_pools` table
  - Set `status = 'closed'`
  - Set `closed_at = NOW()`
  - Filter by `week_start_date = target.weekEndDate`

**Step 1.3: Remove Duplicate Aggregation Logic**
- **DO NOT** add aggregation logic from `weekly-close`
- `rpc_sync_daily_usage` already handles:
  - Aggregating `daily_usage` into `user_week_penalties`
  - Updating `weekly_pools.total_penalty_cents`
- `bright-service` should assume aggregation is already done

### Phase 2: Update Dependencies

**Step 2.1: Update `call_weekly_close()` RPC Function**
- File: `supabase/remote_rpcs/call_weekly_close.sql`
- Change: Update URL from `weekly-close` to `bright-service`
- Before: `'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/weekly-close'`
- After: `'https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/bright-service'`
- **Note**: This function is called by the production cron job, so updating it will automatically route cron calls to `bright-service`
- **Important**: Keep the function name `call_weekly_close()` for backward compatibility with existing cron jobs
- **Testing**: After update, manually test: `SELECT public.call_weekly_close();` to verify it calls `bright-service`

**Step 2.2: Update `admin-close-week-now` Edge Function**
- File: `supabase/functions/admin-close-week-now/index.ts`
- Change: Update URL from `weekly-close` to `bright-service` (line 61)
- Before: `const weeklyCloseUrl = \`${SUPABASE_URL}/functions/v1/weekly-close\`;`
- After: `const weeklyCloseUrl = \`${SUPABASE_URL}/functions/v1/bright-service\`;`
- **Note**: Variable name can stay as `weeklyCloseUrl` for now (cosmetic only)
- **Important**: This is used by iOS app for manual testing, so must work correctly
- **iOS App Impact**: ✅ **No iOS code changes needed** - iOS app calls `admin-close-week-now`, which will now route to `bright-service` automatically
- **Testing**: After update, test from iOS app using `callAdminCloseWeekNow()` method
- **Deployment**: Deploy updated function: `supabase functions deploy admin-close-week-now`

**Step 2.3: Create New Normal Mode Cron Job**
- Create migration: `setup_bright_service_cron.sql`
- Schedule: Tuesday 12:00 ET (after grace period expires)
- Calls: `POST /functions/v1/bright-service` with empty body
- Uses `pg_net.http_post` with service role key
- **Alternative**: Update existing cron job to call `bright-service` directly (if not using `call_weekly_close()`)
- **Note**: If using `call_weekly_close()` wrapper, Step 2.1 handles this automatically

**Step 2.4: Update Cron Job Setup Scripts**
- File: `scripts/setup_cron_jobs.sh`
- Change: Update comments and references from `weekly-close` to `bright-service`
- Update: Job name can stay as `weekly-close-$env` for backward compatibility, or change to `bright-service-$env`
- **Note**: Script functionality remains the same, just updates references

**Step 2.5: Verify Testing Mode Cron Job**
- Ensure `auto-settlement-checker` cron job is active
- Verify it calls `bright-service` correctly
- Confirm it exits early if `TESTING_MODE=false`

### Phase 3: Testing

**Step 3.1: Test in Testing Mode**
- Set `TESTING_MODE=true`
- Create test commitment
- Verify revoked monitoring estimation works
- Verify settlement triggers automatically
- Verify `weekly_pools` closes after settlement
- Verify all settlement logic (actual vs worst case, zero-amount, below-minimum)

**Step 3.2: Test in Normal Mode**
- Set `TESTING_MODE=false`
- Create test commitment (or use existing)
- Verify week target resolution (previous Monday)
- Verify grace period calculation (24 hours)
- Verify settlement logic works correctly
- Verify `weekly_pools` closes after settlement
- **Test `call_weekly_close()` RPC**: Manually call `SELECT public.call_weekly_close();` and verify it triggers `bright-service`
- **Test `admin-close-week-now`**: Call from iOS app and verify it triggers `bright-service`

**Step 3.3: Test Mode Switching**
- Toggle `TESTING_MODE` between `true` and `false`
- Verify cron jobs adapt correctly
- Verify timing calculations change appropriately
- Verify no errors or conflicts

### Phase 4: Cleanup

**Step 4.1: Remove Legacy Function**
- Delete `supabase/functions/weekly-close/` directory
- Remove from `supabase/config.toml` if present

**Step 4.2: Update or Remove Legacy RPC**
- **Option A (Recommended)**: Keep `call_weekly_close()` function but ensure it calls `bright-service`
  - This maintains backward compatibility with existing cron jobs
  - Function name stays the same, but implementation routes to `bright-service`
- **Option B**: Remove `call_weekly_close()` function entirely
  - Requires updating all cron jobs to call `bright-service` directly
  - More disruptive but cleaner long-term
- Remove any references to `call_weekly_close()` in migrations (if choosing Option B)

**Step 4.3: Remove Legacy Cron Job**
- Create migration to unschedule old `weekly-close` cron job (if it exists)
- **Note**: If using `call_weekly_close()` wrapper, the cron job can stay (it now calls `bright-service`)
- Update cron job name from `weekly-close-$env` to `bright-service-$env` (optional, for clarity)

**Step 4.4: Update Test Files**
- Update `supabase/tests/test_weekly_close.ts` to test `bright-service` instead
- Or mark test file as deprecated and create new `test_bright_service.ts`
- Ensure all test cases still pass with `bright-service`

**Step 4.5: Update Documentation**
- Update any docs referencing `weekly-close`
- Document new cron job setup
- Update architecture diagrams
- Update `scripts/setup_cron_jobs.sh` comments
- Update any README or setup guides

**Step 4.6: Optional iOS App Comment Updates (Cosmetic Only)**
- **File**: `payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/BackendClient.swift`
- **Line 274**: Update comment from `///   - weekly-close` to `///   - bright-service (replaces weekly-close)`
- **Line 1181**: Update comment from `// Note: result field is ignored since we don't need to decode the nested weekly-close response` to `// Note: result field is ignored since we don't need to decode the nested bright-service response`
- **Note**: These are **optional cosmetic updates only** - iOS app functionality works without these changes
- **Reason**: iOS app calls `admin-close-week-now` (not `weekly-close` directly), so no code changes needed

---

## Testing Considerations

### Testing Mode Testing

1. **Revoked Monitoring Estimation**
   - Create commitment with monitoring
   - Revoke monitoring mid-week
   - Verify estimated `daily_usage` entries are created
   - Verify they're included in settlement

2. **Pool Closing**
   - Create commitment and trigger settlement
   - Verify `weekly_pools.status = 'closed'`
   - Verify `weekly_pools.closed_at` is set

3. **Settlement Logic**
   - Test all existing test cases (actual, worst case, zero-amount, below-minimum)
   - Verify all still work after migration

### Normal Mode Testing

1. **Week Target Resolution**
   - Verify it correctly identifies previous Monday
   - Test edge cases (Monday before noon, Monday after noon, other days)

2. **Grace Period Calculation**
   - Verify 24-hour grace period is used
   - Verify grace deadline is Tuesday 12:00 ET

3. **Cron Job Execution**
   - Verify cron job runs on Tuesday 12:00 ET
   - Verify it calls `bright-service` correctly
   - Verify settlement completes successfully

### Mode Switching Testing

1. **Toggle `TESTING_MODE`**
   - Switch from `false` to `true`
   - Verify `auto-settlement-checker` starts working
   - Verify timing calculations change
   - Switch back to `false`
   - Verify `auto-settlement-checker` exits early
   - Verify normal cron job works

---

## Rollback Plan

If issues arise during migration:

1. **Immediate Rollback**
   - Re-enable `weekly-close` cron job
   - Disable `bright-service` cron job
   - Set `TESTING_MODE` back to original value

2. **Partial Rollback**
   - Keep `bright-service` enhancements
   - Revert cron job changes
   - Run both functions in parallel temporarily

3. **Full Rollback**
   - Restore `weekly-close` function from Git
   - Restore `call_weekly_close()` RPC
   - Remove `bright-service` enhancements
   - Revert all migrations

---

## Checklist

### Pre-Migration
- [ ] Review current `weekly-close` logic
- [ ] Review current `bright-service` logic
- [ ] Identify all differences
- [ ] Document current cron job setup
- [ ] Backup current state (Git commit)

### Phase 1: Enhance `bright-service`
- [ ] Add revoked monitoring estimation logic
- [ ] Add close `weekly_pools` logic
- [ ] Verify no duplicate aggregation logic
- [ ] Test in testing mode
- [ ] Test in normal mode (with `TESTING_MODE=false`)

### Phase 2: Update Dependencies
- [ ] Update `call_weekly_close()` RPC to call `bright-service`
- [ ] Update `admin-close-week-now` Edge Function to call `bright-service`
- [ ] Test `admin-close-week-now` from iOS app
- [ ] Create new normal mode cron job migration (or update existing)
- [ ] Update cron job setup scripts
- [ ] Test cron job in normal mode
- [ ] Verify testing mode cron job still works
- [ ] Test mode switching

### Phase 3: Testing
- [ ] Test revoked monitoring estimation
- [ ] Test pool closing
- [ ] Test all settlement logic
- [ ] Test week target resolution
- [ ] Test grace period calculation
- [ ] Test cron job execution
- [ ] Test mode switching

### Phase 4: Cleanup
- [ ] Delete `weekly-close` function
- [ ] Decide: Keep or remove `call_weekly_close()` RPC (see Step 4.2)
- [ ] Update or remove old cron job
- [ ] Update test files (`test_weekly_close.ts`)
- [ ] Update documentation
- [ ] Update cron job setup scripts
- [ ] Optional: Update iOS app comments (cosmetic only, not required)
- [ ] Final Git commit

### Post-Migration
- [ ] Monitor logs for errors
- [ ] Verify settlement runs correctly
- [ ] Verify pool closing works
- [ ] Verify mode switching works
- [ ] Update team documentation

---

## Architecture After Migration

```
┌─────────────────────────────────────────────────────────────┐
│                    TESTING_MODE Flag                        │
│              (Single source of truth)                      │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              _shared/timing.ts                               │
│  - WEEK_DURATION_MS (3 min vs 7 days)                       │
│  - GRACE_PERIOD_MS (1 min vs 24 hours)                       │
│  - getNextDeadline()                                        │
│  - getGraceDeadline()                                       │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              bright-service (SINGLE FUNCTION)                │
│                                                              │
│  Shared Logic (both modes):                                 │
│  ✓ Grace period checks                                      │
│  ✓ Actual vs worst case                                     │
│  ✓ Zero-amount handling                                     │
│  ✓ Below-minimum handling                                   │
│  ✓ PaymentIntent creation                                   │
│  ✓ Revoked monitoring estimation                            │
│  ✓ Close weekly_pools                                       │
│                                                              │
│  Mode-Specific (via TESTING_MODE):                         │
│  • Week target resolution                                   │
│  • Deadline calculation                                     │
│  • Grace period timing                                       │
└─────────────────────────────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌──────────────────┐          ┌──────────────────┐
│  Normal Mode     │          │  Testing Mode     │
│  Cron Job        │          │  Cron Job         │
│                  │          │                   │
│  Schedule:       │          │  Schedule:        │
│  Tue 12:00 ET    │          │  Every minute     │
│  (weekly)        │          │                   │
│                  │          │  Calls:           │
│  Calls:          │          │  auto-settlement- │
│  bright-service  │          │  checker          │
│  directly        │          │  (which calls     │
│                  │          │  bright-service)  │
└──────────────────┘          └──────────────────┘
```

---

## Benefits After Migration

1. **Single Settlement Function**: All logic in `bright-service` (no duplication)
2. **Shared Timing Logic**: `_shared/timing.ts` handles all mode differences
3. **Minimal Moving Parts**: Only cron job schedule differs between modes
4. **Safe Mode Switching**: `TESTING_MODE` flag controls everything
5. **No Duplicate Code**: Removed `weekly-close` entirely
6. **Easy Maintenance**: One function to update for settlement logic

---

## Notes

- **Aggregation Logic**: `rpc_sync_daily_usage` already handles aggregation, so `bright-service` should NOT duplicate this
- **Pool Updates**: `rpc_sync_daily_usage` already updates `weekly_pools.total_penalty_cents`, so `bright-service` only needs to close it
- **Mode Switching**: Changing `TESTING_MODE` secret is all that's needed to switch modes
- **Cron Jobs**: Normal mode cron job can be tested manually before going live
- **Testing**: All existing test cases should still pass after migration
- **Backward Compatibility**: Consider keeping `call_weekly_close()` function name but routing to `bright-service` to avoid breaking existing cron jobs
- **iOS App**: ✅ **No code changes needed** - iOS app calls `admin-close-week-now` (not `weekly-close` directly), so updating `admin-close-week-now` is sufficient. Optional comment updates only.
- **Dependency Safety**: Only 2 production dependencies found - both straightforward to update
- **iOS App Testing**: After updating `admin-close-week-now`, test from iOS app using `callAdminCloseWeekNow()` method to verify it works correctly

---

## Related Documents

- `SETTLEMENT_TESTING_IMPLEMENTATION_PLAN.md`: Testing infrastructure setup
- `SETTLEMENT_TESTING_STRATEGY.md`: Settlement testing strategy
- `SETTLEMENT_FLOW_MERMAID.md`: Settlement flow diagrams

---

---

## Quick Reference: Files to Update

### Must Update (Production Dependencies)

1. **`supabase/remote_rpcs/call_weekly_close.sql`**
   - Line 17: Change URL from `weekly-close` to `bright-service`
   - Function name stays the same for backward compatibility

2. **`supabase/functions/admin-close-week-now/index.ts`**
   - Line 61: Change URL from `weekly-close` to `bright-service`
   - Variable name can stay the same

### Should Update (Non-Production)

3. **`supabase/tests/test_weekly_close.ts`**
   - Update to test `bright-service` instead
   - Or create new `test_bright_service.ts`

4. **`scripts/setup_cron_jobs.sh`**
   - Update comments and references
   - Job name can stay the same or change to `bright-service-$env`

### Will Delete (After Migration Complete)

5. **`supabase/functions/weekly-close/`** (entire directory)
6. **`supabase/remote_rpcs/call_weekly_close.sql`** (if choosing Option B in Step 4.2)

### No Code Changes Needed

- ✅ **iOS app (`BackendClient.swift`)** - calls `admin-close-week-now` which will be updated to call `bright-service`
  - **No functional code changes required**
  - **Optional**: Update comments (lines 274, 1181) for clarity
  - iOS app will work automatically after `admin-close-week-now` is updated
- ✅ `stripe-webhook` - does not call `weekly-close`
- ✅ Other Edge Functions - none call `weekly-close`
- ✅ Database triggers - none call `weekly-close`
- ✅ External APIs - none call `weekly-close`

---

**Last Updated**: 2026-01-11  
**Status**: Ready for implementation  
**Dependency Analysis**: Complete - Only 2 production dependencies found, both safe to update

