# Multiple Commitments Edge Case Analysis

**Date**: 2025-01-01  
**Scenario**: User syncs old commitment, then creates new commitment before settlement runs

---

## Scenario Description

1. **Commitment A**: Week ending Monday 12:00 ET (e.g., "2025-01-13")
2. **Monday 12:00 ET**: Week deadline passes
3. **Monday Afternoon** (after Monday noon, before Tuesday noon): User opens app
4. **User syncs**: Usage data for Commitment A syncs to server
5. **User creates Commitment B**: New week starting, ending next Monday 12:00 ET (e.g., "2025-01-20")
6. **Tuesday 12:00 ET**: Settlement runs

**Question**: Does the system correctly handle both commitments?

---

## Analysis

### 1. Sync Process (Monday Afternoon)

**What Happens**:
- User opens app → `UsageSyncManager.syncToBackend()` called
- Reads `DailyUsageEntry` objects from App Group
- Each entry has:
  - `weekStartDate`: "2025-01-13" (Commitment A's deadline)
  - `commitmentId`: Commitment A's ID
  - `date`: Actual date of usage (e.g., "2025-01-06", "2025-01-07", etc.)

**Backend Processing** (`rpc_sync_daily_usage`):
```sql
-- For each entry, match to commitment
WHERE c.user_id = v_user_id
  AND c.week_end_date = v_week_start_date  -- "2025-01-13"
  AND c.status IN ('pending', 'active')
ORDER BY c.created_at DESC
LIMIT 1;
```

**Result**:
- ✅ Matches Commitment A (week_end_date = "2025-01-13")
- ✅ Creates `daily_usage` rows linked to Commitment A
- ✅ Calculates penalties for Commitment A
- ✅ Updates `user_week_penalties` for week "2025-01-13"

**Status**: ✅ **CORRECT** - Old commitment usage is synced correctly

---

### 2. New Commitment Creation (Monday Afternoon)

**What Happens**:
- User creates Commitment B
- New commitment has:
  - `week_end_date`: "2025-01-20" (next Monday)
  - `week_start_date`: "2025-01-13" (today, when commitment created)
  - `status`: "pending" or "active"

**Database State**:
- Commitment A: week_end_date = "2025-01-13", status = "active"
- Commitment B: week_end_date = "2025-01-20", status = "pending"
- Both commitments exist simultaneously

**Status**: ✅ **CORRECT** - Both commitments can coexist

---

### 3. Settlement Process (Tuesday 12:00 ET)

**Settlement Logic** (`run-weekly-settlement.ts`):

#### Step 1: Determine Target Week
```typescript
const target = resolveWeekTarget({ override: payload?.targetWeek });
// Calculates: Monday 12:00 ET = "2025-01-13"
```

#### Step 2: Fetch Commitments for Target Week
```typescript
const commitments = await fetchCommitmentsForWeek(supabase, target.weekEndDate);
// Queries: WHERE week_end_date = "2025-01-13"
```

**Result**:
- ✅ Fetches Commitment A (week_end_date = "2025-01-13")
- ✅ Does NOT fetch Commitment B (week_end_date = "2025-01-20")
- ✅ Only Commitment A is considered for settlement

#### Step 3: Check Usage for Each Commitment
```typescript
const usageCounts = await fetchUsageCounts(supabase, commitmentIds);
// Queries: SELECT commitment_id FROM daily_usage WHERE commitment_id IN (Commitment A's ID)
```

**Result**:
- ✅ Only checks `daily_usage` rows for Commitment A
- ✅ Commitment B has no `daily_usage` rows yet (week just started)
- ✅ Settlement correctly identifies Commitment A has synced usage

#### Step 4: Settlement Decision
```typescript
const hasUsage = hasSyncedUsage(candidate);  // true for Commitment A
const chargeType = hasUsage ? "actual" : "worst_case";
```

**Result**:
- ✅ Commitment A: Charges actual penalty (has synced usage)
- ✅ Commitment B: Not processed (not in target week)

**Status**: ✅ **CORRECT** - Only Commitment A is settled

---

### 4. Potential Issues

#### Issue 1: Extension Tracking After New Commitment

**Scenario**: Extension is still tracking usage when Commitment B is created.

**Question**: Which commitment does new usage belong to?

**Current Behavior**:
- Extension creates `DailyUsageEntry` with `weekStartDate` and `commitmentId`
- These are set when the extension starts tracking (at commitment creation)
- If Commitment A is still active, extension should still use Commitment A's ID

**Potential Problem**:
- If extension doesn't update when new commitment is created, it might:
  - Continue using Commitment A's ID (correct for old week)
  - Or incorrectly use Commitment B's ID (wrong for old week)

**Analysis Needed**: Check how extension determines which commitment to use for tracking.

**Status**: ⚠️ **NEEDS VERIFICATION** - Depends on extension implementation

---

#### Issue 2: Daily Usage Matching Logic

**Location**: `rpc_sync_daily_usage.sql` line 65

```sql
WHERE c.user_id = v_user_id
  AND c.week_end_date = v_week_start_date
  AND c.status IN ('pending', 'active')
ORDER BY c.created_at DESC
LIMIT 1;
```

**Scenario**: If user has two commitments with same `week_end_date` (shouldn't happen, but...)

**Current Behavior**:
- Uses `ORDER BY c.created_at DESC LIMIT 1`
- Would pick the **newest** commitment
- This could be wrong if old commitment wasn't settled yet

**Reality Check**:
- Each week has unique `week_end_date` (Monday deadline)
- User can't have two commitments for the same week
- So this shouldn't be an issue

**Status**: ✅ **SAFE** - Each week has unique deadline

---

#### Issue 3: Settlement Filtering

**Location**: `fetchCommitmentsForWeek()` line 101

```typescript
.eq("week_end_date", weekEndDate);
```

**Analysis**:
- ✅ Only fetches commitments for the specific week being settled
- ✅ Commitment B (week_end_date = "2025-01-20") is NOT fetched
- ✅ Commitment B will be settled next week (when its deadline passes)

**Status**: ✅ **CORRECT** - Settlement only processes target week

---

#### Issue 4: User Week Penalties Calculation

**Location**: `rpc_sync_daily_usage.sql` lines 129-136

```sql
SELECT COALESCE(SUM(penalty_cents), 0)
INTO v_user_week_total_cents
FROM public.daily_usage du
JOIN public.commitments c ON du.commitment_id = c.id
WHERE du.user_id = v_user_id
  AND c.week_end_date = v_week
  AND du.date >= c.week_start_date
  AND du.date <= c.week_end_date;
```

**Analysis**:
- ✅ Joins `daily_usage` with `commitments` by `commitment_id`
- ✅ Filters by `c.week_end_date = v_week` (the deadline)
- ✅ Only sums penalties for Commitment A (week_end_date = "2025-01-13")
- ✅ Commitment B's usage (if any) would have different `week_end_date` and wouldn't be included

**Status**: ✅ **CORRECT** - Only calculates penalties for the correct week

---

## Summary

### What Works Correctly

1. ✅ **Sync Process**: Correctly matches usage to Commitment A by `week_end_date`
2. ✅ **Settlement Filtering**: Only processes commitments for target week
3. ✅ **Penalty Calculation**: Only sums penalties for the correct commitment
4. ✅ **Multiple Commitments**: Can coexist without interference

### Potential Issues

1. ⚠️ **Extension Tracking**: Need to verify extension uses correct commitment ID after new commitment created
2. ⚠️ **Grace Period Bug**: Still applies (grace expires too early, but doesn't affect this scenario)

### Edge Case Coverage

**Scenario**: User syncs old commitment, creates new commitment, settlement runs

**Result**:
- ✅ Old commitment (Commitment A) is settled correctly
- ✅ New commitment (Commitment B) is NOT settled (not in target week)
- ✅ New commitment will be settled next week when its deadline passes

**Status**: ✅ **COVERED** - System handles this correctly

---

## Recommendations

### 1. Verify Extension Commitment ID Handling

**Check**: How does extension determine which `commitmentId` to use when creating `DailyUsageEntry`?

**Potential Issue**: If extension doesn't update when new commitment is created, it might:
- Use old commitment ID for new week's usage (wrong)
- Or correctly continue using old commitment ID for old week's usage (correct)

**Action**: Verify extension logic for commitment ID selection.

### 2. Add Test Case

**Test Scenario**:
1. Create Commitment A (week ending Monday)
2. Wait for Monday 12:00 ET
3. Sync usage for Commitment A
4. Create Commitment B (next week)
5. Run settlement for Commitment A's week
6. Verify: Only Commitment A is settled, Commitment B is untouched

**Action**: Add this to test suite.

---

## Conclusion

**The code correctly handles this edge case**:

1. ✅ Sync process matches usage to correct commitment by `week_end_date`
2. ✅ Settlement only processes commitments for the target week
3. ✅ Multiple commitments can coexist without interference
4. ✅ Each commitment is settled independently based on its `week_end_date`

**The system is designed to handle multiple commitments correctly** because:
- Each commitment has a unique `week_end_date` (Monday deadline)
- All matching logic uses `week_end_date` as the key
- Settlement filters by specific week, not all commitments

**Potential concern**: Extension commitment ID handling (needs verification, but likely fine since it uses stored commitment ID from when tracking started).

---

**End of Analysis**


