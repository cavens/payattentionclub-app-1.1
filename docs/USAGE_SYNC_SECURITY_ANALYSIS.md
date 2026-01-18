# Usage Sync Security & Anti-Cheating Analysis

**Date**: 2026-01-17  
**Status**: Security Review Required  
**Priority**: High

## Executive Summary

**Current Behavior**: Usage entries are synced to the backend throughout the week, but are only marked as "synced" in the app after the deadline passes. This allows entries to be re-synced multiple times as usage increases.

**Security Assessment**: ⚠️ **MODERATE RISK** - The current approach is acceptable but has vulnerabilities that should be addressed.

**Recommendation**: ✅ **Keep current approach** (sync throughout week, mark as synced after deadline), but **add backend validation** to prevent usage from decreasing.

---

## Current Implementation

### How It Works

1. **During the Week (Before Deadline)**:
   - Usage entries are synced to backend multiple times as usage increases
   - Entries are NOT marked as "synced" in the app
   - Backend accepts and updates usage values via `ON CONFLICT ... DO UPDATE SET`

2. **After Deadline**:
   - Usage entries are marked as "synced" in the app
   - No further re-syncs occur (entries remain synced)
   - Settlement uses the final synced values from the database

### Backend Behavior

**File**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`

```sql
ON CONFLICT (user_id, date, commitment_id)
DO UPDATE SET
  used_minutes = EXCLUDED.used_minutes,  -- ⚠️ Always accepts latest value
  ...
```

**Key Finding**: The backend **always accepts the latest value** sent, with **no validation** that usage can only increase.

---

## Security Vulnerabilities

### 1. ⚠️ Usage Can Be Decreased (HIGH RISK)

**Attack Vector**:
- User modifies App Group data to show lower usage
- User syncs the manipulated data before deadline
- Backend accepts the lower value (no validation)
- Penalty is reduced

**Example**:
- Day 1: User uses 60 minutes → syncs → backend stores 60 minutes
- Day 2: User uses 120 minutes → syncs → backend stores 120 minutes
- Day 3: User modifies app data to show 30 minutes → syncs → backend **overwrites with 30 minutes** ❌
- Result: Penalty calculated from 30 minutes instead of 120 minutes

**Impact**: ⚠️ **HIGH** - Users can reduce their penalties by manipulating data

### 2. ⚠️ No Independent Verification (MEDIUM RISK)

**Attack Vector**:
- User modifies the app to send fake usage data
- Backend trusts whatever the app sends (no independent verification)
- No way to detect manipulation

**Limitations**:
- DeviceActivityMonitorExtension writes to App Group (system-level, harder to manipulate)
- But a determined attacker with a jailbroken device or modified app could still manipulate data

**Impact**: ⚠️ **MEDIUM** - Requires technical knowledge, but possible

### 3. ⚠️ App Data Can Be Cleared (LOW-MEDIUM RISK)

**Attack Vector**:
- User clears app data or reinstalls app
- All usage entries are lost
- User could potentially avoid syncing usage before deadline

**Mitigation**:
- Usage is stored in App Group (persists across app reinstalls)
- But if App Group is cleared, usage data is lost

**Impact**: ⚠️ **LOW-MEDIUM** - Requires clearing App Group specifically

### 4. ✅ Multiple Syncs Create Audit Trail (POSITIVE)

**Benefit**:
- Multiple syncs throughout the week create a progression history
- Can detect suspicious patterns (e.g., usage suddenly decreasing)
- `reported_at` timestamp tracks when each sync occurred

**Impact**: ✅ **POSITIVE** - Helps detect manipulation

---

## Comparison: Sync Throughout vs. Only After Deadline

### Option A: Sync Throughout Week (Current Approach) ✅ RECOMMENDED

**Pros**:
- ✅ Creates audit trail (multiple syncs show progression)
- ✅ Can detect suspicious patterns (usage decreasing)
- ✅ Settlement uses final value anyway
- ✅ Better user experience (real-time updates)

**Cons**:
- ⚠️ Allows multiple syncs (potential for manipulation)
- ⚠️ No validation that usage can only increase

**Security**: ⚠️ **MODERATE** - Acceptable with validation added

### Option B: Only Sync After Deadline ❌ NOT RECOMMENDED

**Pros**:
- ✅ Single sync point (less opportunity for manipulation)
- ✅ Usage is finalized before sync

**Cons**:
- ❌ No audit trail (can't see usage progression)
- ❌ User could manipulate data right before deadline
- ❌ No way to detect manipulation (no history)
- ❌ Poor user experience (no real-time updates)

**Security**: ❌ **LOW** - Less secure, no audit trail

---

## Recommended Security Enhancements

### 1. ✅ Add Backend Validation: Prevent Usage Decrease (CRITICAL)

**Implementation**: Modify `rpc_sync_daily_usage.sql` to only accept increases:

```sql
ON CONFLICT (user_id, date, commitment_id)
DO UPDATE SET
  -- Only update if new value is greater than existing value
  used_minutes = GREATEST(
    public.daily_usage.used_minutes,  -- Keep existing if higher
    EXCLUDED.used_minutes             -- Use new if higher
  ),
  ...
```

**Impact**: ✅ **HIGH** - Prevents users from reducing their usage/penalty

**Trade-off**: ⚠️ If legitimate usage correction is needed (e.g., bug fix), would require manual database update

### 2. ✅ Add Suspicious Activity Detection (RECOMMENDED)

**Implementation**: Log or flag when usage decreases:

```sql
-- In rpc_sync_daily_usage.sql
IF EXCLUDED.used_minutes < public.daily_usage.used_minutes THEN
  -- Log suspicious activity
  INSERT INTO suspicious_activity_log (
    user_id, date, old_value, new_value, reason
  ) VALUES (
    v_user_id, v_date, 
    public.daily_usage.used_minutes, 
    EXCLUDED.used_minutes,
    'usage_decreased'
  );
END IF;
```

**Impact**: ✅ **MEDIUM** - Helps detect and investigate manipulation attempts

### 3. ✅ Add Usage Progression Validation (OPTIONAL)

**Implementation**: Validate that usage progression is reasonable:

```sql
-- Check if usage increase is suspiciously large
IF EXCLUDED.used_minutes > public.daily_usage.used_minutes + 1440 THEN
  -- More than 24 hours in one sync - suspicious
  -- Flag for review
END IF;
```

**Impact**: ✅ **LOW** - Helps detect extreme manipulation, but may have false positives

### 4. ✅ Keep Current Approach: Sync Throughout Week (RECOMMENDED)

**Rationale**:
- Creates audit trail
- Better user experience
- Can detect suspicious patterns
- Settlement uses final value anyway

**Impact**: ✅ **POSITIVE** - Current approach is correct, just needs validation

---

## Final Recommendation

### ✅ **Keep Current Approach** (Sync Throughout Week)

**With These Enhancements**:

1. **CRITICAL**: Add backend validation to prevent usage from decreasing
   - Use `GREATEST()` to only accept increases
   - Prevents penalty reduction attacks

2. **RECOMMENDED**: Add suspicious activity logging
   - Track when usage decreases (even if rejected)
   - Helps detect manipulation attempts

3. **OPTIONAL**: Add usage progression validation
   - Flag extreme increases (e.g., >24 hours in one sync)
   - Helps detect obvious manipulation

### ❌ **Do NOT** Switch to "Only Sync After Deadline"

**Reasons**:
- Less secure (no audit trail)
- No way to detect manipulation
- Poor user experience
- User could still manipulate data right before deadline

---

## Implementation Priority

1. **HIGH**: Add backend validation (prevent usage decrease)
2. **MEDIUM**: Add suspicious activity logging
3. **LOW**: Add usage progression validation

---

## Testing Recommendations

1. **Test Usage Decrease Prevention**:
   - Sync usage: 60 minutes
   - Try to sync lower value: 30 minutes
   - Verify backend rejects or keeps 60 minutes

2. **Test Audit Trail**:
   - Sync usage multiple times throughout week
   - Verify all syncs are logged with timestamps
   - Verify progression is visible in database

3. **Test Edge Cases**:
   - What happens if user clears app data?
   - What happens if user reinstalls app?
   - What happens if user syncs after deadline?

---

## Related Documentation

- `supabase/remote_rpcs/rpc_sync_daily_usage.sql` - Current implementation
- `payattentionclub-app-1.1/Utilities/UsageSyncManager.swift` - Frontend sync logic
- `TODO.md` - Task #22 (Comprehensive Test Review)

---

## Conclusion

**Current approach is acceptable** but needs **backend validation** to prevent usage from decreasing. The approach of syncing throughout the week (but only marking as synced after deadline) is **more secure** than only syncing after deadline because it creates an audit trail and allows detection of suspicious patterns.

**Action Required**: Add backend validation to prevent usage decrease (HIGH priority).


