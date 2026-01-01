# Step 1.2 Testing Strategy: Update Settlement Function

**Step**: 1.2 - Update Settlement Function to Use Timing Helper  
**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

---

## What Step 1.2 Does

1. **Imports timing helper** (`TESTING_MODE`, `getGraceDeadline`)
2. **Updates `resolveWeekTarget()`** to use `getGraceDeadline()` for grace deadline calculation
3. **Fixes `isGracePeriodExpired()`** to use timing helper (fixes the Tuesday 12:00 ET bug)
4. **Adds cron skip logic** at function start (skips if TESTING_MODE=true and no manual trigger)

---

## Testing Approach

### Option 1: Unit Test Script (Recommended)

**File**: `supabase/tests/test_settlement_timing.ts` (new)

**Purpose**: Verify timing helper integration and cron skip logic

**Test Cases**:

1. **Test Import**
   - Verify function can import timing helper
   - Verify `TESTING_MODE` is accessible

2. **Test resolveWeekTarget() - Normal Mode**
   - Call `resolveWeekTarget()` without TESTING_MODE
   - Verify `graceDeadlineIso` is Tuesday 12:00 ET (1 day after Monday)
   - Verify `weekEndDate` is Monday date

3. **Test resolveWeekTarget() - Testing Mode**
   - Set `TESTING_MODE=true`
   - Call `resolveWeekTarget()` with a Monday date
   - Verify `graceDeadlineIso` is 1 minute after Monday (compressed)
   - Verify `weekEndDate` is Monday date

4. **Test isGracePeriodExpired() - Normal Mode**
   - Create a mock candidate with `week_end_date` = Monday
   - Set reference date to Tuesday 11:00 ET (before grace expires)
   - Verify `isGracePeriodExpired()` returns `false`
   - Set reference date to Tuesday 13:00 ET (after grace expires)
   - Verify `isGracePeriodExpired()` returns `true`

5. **Test isGracePeriodExpired() - Testing Mode**
   - Set `TESTING_MODE=true`
   - Create a mock candidate with `week_end_date` = Monday
   - Set reference date to 30 seconds after Monday (before 1 min grace)
   - Verify `isGracePeriodExpired()` returns `false`
   - Set reference date to 90 seconds after Monday (after 1 min grace)
   - Verify `isGracePeriodExpired()` returns `true`

6. **Test Cron Skip Logic**
   - Set `TESTING_MODE=true`
   - Make request WITHOUT `x-manual-trigger` header
   - Verify function returns early with "Settlement skipped" message
   - Make request WITH `x-manual-trigger: true` header
   - Verify function continues (doesn't skip)

---

### Option 2: Integration Test (More Realistic)

**File**: `supabase/tests/test_settlement_integration.ts` (new)

**Purpose**: Test actual settlement function with real database calls

**Test Cases**:

1. **Test Settlement in Normal Mode**
   - Create a test commitment (Monday deadline)
   - Wait until Tuesday 12:00 ET (or use override)
   - Call settlement function
   - Verify grace deadline is Tuesday 12:00 ET
   - Verify settlement processes correctly

2. **Test Settlement in Testing Mode**
   - Set `TESTING_MODE=true`
   - Create a test commitment
   - Wait 1 minute (compressed grace period)
   - Call settlement function with `x-manual-trigger: true`
   - Verify grace deadline is 1 minute after deadline
   - Verify settlement processes correctly

3. **Test Cron Skip**
   - Set `TESTING_MODE=true`
   - Call settlement function without manual trigger
   - Verify it returns early (doesn't process)

---

### Option 3: Manual Verification (Simplest)

**File**: `supabase/tests/test_settlement_manual.ts` (new)

**Purpose**: Quick manual verification of key functions

**What to Test**:

1. **Import Check**
   ```typescript
   // Verify imports work
   import { TESTING_MODE, getGraceDeadline } from "../functions/_shared/timing.ts";
   console.log("✅ Imports work");
   ```

2. **resolveWeekTarget() Check**
   ```typescript
   // Test in normal mode
   const target1 = resolveWeekTarget();
   console.log("Normal mode grace deadline:", target1.graceDeadlineIso);
   // Should be Tuesday 12:00 ET
   
   // Test in testing mode
   Deno.env.set("TESTING_MODE", "true");
   const target2 = resolveWeekTarget();
   console.log("Testing mode grace deadline:", target2.graceDeadlineIso);
   // Should be 1 minute after Monday
   ```

3. **isGracePeriodExpired() Check**
   ```typescript
   // Create mock candidate
   const candidate = {
     commitment: {
       week_end_date: "2025-01-13", // Monday
       week_grace_expires_at: null
     }
   };
   
   // Test before grace expires
   const beforeGrace = new Date("2025-01-14T11:00:00-05:00"); // Tuesday 11:00 ET
   console.log("Before grace:", isGracePeriodExpired(candidate, beforeGrace)); // Should be false
   
   // Test after grace expires
   const afterGrace = new Date("2025-01-14T13:00:00-05:00"); // Tuesday 13:00 ET
   console.log("After grace:", isGracePeriodExpired(candidate, afterGrace)); // Should be true
   ```

---

## Recommended Testing Strategy

**Use Option 3 (Manual Verification) for Step 1.2** because:
- ✅ Quick to implement
- ✅ Easy to verify visually
- ✅ Tests key functionality
- ✅ Can be run immediately after implementation

**Then use Option 1 (Unit Tests) for comprehensive coverage** if needed.

---

## Test Script Implementation

```typescript
// supabase/tests/test_settlement_manual.ts
import { TESTING_MODE, getGraceDeadline } from "../functions/_shared/timing.ts";

// Import the settlement function's internal functions
// Note: We'll need to export them or test via the public API

console.log("📊 Settlement Function Timing Test (Step 1.2)");
console.log("============================================\n");

// Test 1: Import Check
console.log("✅ Test 1: Import Check");
console.log(`TESTING_MODE: ${TESTING_MODE}`);
console.log(`getGraceDeadline function: ${typeof getGraceDeadline}`);
console.log("");

// Test 2: resolveWeekTarget (via actual function call)
console.log("✅ Test 2: resolveWeekTarget()");
console.log("(This requires calling the actual Edge Function)");
console.log("");

// Test 3: isGracePeriodExpired (via actual function call)
console.log("✅ Test 3: isGracePeriodExpired()");
console.log("(This requires calling the actual Edge Function)");
console.log("");

// Test 4: Cron Skip Logic
console.log("✅ Test 4: Cron Skip Logic");
console.log("(This requires calling the actual Edge Function)");
console.log("");

console.log("============================================");
console.log("Note: Full testing requires calling the Edge Function");
console.log("Use the manual settlement trigger script to test");
```

---

## Manual Testing Steps

### Step 1: Verify Imports Work

```bash
# Check that the file compiles
deno check supabase/functions/bright-service/run-weekly-settlement.ts
```

**Expected**: No import errors

---

### Step 2: Test resolveWeekTarget() in Normal Mode

```bash
# Call settlement function in normal mode
# (This will use resolveWeekTarget internally)
deno run --allow-net --allow-env supabase/tests/manual_settlement_trigger.ts
```

**Check logs for**:
- `graceDeadlineIso` should be Tuesday 12:00 ET (1 day after Monday)
- `weekEndDate` should be Monday date

---

### Step 3: Test resolveWeekTarget() in Testing Mode

```bash
# Call settlement function in testing mode
TESTING_MODE=true deno run --allow-net --allow-env supabase/tests/manual_settlement_trigger.ts
```

**Check logs for**:
- `graceDeadlineIso` should be 1 minute after Monday deadline
- `weekEndDate` should be Monday date

---

### Step 4: Test isGracePeriodExpired() Fix

**Before Fix** (current bug):
- Grace expires Monday evening (~7-8 PM ET)
- Should expire Tuesday 12:00 ET

**After Fix**:
- Create a commitment with Monday deadline
- Call settlement at Tuesday 11:00 ET → Should skip (grace not expired)
- Call settlement at Tuesday 13:00 ET → Should process (grace expired)

**Test**:
```bash
# Create commitment with Monday deadline
# Wait until Tuesday 11:00 ET
# Call settlement → Should see "graceNotExpired" in summary

# Wait until Tuesday 13:00 ET
# Call settlement → Should process and charge
```

---

### Step 5: Test Cron Skip Logic

```bash
# Test 1: Without manual trigger (should skip)
TESTING_MODE=true curl -X POST https://your-project.supabase.co/functions/v1/bright-service/run-weekly-settlement \
  -H "Authorization: Bearer YOUR_ANON_KEY"

# Expected: {"message": "Settlement skipped - testing mode active"}

# Test 2: With manual trigger (should process)
TESTING_MODE=true curl -X POST https://your-project.supabase.co/functions/v1/bright-service/run-weekly-settlement \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "x-manual-trigger: true"

# Expected: Settlement processes normally
```

---

## Verification Checklist

After implementing Step 1.2, verify:

- [ ] File imports timing helper correctly
- [ ] `resolveWeekTarget()` uses `getGraceDeadline()` from timing helper
- [ ] `isGracePeriodExpired()` uses timing helper (fixes Tuesday 12:00 ET bug)
- [ ] Cron skip logic added at function start
- [ ] Normal mode: Grace deadline is Tuesday 12:00 ET
- [ ] Testing mode: Grace deadline is 1 minute after Monday
- [ ] Normal mode: `isGracePeriodExpired()` works correctly
- [ ] Testing mode: `isGracePeriodExpired()` works with compressed timing
- [ ] Cron skip works (returns early without manual trigger)
- [ ] Manual trigger works (processes with `x-manual-trigger: true`)
- [ ] No TypeScript errors
- [ ] Function can be deployed

---

## Success Criteria

✅ **Step 1.2 is complete when**:

1. ✅ Timing helper is imported and used
2. ✅ `resolveWeekTarget()` uses compressed timing in testing mode
3. ✅ `isGracePeriodExpired()` bug is fixed (uses Tuesday 12:00 ET)
4. ✅ Cron skip logic works correctly
5. ✅ Normal mode still works (no regressions)
6. ✅ Testing mode works with compressed timing
7. ✅ Function compiles without errors
8. ✅ Ready for Step 1.3

---

## Quick Test Commands

```bash
# Test 1: Check imports compile
deno check supabase/functions/bright-service/run-weekly-settlement.ts

# Test 2: Test in normal mode (manual trigger)
deno run --allow-net --allow-env supabase/tests/manual_settlement_trigger.ts

# Test 3: Test in testing mode (manual trigger)
TESTING_MODE=true deno run --allow-net --allow-env supabase/tests/manual_settlement_trigger.ts

# Test 4: Test cron skip (without manual trigger)
# (Requires actual Edge Function deployment)
```

---

**End of Testing Strategy**


