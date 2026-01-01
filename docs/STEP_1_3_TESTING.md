# Step 1.3 Testing Strategy: Update Commitment Creation

**Step**: 1.3 - Update Commitment Creation to Use Compressed Deadline  
**File**: `supabase/functions/super-service/index.ts`

---

## What Step 1.3 Does

1. **Imports timing helper** (`TESTING_MODE`, `getNextDeadline`)
2. **Overrides client deadline in testing mode**:
   - If `TESTING_MODE=true`: Calculates compressed deadline (3 minutes from now) using `getNextDeadline()`
   - If `TESTING_MODE=false`: Uses deadline from iOS app (next Monday)
3. **Passes deadline to RPC function** (`rpc_create_commitment`)

---

## Testing Approach

### Option 1: Unit Test Script (Recommended)

**File**: `supabase/tests/test_step_1_3_commitment_deadline.ts` (new)

**Purpose**: Verify commitment creation uses compressed deadline in testing mode

**Test Cases**:

1. **Test Import**
   - Verify function can import timing helper
   - Verify `TESTING_MODE` and `getNextDeadline` are accessible

2. **Test Normal Mode (Client Deadline Used)**
   - Call Edge Function without `TESTING_MODE=true`
   - Send a commitment request with `weekStartDate` = next Monday
   - Verify commitment is created with the client's deadline (not overridden)

3. **Test Testing Mode (Compressed Deadline Used)**
   - Set `TESTING_MODE=true` (requires deployment or local testing)
   - Call Edge Function with any `weekStartDate` from client
   - Verify commitment is created with compressed deadline (~3 minutes from now)
   - Verify client's deadline is ignored/overridden

4. **Test Date Format**
   - Verify deadline is in `YYYY-MM-DD` format
   - Verify it's passed correctly to RPC function

---

### Option 2: Integration Test (More Realistic)

**File**: `supabase/tests/test_commitment_compressed_deadline.ts` (new)

**Purpose**: Test actual commitment creation with compressed deadline

**Test Cases**:

1. **Create Commitment in Testing Mode**
   - Set up test user
   - Call `super-service` Edge Function with `TESTING_MODE=true`
   - Verify commitment is created with deadline ~3 minutes from now
   - Verify commitment can be queried from database

2. **Create Commitment in Normal Mode**
   - Call `super-service` Edge Function without testing mode
   - Verify commitment is created with client's deadline (next Monday)
   - Verify commitment can be queried from database

---

### Option 3: Manual Verification (Simplest)

**File**: `supabase/tests/test_commitment_deadline_manual.ts` (new)

**Purpose**: Quick manual verification of deadline calculation

**What to Test**:

1. **Import Check**
   ```typescript
   import { TESTING_MODE, getNextDeadline } from "../functions/_shared/timing.ts";
   console.log("✅ Imports work");
   ```

2. **Deadline Calculation**
   ```typescript
   // Test compressed deadline
   const compressed = getNextDeadline();
   console.log("Compressed deadline:", compressed);
   // Should be ~3 minutes from now
   ```

3. **Date Format**
   ```typescript
   function formatDate(date: Date): string {
     return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
   }
   const deadlineString = formatDate(compressed);
   console.log("Deadline string:", deadlineString);
   // Should be YYYY-MM-DD format
   ```

---

## Recommended Testing Strategy

**Use Option 2 (Integration Test) for Step 1.3** because:
- ✅ Tests actual Edge Function behavior
- ✅ Verifies end-to-end flow (client → Edge Function → RPC → database)
- ✅ Can verify database records are correct
- ✅ More realistic than unit tests

**Then use Option 3 (Manual Verification) for quick checks** during development.

---

## Test Script Implementation

```typescript
// supabase/tests/test_step_1_3_commitment_deadline.ts
import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { callEdgeFunction, supabase } from "./helpers/client.ts";
import { TEST_USER_IDS } from "./config.ts";

console.log("📊 Step 1.3 Test: Commitment Creation with Compressed Deadline");
console.log("=============================================================\n");

// Test 1: Verify timing helper can be imported
console.log("📊 Test 1: Verify timing helper import");
try {
  const { TESTING_MODE, getNextDeadline } = await import("../functions/_shared/timing.ts");
  assertExists(TESTING_MODE, "TESTING_MODE should be exported");
  assertExists(getNextDeadline, "getNextDeadline should be exported");
  console.log("✅ Test 1 PASS: Timing helper imports correctly");
} catch (error) {
  console.error("❌ Test 1 FAIL:", error);
  Deno.exit(1);
}

// Test 2: Test deadline calculation (normal mode)
console.log("\n📊 Test 2: Deadline calculation (normal mode)");
try {
  Deno.env.delete("TESTING_MODE");
  const { getNextDeadline } = await import("../functions/_shared/timing.ts");
  
  const now = new Date();
  const deadline = getNextDeadline(now);
  const diff = deadline.getTime() - now.getTime();
  const expectedDiff = 7 * 24 * 60 * 60 * 1000; // 7 days
  
  console.log(`   Deadline is ${diff / 1000 / 60 / 60 / 24} days from now`);
  // Should be next Monday, so approximately 1-7 days
  if (diff > 0 && diff < 8 * 24 * 60 * 60 * 1000) {
    console.log("✅ Test 2 PASS: Normal mode deadline is next Monday");
  } else {
    throw new Error(`Unexpected deadline difference: ${diff}ms`);
  }
} catch (error) {
  console.error("❌ Test 2 FAIL:", error);
  Deno.exit(1);
}

// Test 3: Test deadline calculation (testing mode)
console.log("\n📊 Test 3: Deadline calculation (testing mode)");
console.log("⚠️  Note: Requires TESTING_MODE=true at module load time");
console.log("   (Will test via actual Edge Function call)");

// Test 4: Test date formatting
console.log("\n📊 Test 4: Date formatting");
try {
  function formatDate(date: Date): string {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  }
  
  const testDate = new Date("2025-01-13T12:00:00Z");
  const formatted = formatDate(testDate);
  assertEquals(formatted, "2025-01-13", "Date should be formatted as YYYY-MM-DD");
  console.log(`   Formatted date: ${formatted}`);
  console.log("✅ Test 4 PASS: Date formatting works correctly");
} catch (error) {
  console.error("❌ Test 4 FAIL:", error);
  Deno.exit(1);
}

// Test 5: Test actual Edge Function call (requires deployment)
console.log("\n📊 Test 5: Edge Function call (requires deployment)");
console.log("⚠️  This test requires:");
console.log("   1. Edge Function deployed with TESTING_MODE=true");
console.log("   2. Test user with valid payment method");
console.log("   3. Valid authentication token");
console.log("   (Will be tested in integration testing)");

console.log("\n============================================================");
console.log("✅ Step 1.3 basic tests passed!");
console.log("============================================================");
```

---

## Manual Testing Steps

### Step 1: Verify Imports Work

```bash
# Check that the file compiles
deno check supabase/functions/super-service/index.ts
```

**Expected**: No import errors

---

### Step 2: Test in Normal Mode

**Setup**:
1. Ensure `TESTING_MODE` is not set (or `false`)
2. Have a test user ready

**Test**:
```bash
# Call Edge Function with a commitment request
# The deadline should be the client's deadline (next Monday)
```

**Verify**:
- Commitment is created with deadline = client's `weekStartDate`
- Deadline is in `YYYY-MM-DD` format
- Commitment exists in database

---

### Step 3: Test in Testing Mode

**Setup**:
1. Deploy Edge Function with `TESTING_MODE=true`
2. Have a test user ready

**Test**:
```bash
# Call Edge Function with a commitment request
# The deadline should be ~3 minutes from now (compressed)
```

**Verify**:
- Commitment is created with deadline ~3 minutes from now
- Client's `weekStartDate` is ignored/overridden
- Deadline is in `YYYY-MM-DD` format
- Commitment exists in database

---

### Step 4: Verify Database Record

**Query**:
```sql
SELECT id, week_end_date, created_at 
FROM commitments 
WHERE user_id = 'test-user-id'
ORDER BY created_at DESC 
LIMIT 1;
```

**Verify**:
- `week_end_date` matches expected deadline
- In testing mode: `week_end_date` is approximately 3 minutes after `created_at`
- In normal mode: `week_end_date` is next Monday

---

## Verification Checklist

After implementing Step 1.3, verify:

- [ ] File imports timing helper correctly
- [ ] `TESTING_MODE` check is added
- [ ] Compressed deadline is calculated when `TESTING_MODE=true`
- [ ] Client deadline is used when `TESTING_MODE=false`
- [ ] Deadline is formatted as `YYYY-MM-DD`
- [ ] Deadline is passed correctly to `rpc_create_commitment`
- [ ] Normal mode: Commitment uses client's deadline
- [ ] Testing mode: Commitment uses compressed deadline (~3 minutes)
- [ ] No TypeScript errors
- [ ] Function can be deployed

---

## Success Criteria

✅ **Step 1.3 is complete when**:

1. ✅ Timing helper is imported and used
2. ✅ Testing mode: Compressed deadline is calculated and used
3. ✅ Normal mode: Client's deadline is still used (no regression)
4. ✅ Deadline format is correct (`YYYY-MM-DD`)
5. ✅ RPC function receives correct deadline
6. ✅ Database records show correct deadline
7. ✅ Function compiles without errors
8. ✅ Ready for Step 1.4 (or next phase)

---

## Quick Test Commands

```bash
# Test 1: Check imports compile
deno check supabase/functions/super-service/index.ts

# Test 2: Test deadline calculation manually
deno run --allow-env supabase/tests/test_commitment_deadline_manual.ts

# Test 3: Test actual Edge Function (requires deployment)
# (Use existing test_create_commitment.ts as reference)
```

---

## Edge Cases to Test

1. **Client sends invalid date format**
   - Should still work (server calculates deadline in testing mode)
   - Normal mode: Should handle gracefully

2. **Client sends past date**
   - Testing mode: Overridden with compressed deadline
   - Normal mode: Should validate or use next Monday

3. **Client sends future date (beyond next Monday)**
   - Testing mode: Overridden with compressed deadline
   - Normal mode: Should use client's date or validate

4. **TESTING_MODE changes mid-request**
   - Should use mode at function start (module load time)

---

**End of Testing Strategy**


