# Phase 1 Verification Strategy

**Phase**: Phase 1 - Backend Testing Mode Infrastructure  
**Purpose**: Comprehensive verification that all Phase 1 components work together correctly

---

## Phase 1 Components Summary

### ✅ Step 1.1: Create Shared Timing Helper
- File: `supabase/functions/_shared/timing.ts`
- Exports: `TESTING_MODE`, `WEEK_DURATION_MS`, `GRACE_PERIOD_MS`, `getNextDeadline()`, `getGraceDeadline()`

### ✅ Step 1.2: Update Settlement Function
- File: `supabase/functions/bright-service/run-weekly-settlement.ts`
- Uses timing helper for grace deadline calculation
- Adds cron skip logic (skips if `TESTING_MODE=true` without manual trigger)
- Fixes `isGracePeriodExpired()` bug

### ✅ Step 1.3: Update Commitment Creation
- File: `supabase/functions/super-service/index.ts`
- Overrides client deadline with compressed deadline in testing mode
- Uses timing helper for deadline calculation

### ✅ Step 1.4: Fix Grace Period Bug
- Already completed in Step 1.2 (uses timing helper)

---

## Verification Approach

### Option 1: End-to-End Integration Test (Recommended)

**Purpose**: Test the complete flow from commitment creation to settlement

**Test Flow**:
1. **Setup**: Create test user, set `TESTING_MODE=true`
2. **Create Commitment**: Call `super-service` Edge Function
3. **Verify Commitment**: Check database for compressed deadline
4. **Wait for Grace Period**: Wait 1 minute (compressed grace period)
5. **Trigger Settlement**: Call `bright-service/run-weekly-settlement` with manual trigger
6. **Verify Settlement**: Check database for settlement results

**What to Verify**:
- ✅ Commitment created with deadline ~3 minutes from now
- ✅ Grace period expires after 1 minute
- ✅ Settlement processes correctly
- ✅ Cron skip works (settlement skipped without manual trigger)

---

### Option 2: Component Integration Test

**Purpose**: Test each component individually but verify they work together

**Test Cases**:

1. **Timing Helper Integration**
   - Verify all Edge Functions can import timing helper
   - Verify constants are correct in both modes
   - Verify functions return correct dates

2. **Commitment Creation Flow**
   - Normal mode: Uses client deadline
   - Testing mode: Uses compressed deadline
   - Database: Deadline stored correctly

3. **Settlement Flow**
   - Normal mode: Grace period is 24 hours
   - Testing mode: Grace period is 1 minute
   - Cron skip: Works correctly

4. **End-to-End Flow**
   - Create commitment in testing mode
   - Wait for grace period
   - Trigger settlement
   - Verify results

---

### Option 3: Manual Verification Script

**Purpose**: Quick manual checks of all Phase 1 components

**Manual Checks**:

1. **Timing Helper**
   ```bash
   TESTING_MODE=true deno run --allow-env supabase/tests/test_timing_manual.ts
   ```

2. **Commitment Creation**
   - Deploy with `TESTING_MODE=true`
   - Create commitment via Edge Function
   - Check database: `SELECT week_end_date FROM commitments WHERE ...`

3. **Settlement**
   - Wait 1 minute after commitment deadline
   - Call settlement with manual trigger
   - Check database: `SELECT * FROM user_week_penalties WHERE ...`

4. **Cron Skip**
   - Call settlement WITHOUT manual trigger
   - Should return "Settlement skipped" message

---

## Recommended Verification Strategy

**Use Option 1 (End-to-End Integration Test)** because:
- ✅ Tests complete flow
- ✅ Verifies all components work together
- ✅ Most realistic test scenario
- ✅ Catches integration issues

**Then use Option 3 (Manual Verification)** for quick checks during development.

---

## Detailed Test Script

### Test 1: Timing Helper Works in All Contexts

**File**: `supabase/tests/test_phase1_timing_helper.ts`

**Purpose**: Verify timing helper can be imported and used by all Edge Functions

**Test Cases**:
1. Import from settlement function context
2. Import from commitment creation context
3. Verify constants are correct
4. Verify functions work correctly

---

### Test 2: Commitment Creation with Compressed Deadline

**File**: `supabase/tests/test_phase1_commitment_creation.ts`

**Purpose**: Verify commitment creation uses compressed deadline in testing mode

**Test Cases**:
1. **Normal Mode**:
   - Create commitment
   - Verify deadline is client's deadline (next Monday)
   - Verify database record is correct

2. **Testing Mode**:
   - Set `TESTING_MODE=true`
   - Create commitment
   - Verify deadline is ~3 minutes from now
   - Verify database record is correct
   - Verify client's deadline is ignored

---

### Test 3: Settlement with Compressed Timeline

**File**: `supabase/tests/test_phase1_settlement.ts`

**Purpose**: Verify settlement works with compressed timeline

**Test Cases**:
1. **Create Commitment** (testing mode)
   - Deadline is ~3 minutes from now

2. **Wait for Grace Period** (1 minute)
   - Grace period expires 1 minute after deadline

3. **Trigger Settlement** (with manual trigger)
   - Settlement processes correctly
   - Charges are correct
   - Database records are correct

4. **Verify Cron Skip**
   - Call settlement WITHOUT manual trigger
   - Should skip (return "Settlement skipped" message)

---

### Test 4: End-to-End Flow

**File**: `supabase/tests/test_phase1_end_to_end.ts`

**Purpose**: Test complete flow from commitment to settlement

**Test Flow**:
1. **Setup**
   - Create test user
   - Set `TESTING_MODE=true`
   - Clear any existing test data

2. **Create Commitment**
   - Call `super-service` Edge Function
   - Verify commitment created with compressed deadline
   - Record commitment ID and deadline

3. **Wait for Deadline**
   - Wait until deadline passes (or simulate with time override)
   - Verify commitment is ready for settlement

4. **Wait for Grace Period**
   - Wait 1 minute after deadline (compressed grace period)
   - Verify grace period has expired

5. **Trigger Settlement**
   - Call `bright-service/run-weekly-settlement` with manual trigger
   - Verify settlement processes
   - Verify charges are correct
   - Verify database records are correct

6. **Verify Cron Skip**
   - Call settlement WITHOUT manual trigger
   - Verify it skips correctly

7. **Cleanup**
   - Remove test data

---

## Verification Checklist

After running all tests, verify:

### Timing Helper (Step 1.1)
- [ ] File exists and exports correctly
- [ ] `TESTING_MODE` reads from environment variable
- [ ] Constants have correct values in both modes
- [ ] Functions return correct dates in both modes
- [ ] Can be imported by all Edge Functions

### Settlement Function (Step 1.2)
- [ ] Imports timing helper correctly
- [ ] Uses `getGraceDeadline()` for grace deadline
- [ ] `isGracePeriodExpired()` uses timing helper
- [ ] Cron skip logic works (skips without manual trigger)
- [ ] Manual trigger works (processes with `x-manual-trigger: true`)
- [ ] Normal mode still works (no regressions)

### Commitment Creation (Step 1.3)
- [ ] Imports timing helper correctly
- [ ] Testing mode: Uses compressed deadline
- [ ] Normal mode: Uses client's deadline
- [ ] Deadline is formatted correctly (`YYYY-MM-DD`)
- [ ] Database records show correct deadline

### Integration
- [ ] Commitment creation → Settlement flow works
- [ ] Compressed timeline works end-to-end
- [ ] Normal mode still works (no regressions)
- [ ] Cron skip prevents accidental runs
- [ ] Manual trigger allows controlled testing

---

## Success Criteria

✅ **Phase 1 is complete when**:

1. ✅ All components work individually
2. ✅ All components work together
3. ✅ Testing mode works correctly (compressed timeline)
4. ✅ Normal mode still works (no regressions)
5. ✅ Cron skip logic works
6. ✅ Manual trigger works
7. ✅ End-to-end flow works
8. ✅ Database records are correct
9. ✅ No TypeScript errors
10. ✅ All tests pass

---

## Test Execution Plan

### Phase 1: Individual Component Tests
1. Run `test_phase1_timing_helper.ts`
2. Run `test_phase1_commitment_creation.ts`
3. Run `test_phase1_settlement.ts`

### Phase 2: Integration Test
4. Run `test_phase1_end_to_end.ts`

### Phase 3: Manual Verification
5. Deploy Edge Functions with `TESTING_MODE=true`
6. Create commitment via iOS app or API
7. Verify database records
8. Wait for grace period
9. Trigger settlement manually
10. Verify results

---

## Quick Verification Commands

```bash
# Test 1: Timing Helper
deno run --allow-env supabase/tests/test_timing_manual.ts

# Test 2: Step 1.2 (Settlement)
deno run --allow-env supabase/tests/test_step_1_2_timing.ts

# Test 3: Step 1.3 (Commitment)
deno run --allow-env supabase/tests/test_step_1_3_commitment_deadline.ts

# Test 4: End-to-End (requires deployment)
# (Use test_phase1_end_to_end.ts)
```

---

## Edge Cases to Test

1. **TESTING_MODE changes mid-test**
   - Should use mode at module load time
   - Components should be consistent

2. **Multiple commitments in testing mode**
   - Each should have compressed deadline
   - Settlement should handle all

3. **Settlement called before grace period**
   - Should skip (grace not expired)
   - Should process after grace period

4. **Settlement called without manual trigger**
   - Should skip in testing mode
   - Should process in normal mode (cron)

5. **Normal mode regression**
   - Verify normal mode still works
   - Verify no changes to normal behavior

---

## Known Limitations

1. **Module Load Time**: `TESTING_MODE` is evaluated at module load time, so changing it mid-execution won't work. This is by design.

2. **Deployment Required**: Full end-to-end testing requires Edge Functions to be deployed with `TESTING_MODE=true`.

3. **Time-Dependent**: Some tests require waiting for actual time to pass (1 minute grace period, 3 minute deadline).

---

**End of Verification Strategy**


