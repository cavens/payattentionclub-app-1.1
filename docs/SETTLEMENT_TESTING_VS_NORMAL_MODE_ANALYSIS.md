# Settlement: Testing Mode vs Normal Mode Analysis
**Date**: 2026-01-17  
**Purpose**: Analyze exact differences between testing and normal mode to ensure they're as close as possible

---

## ✅ Single Codebase: YES

**File**: `supabase/functions/bright-service/index.ts`

**Both modes use the same codebase**. The function checks `TESTING_MODE` from `_shared/timing.ts` to determine behavior.

---

## Differences Between Testing and Normal Mode

### 1. **Timing Durations** (Abstracted via `_shared/timing.ts`)

| Aspect | Testing Mode | Normal Mode |
|--------|--------------|-------------|
| **Week Duration** | 3 minutes | 7 days |
| **Grace Period** | 1 minute | 24 hours |
| **Source** | `WEEK_DURATION_MS`, `GRACE_PERIOD_MS` constants | Same constants |

**Impact**: ✅ **Abstracted** - Core logic uses `getGraceDeadline()` which handles both modes

---

### 2. **Week Target Resolution** (`resolveWeekTarget()`)

**Testing Mode** (lines 77-90):
```typescript
if (TESTING_MODE) {
  const now = options?.now ?? new Date();
  const todayUTC = new Date(now);
  const weekEndDate = formatDate(todayUTC); // Uses UTC date
  todayUTC.setUTCHours(12, 0, 0, 0);
  const graceDeadline = getGraceDeadline(todayUTC);
  return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
}
```

**Normal Mode** (lines 93-105):
```typescript
// Normal mode: Calculate previous Monday
const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE);
const monday = new Date(reference);
const dayOfWeek = reference.getDay();
const daysSinceMonday = (dayOfWeek + 6) % 7;
monday.setDate(monday.getDate() - daysSinceMonday);
monday.setHours(12, 0, 0, 0);
const weekEndDate = formatDate(monday);
const graceDeadline = getGraceDeadline(monday);
return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
```

**Difference**:
- **Testing**: Uses today's UTC date as `week_end_date`
- **Normal**: Calculates previous Monday 12:00 ET as `week_end_date`

**Impact**: ⚠️ **Different logic** - But both use `getGraceDeadline()` which handles timing differences

---

### 3. **Commitment Deadline Calculation** (`getCommitmentDeadline()`)

**Testing Mode** (lines 228-238):
```typescript
// Prefer stored precise timestamp if available (testing mode with new column)
if (candidate.commitment.week_end_timestamp) {
  return new Date(candidate.commitment.week_end_timestamp);
}

// Fallback: In testing mode, calculate deadline from created_at
if (TESTING_MODE && candidate.commitment.created_at) {
  const createdAt = new Date(candidate.commitment.created_at);
  return new Date(createdAt.getTime() + (3 * 60 * 1000)); // 3 minutes after creation
}
```

**Normal Mode** (lines 240-244):
```typescript
// Normal mode: deadline is Monday 12:00 ET (week_end_date)
const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
mondayET.setHours(12, 0, 0, 0);
return mondayET;
```

**Difference**:
- **Testing**: Uses `week_end_timestamp` (precise) or calculates from `created_at + 3 minutes`
- **Normal**: Uses `week_end_date` parsed as Monday 12:00 ET

**Impact**: ⚠️ **Different logic** - But both result in correct deadline for their respective modes

---

### 4. **Manual Trigger Requirement** (Handler Entry Point)

**Testing Mode** (lines 504-514):
```typescript
if (TESTING_MODE) {
  const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
  if (!isManualTrigger) {
    console.log("run-weekly-settlement: Skipped - testing mode active (use x-manual-trigger header)");
    return new Response(
      JSON.stringify({ message: "Settlement skipped - testing mode active. Use x-manual-trigger: true header to run." }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }
  // In testing mode, skip authentication check - function is public
  console.log("run-weekly-settlement: Testing mode - public access allowed with x-manual-trigger header");
}
```

**Normal Mode** (lines 515-518):
```typescript
else {
  // In production mode, authentication is still required by Edge Function gateway
  // (This code path won't execute if gateway requires auth, but kept for clarity)
}
```

**Difference**:
- **Testing**: Requires `x-manual-trigger: true` header, skips auth
- **Normal**: No header requirement, auth handled by Edge Function gateway

**Impact**: ⚠️ **Different entry point behavior** - This is the main operational difference

---

### 5. **Core Settlement Logic** (Same for Both Modes)

**Lines 550-616**: The actual settlement logic is **identical** for both modes:

```typescript
for (const candidate of candidates) {
  const hasUsage = hasSyncedUsage(candidate);
  if (shouldSkipBecauseSettled(candidate)) continue;
  
  // CRITICAL: Always wait for grace period to expire before settling
  if (!isGracePeriodExpired(candidate)) {
    summary.graceNotExpired += 1;
    continue;  // Skip settlement - wait for grace period to expire
  }

  // Grace period has expired - now check usage and charge accordingly
  const chargeType: ChargeType = hasUsage ? "actual" : "worst_case";
  const amountCents = getChargeAmount(candidate, chargeType);
  // ... charge logic ...
}
```

**Key Functions Used** (all mode-agnostic):
- `hasSyncedUsage()` - Same logic
- `isGracePeriodExpired()` - Uses `getGraceDeadline()` (handles both modes)
- `getChargeAmount()` - Same logic
- `chargeCandidate()` - Same Stripe logic

**Impact**: ✅ **Identical core logic** - The business rules are the same

---

## Summary: What's Different vs What's the Same

### ✅ **Same (Core Logic)**
1. **Settlement decision logic** - When to charge, what to charge
2. **Grace period checking** - Uses `getGraceDeadline()` which abstracts timing
3. **Usage detection** - Same `hasSyncedUsage()` logic
4. **Stripe charging** - Same payment intent creation
5. **Database updates** - Same record updates

### ⚠️ **Different (Configuration/Entry Point)**
1. **Timing durations** - 3 min vs 7 days, 1 min vs 24 hours (abstracted)
2. **Week target resolution** - Today's date vs previous Monday
3. **Deadline calculation** - `week_end_timestamp` vs `week_end_date` parsing
4. **Manual trigger requirement** - Testing mode requires header
5. **Authentication** - Testing mode skips auth

---

## Are They Close Enough?

### ✅ **Yes - Core Logic is Identical**

The **business logic** (when to charge, what to charge, how to charge) is **100% identical**. The differences are:
- **Timing** (abstracted via helper functions)
- **Entry point** (manual trigger vs cron)
- **Date resolution** (today vs Monday calculation)

### ⚠️ **Potential Issues**

1. **Week Target Resolution**:
   - Testing: Uses today's UTC date
   - Normal: Calculates previous Monday
   - **Risk**: Different date selection logic could cause edge cases

2. **Deadline Calculation**:
   - Testing: Uses `week_end_timestamp` (precise)
   - Normal: Parses `week_end_date` as Monday 12:00 ET
   - **Risk**: Normal mode relies on date parsing, testing mode uses precise timestamp

3. **Manual Trigger Requirement**:
   - Testing: Requires header (prevents automatic cron)
   - Normal: No header requirement
   - **Risk**: Different operational behavior

---

## Recommendations

### 1. **Unify Week Target Resolution**

**Current**: Different logic for testing vs normal mode

**Suggestion**: Both modes should use the same approach:
- Use `week_end_date` from commitments (already stored)
- Both modes query by `week_end_date`
- No need for different resolution logic

**Impact**: Would make both modes more similar

### 2. **Unify Deadline Calculation**

**Current**: Testing uses `week_end_timestamp`, normal parses `week_end_date`

**Suggestion**: 
- Normal mode should also use `week_end_timestamp` if available
- Fall back to parsing `week_end_date` only if timestamp is NULL
- This is already partially done (line 230 checks `week_end_timestamp` first)

**Impact**: Would make both modes more similar

### 3. **Keep Manual Trigger for Testing**

**Current**: Testing requires manual trigger header

**Reason**: This is intentional - allows controlled testing without interfering with production cron

**Impact**: ✅ **Keep as-is** - This is a feature, not a bug

---

## Conclusion

**Are we using one codebase?** ✅ **YES**

**Are they close?** ✅ **YES** - Core settlement logic is identical

**Differences are**:
1. ✅ **Timing** (abstracted - good)
2. ⚠️ **Week target resolution** (different logic - could be unified)
3. ⚠️ **Deadline calculation** (different sources - already partially unified)
4. ✅ **Manual trigger** (intentional difference - keep as-is)

**Recommendation**: The codebase is already well-designed with shared logic. The main differences are operational (manual trigger) and configuration (timing), which are appropriate. The week target resolution could be unified, but it's not critical since both modes query by `week_end_date` correctly.


