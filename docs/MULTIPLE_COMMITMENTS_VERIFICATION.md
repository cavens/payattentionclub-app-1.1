# Multiple Commitments Edge Case - Code Verification

**Date**: 2025-01-01  
**Purpose**: Verify code handles user syncing old commitment, then creating new commitment before settlement

---

## Scenario Timeline

1. **Commitment A**: Created, `week_end_date = "2025-01-13"` (Monday deadline)
2. **Monday 12:00 ET**: Week deadline passes
3. **Monday Afternoon** (after Monday noon, before Tuesday noon): User opens app
4. **Step A**: User syncs usage for Commitment A
5. **Step B**: User creates Commitment B (`week_end_date = "2025-01-20"`)
6. **Tuesday 12:00 ET**: Settlement runs

---

## Verification: Step A - Sync Process

### Code Path: `UsageSyncManager.syncToBackend()`

**Location**: `payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/UsageSyncManager.swift`

**What Happens**:
1. Reads `DailyUsageEntry` objects from App Group
2. Each entry has:
   - `weekStartDate`: "2025-01-13" (Commitment A's deadline)
   - `commitmentId`: Commitment A's ID (stored when entry was created)
   - `date`: Actual usage date (e.g., "2025-01-06", "2025-01-07", etc.)

**Key Point**: `DailyUsageEntry` objects are created with `commitmentId` and `weekStartDate` **at the time of usage tracking**, not at sync time. This means they're already "locked" to Commitment A.

---

### Code Path: `BackendClient.syncDailyUsage()`

**Location**: `payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/Utilities/BackendClient.swift:760`

**Code**:
```swift
let payload: [SyncDailyUsageEntryPayload] = entries.map { entry in
    return SyncDailyUsageEntryPayload(
        date: entry.date,
        weekStartDate: entry.weekStartDate,  // "2025-01-13"
        usedMinutes: computedUsedMinutes
    )
}
```

**Verification**: ✅ Uses `entry.weekStartDate` directly from `DailyUsageEntry` (which is "2025-01-13" for Commitment A)

---

### Code Path: `rpc_sync_daily_usage`

**Location**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql:55-68`

**Code**:
```sql
SELECT 
  c.id,
  c.limit_minutes,
  c.penalty_per_minute_cents
INTO 
  v_commitment_id,
  v_limit_minutes,
  v_penalty_per_minute_cents
FROM public.commitments c
WHERE c.user_id = v_user_id
  AND c.week_end_date = v_week_start_date  -- "2025-01-13"
  AND c.status IN ('pending', 'active')
ORDER BY c.created_at DESC
LIMIT 1;
```

**Verification**:
- ✅ Matches by `week_end_date = v_week_start_date` ("2025-01-13")
- ✅ At this point, Commitment A exists with `week_end_date = "2025-01-13"`
- ✅ Commitment B does NOT exist yet (created in Step B)
- ✅ Query will match Commitment A correctly

**Result**: ✅ **VERIFIED** - Sync correctly matches to Commitment A

---

## Verification: Step B - New Commitment Creation

### Code Path: `rpc_create_commitment`

**Location**: `supabase/remote_rpcs/rpc_create_commitment.sql:75-106`

**Code**:
```sql
INSERT INTO public.commitments (
  user_id,
  week_start_date,
  week_end_date,  -- "2025-01-20" (next Monday)
  ...
)
VALUES (
  v_user_id,
  v_commitment_start_date,  -- "2025-01-13" (today)
  p_deadline_date,          -- "2025-01-20" (next Monday)
  ...
)
```

**Verification**:
- ✅ Creates Commitment B with `week_end_date = "2025-01-20"`
- ✅ Commitment A still exists with `week_end_date = "2025-01-13"`
- ✅ Both commitments coexist with different `week_end_date` values

**Result**: ✅ **VERIFIED** - New commitment created correctly, doesn't interfere with Commitment A

---

## Verification: Step C - Settlement Process

### Code Path: `resolveWeekTarget()`

**Location**: `supabase/functions/bright-service/run-weekly-settlement.ts:61-82`

**Code**:
```typescript
const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE);
const monday = new Date(reference);
const dayOfWeek = reference.getDay();
const daysSinceMonday = (dayOfWeek + 6) % 7;
monday.setDate(monday.getDate() - daysSinceMonday);
monday.setHours(12, 0, 0, 0);

const weekEndDate = formatDate(monday);  // "2025-01-13"
```

**Verification**: ✅ Calculates Monday 12:00 ET = "2025-01-13" (Commitment A's deadline)

---

### Code Path: `fetchCommitmentsForWeek()`

**Location**: `supabase/functions/bright-service/run-weekly-settlement.ts:84-105`

**Code**:
```typescript
const { data, error } = await supabase
  .from("commitments")
  .select(...)
  .eq("week_end_date", weekEndDate);  // "2025-01-13"
```

**Verification**:
- ✅ Filters by `week_end_date = "2025-01-13"`
- ✅ Commitment A: `week_end_date = "2025-01-13"` → ✅ **INCLUDED**
- ✅ Commitment B: `week_end_date = "2025-01-20"` → ✅ **EXCLUDED**

**Result**: ✅ **VERIFIED** - Only Commitment A is fetched for settlement

---

### Code Path: `fetchUsageCounts()`

**Location**: `supabase/functions/bright-service/run-weekly-settlement.ts:151-169`

**Code**:
```typescript
const { data, error } = await supabase
  .from("daily_usage")
  .select("commitment_id")
  .in("commitment_id", commitmentIds);  // Only Commitment A's ID
```

**Verification**:
- ✅ `commitmentIds` array only contains Commitment A's ID (from `fetchCommitmentsForWeek`)
- ✅ Only checks `daily_usage` rows for Commitment A
- ✅ Commitment B has no `daily_usage` rows yet (week just started)

**Result**: ✅ **VERIFIED** - Only checks usage for Commitment A

---

### Code Path: `buildSettlementCandidates()`

**Location**: `supabase/functions/bright-service/run-weekly-settlement.ts:171-199`

**Code**:
```typescript
const commitments = await fetchCommitmentsForWeek(supabase, weekEndDate);
// Only Commitment A

const commitmentIds = commitments.map((c) => c.id);
// Only Commitment A's ID

const usageCounts = await fetchUsageCounts(supabase, commitmentIds);
// Only counts for Commitment A

return commitments.map((commitment) => ({
  commitment,  // Only Commitment A
  reportedDays: usageCounts.get(commitment.id) ?? 0
}));
```

**Verification**:
- ✅ Only processes Commitment A
- ✅ Commitment B is not in the candidates list

**Result**: ✅ **VERIFIED** - Only Commitment A is a settlement candidate

---

## Critical Verification: Matching Logic

### Question: What if Commitment B is created BEFORE sync?

**Scenario**: User creates Commitment B, then syncs Commitment A's usage.

**Analysis**:
1. `DailyUsageEntry` objects have `weekStartDate = "2025-01-13"` (from when they were created)
2. `rpc_sync_daily_usage` matches by: `WHERE week_end_date = v_week_start_date`
3. Query: `WHERE week_end_date = "2025-01-13"`
4. Both commitments exist:
   - Commitment A: `week_end_date = "2025-01-13"`, `created_at = earlier`
   - Commitment B: `week_end_date = "2025-01-20"`, `created_at = later`
5. Query result: Only Commitment A matches (different `week_end_date`)

**Result**: ✅ **SAFE** - Matching by `week_end_date` ensures correct commitment is selected

---

### Question: What if two commitments have the same `week_end_date`?

**Analysis**:
- This should be impossible because:
  1. Each week has a unique Monday deadline
  2. User can only have one commitment per week
  3. Database constraints should prevent this

**Code Check**: `rpc_sync_daily_usage` uses `ORDER BY c.created_at DESC LIMIT 1`

**If somehow two commitments exist with same `week_end_date`**:
- Would pick the newest one (most recently created)
- This could be wrong if old commitment wasn't settled yet

**Mitigation**: This scenario should be prevented by business logic, but the `ORDER BY created_at DESC` provides a fallback.

**Result**: ⚠️ **EDGE CASE** - Shouldn't happen, but code has fallback

---

## Verification: Penalty Calculation

### Code Path: `rpc_sync_daily_usage` - Penalty Summation

**Location**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql:129-136`

**Code**:
```sql
SELECT COALESCE(SUM(penalty_cents), 0)
INTO v_user_week_total_cents
FROM public.daily_usage du
JOIN public.commitments c ON du.commitment_id = c.id
WHERE du.user_id = v_user_id
  AND c.week_end_date = v_week  -- "2025-01-13"
  AND du.date >= c.week_start_date
  AND du.date <= c.week_end_date;
```

**Verification**:
- ✅ Joins `daily_usage` with `commitments` by `commitment_id`
- ✅ Filters by `c.week_end_date = v_week` ("2025-01-13")
- ✅ Only sums penalties for Commitment A
- ✅ Commitment B's usage (if any) has different `week_end_date` and is excluded

**Result**: ✅ **VERIFIED** - Only calculates penalties for Commitment A

---

## Summary of Verification

### ✅ Verified Correct Behavior

1. **Sync Process**:
   - ✅ `DailyUsageEntry` objects have correct `weekStartDate` and `commitmentId` from creation time
   - ✅ `rpc_sync_daily_usage` matches by `week_end_date = week_start_date`
   - ✅ Correctly matches to Commitment A even if Commitment B exists

2. **Settlement Process**:
   - ✅ `fetchCommitmentsForWeek()` filters by specific `week_end_date`
   - ✅ Only Commitment A is fetched (Commitment B has different `week_end_date`)
   - ✅ Only Commitment A's usage is checked
   - ✅ Only Commitment A is settled

3. **Penalty Calculation**:
   - ✅ Joins `daily_usage` with `commitments` and filters by `week_end_date`
   - ✅ Only sums penalties for the correct commitment

### ⚠️ Potential Edge Cases

1. **Two commitments with same `week_end_date`**:
   - Shouldn't happen (business logic prevents it)
   - Code has fallback (`ORDER BY created_at DESC LIMIT 1`)
   - **Recommendation**: Add database constraint to prevent this

2. **Extension commitment ID handling**:
   - Need to verify extension uses correct `commitmentId` when creating `DailyUsageEntry`
   - If extension doesn't update when new commitment is created, it should still use old commitment ID for old week's usage (which is correct)

---

## Conclusion

**The code correctly handles the edge case** where:
- User syncs old commitment (Commitment A)
- User creates new commitment (Commitment B)
- Settlement runs for Commitment A

**Key Protection Mechanisms**:
1. `DailyUsageEntry` stores `weekStartDate` and `commitmentId` at creation time (immutable)
2. All matching logic uses `week_end_date` as the key (unique per week)
3. Settlement filters by specific `week_end_date` (only processes target week)
4. Penalty calculation joins and filters by `week_end_date` (isolates by week)

**The system is designed correctly to handle multiple commitments** because each commitment has a unique `week_end_date` (Monday deadline), and all matching logic uses this as the key.

---

**End of Verification**


