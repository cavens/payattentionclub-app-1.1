# Step 1.1 Testing Strategy: Create Shared Timing Helper

**Step**: 1.1 - Create Shared Timing Helper  
**File**: `supabase/functions/_shared/timing.ts`

---

## Testing Approach

### Option 1: Simple Test Script (Recommended)

**File**: `supabase/tests/test_timing_helper.ts` (new)

**Purpose**: Verify timing helper exports and functions work correctly

**Test Cases**:

1. **Test Constants Export**
   - Verify `TESTING_MODE` exports
   - Verify `WEEK_DURATION_MS` exports
   - Verify `GRACE_PERIOD_MS` exports

2. **Test TESTING_MODE Detection**
   - Test with `TESTING_MODE=true` → Should be `true`
   - Test with `TESTING_MODE=false` → Should be `false`
   - Test with `TESTING_MODE` unset → Should be `false`

3. **Test Duration Constants**
   - When `TESTING_MODE=true`:
     - `WEEK_DURATION_MS` should be `180000` (3 * 60 * 1000)
     - `GRACE_PERIOD_MS` should be `60000` (1 * 60 * 1000)
   - When `TESTING_MODE=false`:
     - `WEEK_DURATION_MS` should be `604800000` (7 * 24 * 60 * 60 * 1000)
     - `GRACE_PERIOD_MS` should be `86400000` (24 * 60 * 60 * 1000)

4. **Test getNextDeadline() Function**
   - **Testing Mode**: Should return date ~3 minutes from now
   - **Normal Mode**: Should return next Monday 12:00 ET
   - Verify date is in the future
   - Verify date format is correct

5. **Test getGraceDeadline() Function**
   - **Testing Mode**: Should return date 1 minute after input date
   - **Normal Mode**: Should return date 1 day after input date (Tuesday 12:00 ET)
   - Verify time is preserved correctly

---

## Test Script Implementation

```typescript
// supabase/tests/test_timing_helper.ts
import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";

// Import the timing helper
// Note: We'll need to import from the actual path once created
// import { TESTING_MODE, WEEK_DURATION_MS, GRACE_PERIOD_MS, getNextDeadline, getGraceDeadline } from "../functions/_shared/timing.ts";

Deno.test("Timing Helper - Constants Export", () => {
  // Verify all constants are exported
  assertExists(TESTING_MODE, "TESTING_MODE should be exported");
  assertExists(WEEK_DURATION_MS, "WEEK_DURATION_MS should be exported");
  assertExists(GRACE_PERIOD_MS, "GRACE_PERIOD_MS should be exported");
});

Deno.test("Timing Helper - Week Duration (Testing Mode)", async () => {
  // Set TESTING_MODE=true
  Deno.env.set("TESTING_MODE", "true");
  
  // Re-import to get updated values
  // (In actual implementation, may need to reload module)
  
  assertEquals(WEEK_DURATION_MS, 180000, "Week duration should be 3 minutes in testing mode");
  assertEquals(GRACE_PERIOD_MS, 60000, "Grace period should be 1 minute in testing mode");
  
  // Cleanup
  Deno.env.delete("TESTING_MODE");
});

Deno.test("Timing Helper - Week Duration (Normal Mode)", async () => {
  // Ensure TESTING_MODE is not set
  Deno.env.delete("TESTING_MODE");
  
  // Re-import to get updated values
  
  assertEquals(WEEK_DURATION_MS, 604800000, "Week duration should be 7 days in normal mode");
  assertEquals(GRACE_PERIOD_MS, 86400000, "Grace period should be 24 hours in normal mode");
});

Deno.test("Timing Helper - getNextDeadline (Testing Mode)", () => {
  Deno.env.set("TESTING_MODE", "true");
  
  const now = new Date();
  const deadline = getNextDeadline(now);
  
  // Should be approximately 3 minutes from now
  const diff = deadline.getTime() - now.getTime();
  const expectedDiff = 3 * 60 * 1000; // 3 minutes in ms
  
  // Allow 1 second tolerance
  assertEquals(Math.abs(diff - expectedDiff) < 1000, true, 
    `Deadline should be ~3 minutes from now. Got ${diff}ms, expected ~${expectedDiff}ms`);
  
  Deno.env.delete("TESTING_MODE");
});

Deno.test("Timing Helper - getGraceDeadline (Testing Mode)", () => {
  Deno.env.set("TESTING_MODE", "true");
  
  const baseDate = new Date("2025-01-13T12:00:00Z");
  const graceDeadline = getGraceDeadline(baseDate);
  
  // Should be 1 minute after base date
  const diff = graceDeadline.getTime() - baseDate.getTime();
  const expectedDiff = 1 * 60 * 1000; // 1 minute in ms
  
  assertEquals(Math.abs(diff - expectedDiff) < 1000, true,
    `Grace deadline should be 1 minute after base date. Got ${diff}ms, expected ${expectedDiff}ms`);
  
  Deno.env.delete("TESTING_MODE");
});

Deno.test("Timing Helper - getGraceDeadline (Normal Mode)", () => {
  Deno.env.delete("TESTING_MODE");
  
  const baseDate = new Date("2025-01-13T12:00:00Z"); // Monday
  const graceDeadline = getGraceDeadline(baseDate);
  
  // Should be 1 day after (Tuesday)
  const diff = graceDeadline.getTime() - baseDate.getTime();
  const expectedDiff = 24 * 60 * 60 * 1000; // 24 hours in ms
  
  assertEquals(Math.abs(diff - expectedDiff) < 1000, true,
    `Grace deadline should be 1 day after base date. Got ${diff}ms, expected ${expectedDiff}ms`);
});
```

---

## Option 2: Manual Verification (Simpler)

**Quick Manual Test**:

1. **Create the file** `supabase/functions/_shared/timing.ts`

2. **Create a simple test script** `supabase/tests/test_timing_manual.ts`:

```typescript
// Simple manual test
import { TESTING_MODE, WEEK_DURATION_MS, GRACE_PERIOD_MS, getNextDeadline, getGraceDeadline } from "../functions/_shared/timing.ts";

console.log("📊 Timing Helper Test");
console.log("====================");
console.log(`TESTING_MODE: ${TESTING_MODE}`);
console.log(`WEEK_DURATION_MS: ${WEEK_DURATION_MS} (${WEEK_DURATION_MS / 1000 / 60} minutes)`);
console.log(`GRACE_PERIOD_MS: ${GRACE_PERIOD_MS} (${GRACE_PERIOD_MS / 1000 / 60} minutes)`);
console.log("");

const now = new Date();
const deadline = getNextDeadline(now);
const graceDeadline = getGraceDeadline(deadline);

console.log(`Now: ${now.toISOString()}`);
console.log(`Next Deadline: ${deadline.toISOString()}`);
console.log(`Grace Deadline: ${graceDeadline.toISOString()}`);
console.log("");

const deadlineDiff = (deadline.getTime() - now.getTime()) / 1000 / 60;
const graceDiff = (graceDeadline.getTime() - deadline.getTime()) / 1000 / 60;

console.log(`Deadline is ${deadlineDiff.toFixed(2)} minutes from now`);
console.log(`Grace period is ${graceDiff.toFixed(2)} minutes after deadline`);

if (TESTING_MODE) {
  console.log("");
  console.log("✅ Testing Mode: Expected ~3 min deadline, ~1 min grace");
  if (Math.abs(deadlineDiff - 3) < 0.1 && Math.abs(graceDiff - 1) < 0.1) {
    console.log("✅ PASS: Timings match expected compressed values");
  } else {
    console.log("❌ FAIL: Timings don't match expected values");
  }
} else {
  console.log("");
  console.log("✅ Normal Mode: Expected next Monday deadline, 24h grace");
  console.log("(Manual verification needed for Monday calculation)");
}
```

3. **Run the test**:
```bash
# With TESTING_MODE=true
TESTING_MODE=true deno run --allow-net --allow-env supabase/tests/test_timing_manual.ts

# With TESTING_MODE=false (or unset)
deno run --allow-net --allow-env supabase/tests/test_timing_manual.ts
```

---

## Expected Results

### When TESTING_MODE=true:
- `TESTING_MODE` = `true`
- `WEEK_DURATION_MS` = `180000` (3 minutes)
- `GRACE_PERIOD_MS` = `60000` (1 minute)
- `getNextDeadline(now)` = Date ~3 minutes from now
- `getGraceDeadline(deadline)` = Date ~1 minute after deadline

### When TESTING_MODE=false (or unset):
- `TESTING_MODE` = `false`
- `WEEK_DURATION_MS` = `604800000` (7 days)
- `GRACE_PERIOD_MS` = `86400000` (24 hours)
- `getNextDeadline(now)` = Next Monday 12:00 ET
- `getGraceDeadline(deadline)` = Tuesday 12:00 ET (1 day after Monday)

---

## Verification Checklist

After implementing Step 1.1, verify:

- [ ] File `supabase/functions/_shared/timing.ts` exists
- [ ] All constants export correctly
- [ ] `TESTING_MODE` reads from environment variable
- [ ] Constants have correct values in testing mode
- [ ] Constants have correct values in normal mode
- [ ] `getNextDeadline()` returns correct date in testing mode
- [ ] `getNextDeadline()` returns next Monday in normal mode
- [ ] `getGraceDeadline()` returns correct date in testing mode
- [ ] `getGraceDeadline()` returns correct date in normal mode
- [ ] No TypeScript errors
- [ ] Module can be imported by other files

---

## Quick Test Command

```bash
# Test in testing mode
TESTING_MODE=true deno run --allow-env supabase/tests/test_timing_manual.ts

# Test in normal mode
deno run --allow-env supabase/tests/test_timing_manual.ts
```

---

## Success Criteria

✅ **Step 1.1 is complete when**:
1. File exists and exports all required constants and functions
2. Constants have correct values based on `TESTING_MODE`
3. Functions return correct dates in both modes
4. No errors when importing the module
5. Ready to be used by Step 1.2

---

**End of Testing Strategy**


