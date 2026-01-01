# Testing Timeline Compression - Analysis & Implementation Plan

**Date**: 2025-01-01  
**Purpose**: Analyze how to compress settlement timeline for faster testing

---

## Goal

Compress timeline for testing:
- **Week duration**: 7 days → **3 minutes**
- **Grace period**: 24 hours → **1 minute**

This allows testing all settlement cases in ~5 minutes instead of weeks.

---

## Current Timing Logic Locations

### 1. Backend Settlement Function

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

**Functions**:
- `resolveWeekTarget()` - Calculates Monday deadline and Tuesday grace period
- `isGracePeriodExpired()` - Checks if grace period expired

**Key Code**:
```typescript
// Line 70-81: Calculates Monday 12:00 ET and Tuesday 12:00 ET
const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE);
const monday = new Date(reference);
monday.setDate(monday.getDate() - daysSinceMonday);
monday.setHours(12, 0, 0, 0);  // Monday 12:00 ET

const graceDeadline = new Date(monday);
graceDeadline.setDate(graceDeadline.getDate() + 1);  // Tuesday 12:00 ET
```

---

### 2. iOS App Deadline Calculation

**Files**:
- `Models/AppModel.swift` - `calculateNextMondayNoonEST()`
- `Models/CountdownModel.swift` - `nextMondayNoonEST()`
- `Views/SetupView.swift` - `nextMondayNoonEST()`

**Key Code**:
```swift
// Calculates next Monday 12:00 ET
let daysUntilMonday = (9 - weekday) % 7
// ... sets hour to 12, minute to 0
```

---

### 3. Commitment Creation

**File**: `supabase/remote_rpcs/rpc_create_commitment.sql`

**Key Code**:
```sql
-- Sets week_end_date to p_deadline_date (next Monday)
-- Sets week_start_date to current_date (when committed)
```

---

### 4. Cron Job Schedule

**File**: Supabase cron configuration (likely in dashboard or migrations)

**Current**: Runs settlement on Tuesday 12:00 ET

---

## Implementation Approach

### Option 1: Environment Variable + Helper Functions (RECOMMENDED)

**Concept**: Add a `TESTING_MODE` environment variable that compresses durations.

**Implementation**:

#### Step 1: Create Helper Functions

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

```typescript
// Add at top of file
const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
const WEEK_DURATION_MS = TESTING_MODE ? 3 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;  // 3 min or 7 days
const GRACE_PERIOD_MS = TESTING_MODE ? 1 * 60 * 1000 : 24 * 60 * 60 * 1000;  // 1 min or 24 hours

function resolveWeekTarget(options?: { override?: string; now?: Date }): WeekTarget {
  const override = options?.override;
  if (override) {
    const parsed = new Date(`${override}T12:00:00Z`);
    const grace = new Date(parsed);
    grace.setUTCDate(grace.getUTCDate() + 1);
    return { weekEndDate: override, graceDeadlineIso: grace.toISOString() };
  }

  const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE);
  const monday = new Date(reference);
  const dayOfWeek = reference.getDay();
  const daysSinceMonday = (dayOfWeek + 6) % 7;
  monday.setDate(monday.getDate() - daysSinceMonday);
  monday.setHours(12, 0, 0, 0);

  const weekEndDate = formatDate(monday);
  
  // COMPRESSED: Add compressed duration instead of 1 day
  const graceDeadline = new Date(monday);
  if (TESTING_MODE) {
    graceDeadline.setTime(graceDeadline.getTime() + GRACE_PERIOD_MS);
  } else {
    graceDeadline.setDate(graceDeadline.getDate() + 1);
  }

  return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
}
```

**Problem**: This approach has issues because:
- `week_end_date` is stored as a DATE (not timestamp)
- We need to compress from commitment creation time, not settlement time
- iOS app also needs to know about compression

---

### Option 2: Testing Mode Flag + Compressed Timestamps (BETTER)

**Concept**: Store compressed timestamps in database when testing mode is enabled.

#### Step 1: Add Testing Mode Configuration

**File**: `supabase/functions/_shared/config.ts` (create if doesn't exist)

```typescript
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
export const WEEK_DURATION_MS = TESTING_MODE ? 3 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
export const GRACE_PERIOD_MS = TESTING_MODE ? 1 * 60 * 1000 : 24 * 60 * 60 * 1000;
```

#### Step 2: Modify Commitment Creation

**File**: `supabase/remote_rpcs/rpc_create_commitment.sql`

```sql
-- Add function parameter or check environment
-- When testing mode: Calculate compressed deadline
-- When normal mode: Use next Monday

-- Option: Add p_testing_mode parameter (default false)
-- Or: Check for environment variable via Supabase function context
```

**Challenge**: SQL functions can't easily access environment variables. Need to pass as parameter.

#### Step 3: Modify Settlement Function

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

```typescript
import { TESTING_MODE, WEEK_DURATION_MS, GRACE_PERIOD_MS } from "../_shared/config.ts";

function resolveWeekTarget(options?: { override?: string; now?: Date }): WeekTarget {
  // ... existing logic ...
  
  // If testing mode, calculate compressed grace deadline
  if (TESTING_MODE) {
    const graceDeadline = new Date(monday);
    graceDeadline.setTime(graceDeadline.getTime() + GRACE_PERIOD_MS);
    return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
  }
  
  // Normal mode
  const graceDeadline = new Date(monday);
  graceDeadline.setDate(graceDeadline.getDate() + 1);
  return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
}

function isGracePeriodExpired(candidate: SettlementCandidate, reference: Date = new Date()): boolean {
  const explicit = candidate.commitment.week_grace_expires_at;
  if (explicit) return new Date(explicit).getTime() <= reference.getTime();

  // If testing mode, use compressed calculation
  if (TESTING_MODE) {
    const weekEnd = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
    const graceExpires = new Date(weekEnd.getTime() + GRACE_PERIOD_MS);
    return graceExpires.getTime() <= reference.getTime();
  }

  // Normal mode (existing logic - but has bug, should be fixed)
  const derived = new Date(`${candidate.commitment.week_end_date}T00:00:00Z`);
  derived.setUTCDate(derived.getUTCDate() + 1);
  return derived.getTime() <= reference.getTime();
}
```

#### Step 4: Modify iOS App (if needed)

**File**: `Models/AppModel.swift`

```swift
// Add testing mode check (from environment or config)
private var isTestingMode: Bool {
    // Check environment variable or config
    // For staging builds, could be enabled
}

func calculateNextMondayNoonEST() -> Date {
    if isTestingMode {
        // Return deadline 3 minutes from now
        return Date().addingTimeInterval(3 * 60)
    }
    // ... existing logic ...
}
```

**Problem**: iOS app doesn't know about backend testing mode. Need coordination.

---

### Option 3: Database Flag + Compressed Calculations (SIMPLEST)

**Concept**: Add a `testing_mode` flag to database (or use existing config table). All functions check this flag.

#### Step 1: Add Testing Mode Check Function

**File**: `supabase/remote_rpcs/rpc_get_testing_mode.sql` (new)

```sql
CREATE OR REPLACE FUNCTION public.rpc_get_testing_mode()
RETURNS boolean
LANGUAGE sql
STABLE AS $$
  -- Check environment variable or config table
  -- For now, use a simple approach: check if TESTING_MODE env var is set
  -- This requires Supabase to expose env vars to SQL (may not be possible)
  
  -- Alternative: Use a config table
  SELECT COALESCE(
    (SELECT value::boolean FROM public.config WHERE key = 'testing_mode'),
    false
  );
$$;
```

**Better**: Use Supabase Edge Function environment variables (accessible in TypeScript, not SQL).

#### Step 2: Store Compressed Deadlines

**Approach**: When `TESTING_MODE=true`, calculate compressed deadlines at commitment creation.

**File**: `supabase/remote_rpcs/rpc_create_commitment.sql`

```sql
-- Add logic to calculate compressed deadline if testing mode
-- But SQL can't check env vars easily...

-- Solution: Pass testing_mode as parameter (optional, default false)
CREATE OR REPLACE FUNCTION public.rpc_create_commitment(
  -- ... existing parameters ...
  p_testing_mode boolean DEFAULT false
)
```

**Then in Edge Function** (`super-service/index.ts`):
```typescript
const testingMode = Deno.env.get("TESTING_MODE") === "true";
const deadlineDate = testingMode 
  ? calculateCompressedDeadline()  // 3 minutes from now
  : getNextMondayDeadline();       // Next Monday

await supabase.rpc('rpc_create_commitment', {
  // ... other params ...
  p_deadline_date: deadlineDate,
  p_testing_mode: testingMode
});
```

---

## Recommended Approach: Hybrid Solution

### Implementation Strategy

1. **Backend (Edge Functions)**: Use environment variable `TESTING_MODE=true` in staging
2. **Database**: Pass `testing_mode` flag to RPC functions when needed
3. **iOS App**: Add staging build flag (separate from backend testing mode)

### Key Changes Needed

#### 1. Environment Variable Setup

**Staging Environment**:
```bash
# Set in Supabase dashboard or via CLI
TESTING_MODE=true
```

#### 2. Helper Functions

**File**: `supabase/functions/_shared/timing.ts` (new)

```typescript
export const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
export const WEEK_DURATION_MS = TESTING_MODE ? 3 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
export const GRACE_PERIOD_MS = TESTING_MODE ? 1 * 60 * 1000 : 24 * 60 * 60 * 1000;

export function getNextDeadline(now: Date = new Date()): Date {
  if (TESTING_MODE) {
    return new Date(now.getTime() + WEEK_DURATION_MS);
  }
  // ... existing Monday calculation ...
}

export function getGraceDeadline(weekEndDate: Date): Date {
  if (TESTING_MODE) {
    return new Date(weekEndDate.getTime() + GRACE_PERIOD_MS);
  }
  const grace = new Date(weekEndDate);
  grace.setDate(grace.getDate() + 1);
  return grace;
}
```

#### 3. Update Settlement Function

**File**: `supabase/functions/bright-service/run-weekly-settlement.ts`

```typescript
import { TESTING_MODE, getGraceDeadline } from "../_shared/timing.ts";

function resolveWeekTarget(options?: { override?: string; now?: Date }): WeekTarget {
  // ... existing logic ...
  const graceDeadline = getGraceDeadline(monday);
  return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
}
```

#### 4. Update Commitment Creation

**File**: `supabase/functions/super-service/index.ts`

```typescript
import { TESTING_MODE, getNextDeadline } from "../_shared/timing.ts";

const deadlineDate = TESTING_MODE 
  ? getNextDeadline()  // 3 minutes from now
  : getNextMondayDeadline();  // Next Monday

// Format as YYYY-MM-DD for database
const deadlineDateString = formatDate(deadlineDate);
```

---

## Implications & Risks

### ✅ Benefits

1. **Fast Testing**: Test all cases in ~5 minutes
2. **Repeatable**: Can run tests multiple times quickly
3. **Isolated**: Only affects staging environment
4. **No Code Duplication**: Same logic, compressed timing

### ⚠️ Risks & Considerations

#### 1. **Timing Precision**

**Risk**: Milliseconds matter in compressed mode (3 minutes = 180,000ms)

**Mitigation**:
- Use `Date` objects with millisecond precision
- Ensure all timing checks use same reference time
- Be careful with timezone conversions

#### 2. **Cron Job Timing**

**Risk**: Cron job runs on fixed schedule (Tuesday 12:00 ET), not relative to commitment creation

**Solution**: ✅ **MANUAL TRIGGERING** (Chosen Approach)
- In testing mode, **disable cron** and trigger settlement manually via API
- This gives full control over when settlement runs
- Allows testing exact timing scenarios (before/after grace period)
- Can trigger multiple times to test different cases

#### 3. **iOS App Coordination**

**Risk**: iOS app calculates deadlines independently, may not match backend

**Current Issue**: iOS app **ignores** the `deadlineDate` returned from backend and recalculates locally using `getNextMondayNoonEST()`. This means:
- In testing mode, backend stores compressed deadline (3 minutes)
- iOS app still calculates full week deadline locally
- Countdown will show ~7 days instead of 3 minutes

**Solution**: ✅ **iOS APP USES BACKEND DEADLINE** (Required for Testing Mode)
- **Update iOS app** to use `commitmentResponse.deadlineDate` from backend
- Parse the date string (YYYY-MM-DD) and convert to `Date` object
- Store this deadline instead of recalculating locally
- Countdown will automatically show compressed timeline in testing mode
- This also fixes a current bug (app should use backend as source of truth)

**Implementation**:
```swift
// In AuthorizationView.swift, after commitment creation:
let commitmentResponse = try await BackendClient.shared.createCommitment(...)

// Parse deadline from backend response
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd"
dateFormatter.timeZone = TimeZone(identifier: "America/New_York")

if let deadlineDate = dateFormatter.date(from: commitmentResponse.deadlineDate) {
    // Store backend deadline (not local calculation)
    UsageTracker.shared.storeCommitmentDeadline(deadlineDate)
} else {
    // Fallback to local calculation if parsing fails
    let deadline = model.getNextMondayNoonEST()
    UsageTracker.shared.storeCommitmentDeadline(deadline)
}
```

**Files to Modify**:
- `Views/AuthorizationView.swift` - Use `commitmentResponse.deadlineDate`
- Remove local deadline calculation after commitment creation

#### 4. **Database Date Storage**

**Risk**: `week_end_date` is stored as DATE (not timestamp), loses time precision

**Impact**: 
- In testing mode, need to store exact timestamp
- Or: Store as timestamp in separate column for testing

**Solution**: 
- Use `week_end_date` for date part (YYYY-MM-DD)
- Use `week_grace_expires_at` for exact timestamp (already exists!)
- In testing mode, set `week_grace_expires_at` to compressed time

#### 5. **Multiple Commitments**

**Risk**: If user creates multiple commitments in testing mode, they may overlap

**Mitigation**: 
- Testing should be single-user, sequential
- Or: Ensure compressed deadlines don't overlap

#### 6. **State Persistence**

**Risk**: If testing mode is toggled, existing commitments may have mixed timing

**Mitigation**:
- Only enable testing mode when starting fresh
- Or: Add `testing_mode` flag to commitments table to track which mode was used

#### 7. **Settlement Cron**

**Risk**: Cron job runs on fixed schedule, not relative to compressed deadlines

**Solution**: ✅ **AUTOMATIC SKIP IN TESTING MODE** (Simplest Approach)
- **Check `TESTING_MODE` at start of settlement function** - If enabled, return early with message
- **No need to disable cron** - Function will automatically skip when testing mode is active
- **Trigger settlement manually** via API call to `bright-service/run-weekly-settlement` for testing
- Pass `now` parameter to control exact timing for testing
- This gives full control and allows testing all edge cases precisely

**Implementation**: 
```typescript
// At start of run-weekly-settlement.ts
const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";

// In main handler, before processing:
if (TESTING_MODE) {
  // In testing mode, only run if explicitly triggered (not from cron)
  // Cron jobs don't pass special headers, manual triggers can pass a flag
  const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
  if (!isManualTrigger) {
    return new Response(JSON.stringify({ 
      message: "Settlement skipped - testing mode active, use manual trigger" 
    }), { status: 200 });
  }
}
```

**Alternative (Simpler)**: Just test outside cron schedule times, or let cron run but it will process nothing (no commitments ready for settlement in compressed timeline).

---

## Simplest Implementation

### Minimal Changes Approach

1. **Add environment variable** `TESTING_MODE=true` in staging
2. **Create timing helper** `_shared/timing.ts` with compressed durations
3. **Update 2 functions**:
   - `resolveWeekTarget()` - Use compressed grace period
   - `getNextDeadline()` in commitment creation - Use compressed week duration
4. ✅ **Manual settlement triggering** - **Disable cron in testing mode**, call settlement function directly via API with `now` parameter for precise control

### Files to Modify

1. ✅ `supabase/functions/_shared/timing.ts` (new)
2. ✅ `supabase/functions/bright-service/run-weekly-settlement.ts`
3. ✅ `supabase/functions/super-service/index.ts`
4. ✅ **Manual Settlement Trigger** - Use Supabase function invoker or create simple API endpoint to call `bright-service/run-weekly-settlement` with controlled `now` parameter

### Testing Workflow

1. Set `TESTING_MODE=true` in staging environment
2. **Disable cron job** for settlement (or ensure it's skipped in testing mode)
3. Create commitment → Deadline is 3 minutes from now
4. Wait 1 minute → Grace period expires
5. **Manually trigger settlement** via API → Tests Case 2 (no sync)
6. Create new commitment, sync immediately → Tests Case 1
7. Wait for grace period → **Manually trigger settlement** → Tests Case 1
8. Create commitment, wait for settlement, then sync → Tests Case 3

**Manual Trigger Method**:
- Use Supabase function invoker: `supabase functions invoke bright-service --method POST --body '{"targetWeek": "2025-01-13"}'`
- Or create simple test script that calls the function with controlled timing
- Pass `now` parameter to control exact settlement time for testing

---

## Recommendations

### ✅ DO

1. **Use environment variable** for easy toggling
2. **Create shared timing helper** to avoid duplication
3. **Store compressed timestamps** in `week_grace_expires_at` field
4. ✅ **Manual settlement triggering** - **Disable cron in testing mode**, trigger settlement manually via API for full control
5. **Test sequentially** - one commitment at a time
6. **Clear test data** between test runs
7. **Use `now` parameter** when triggering settlement to control exact timing

### ❌ DON'T

1. **Don't modify production code paths** - use feature flags
2. **Don't rely on iOS app timing** - get deadline from backend
3. **Don't mix testing and normal mode** - clear data when switching
4. ✅ **Don't use cron in testing** - **Always trigger settlement manually** for precise control over timing

---

## Next Steps

1. ✅ Create `_shared/timing.ts` helper
2. ✅ Update `resolveWeekTarget()` to use compressed timing
3. ✅ Update commitment creation to use compressed deadline
4. ✅ **Add automatic cron skip** - Check `TESTING_MODE` at start of settlement function
5. ✅ **Update iOS app** - Use `commitmentResponse.deadlineDate` from backend instead of local calculation
6. ✅ **Create verification tools** - SQL queries and helper functions to verify test results
7. ✅ Document testing workflow with manual trigger steps
8. ✅ Test all 3 cases with compressed timing using manual triggers

## Verification Tools

### SQL Verification Function

**File**: `supabase/remote_rpcs/rpc_verify_test_settlement.sql` (new)

```sql
CREATE OR REPLACE FUNCTION public.rpc_verify_test_settlement(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  v_result json;
  v_commitment json;
  v_penalty json;
  v_payments json;
  v_usage_count integer;
BEGIN
  -- Get latest commitment
  SELECT row_to_json(c.*) INTO v_commitment
  FROM public.commitments c
  WHERE c.user_id = p_user_id
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- Get latest penalty record
  SELECT row_to_json(uwp.*) INTO v_penalty
  FROM public.user_week_penalties uwp
  WHERE uwp.user_id = p_user_id
  ORDER BY uwp.week_start_date DESC
  LIMIT 1;

  -- Get all payments
  SELECT json_agg(row_to_json(p.*)) INTO v_payments
  FROM public.payments p
  WHERE p.user_id = p_user_id
  ORDER BY p.created_at DESC;

  -- Count usage entries
  SELECT COUNT(*) INTO v_usage_count
  FROM public.daily_usage
  WHERE user_id = p_user_id;

  -- Build result
  v_result := json_build_object(
    'commitment', v_commitment,
    'penalty', v_penalty,
    'payments', COALESCE(v_payments, '[]'::json),
    'usage_count', v_usage_count,
    'verification_time', NOW()
  );

  RETURN v_result;
END;
$$;
```

### Verification Summary View

**File**: `supabase/tests/verify_test_results.ts` (new)

```typescript
// Quick verification script to check test results
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

async function verifyTestResults(userId: string) {
  const { data, error } = await supabase.rpc('rpc_verify_test_settlement', {
    p_user_id: userId
  });

  if (error) {
    console.error("❌ Verification failed:", error);
    return;
  }

  console.log("\n📊 TEST RESULTS VERIFICATION");
  console.log("============================\n");

  // Commitment
  if (data.commitment) {
    console.log("✅ Commitment:", {
      id: data.commitment.id,
      deadline: data.commitment.week_end_date,
      grace_expires: data.commitment.week_grace_expires_at,
      max_charge: data.commitment.max_charge_cents,
      status: data.commitment.status
    });
  }

  // Penalty
  if (data.penalty) {
    console.log("\n✅ Penalty Record:", {
      status: data.penalty.settlement_status,
      charged: data.penalty.charged_amount_cents,
      actual: data.penalty.actual_amount_cents,
      needs_reconciliation: data.penalty.needs_reconciliation,
      delta: data.penalty.reconciliation_delta_cents
    });
  }

  // Payments
  console.log("\n✅ Payments:", data.payments.length);
  data.payments.forEach((p: any, i: number) => {
    console.log(`  ${i + 1}. ${p.type}: ${p.amount_cents} cents (${p.status})`);
  });

  // Usage
  console.log(`\n✅ Usage Entries: ${data.usage_count}`);

  console.log("\n============================\n");
}

// Usage
const userId = Deno.args[0];
if (!userId) {
  console.error("Usage: deno run verify_test_results.ts <user-id>");
  Deno.exit(1);
}

await verifyTestResults(userId);
```

---

**End of Analysis**

