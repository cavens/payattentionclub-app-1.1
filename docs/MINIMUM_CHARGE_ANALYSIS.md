# Minimum Charge Amount Analysis
## Investigation: Missing 5-Cent/$5 Minimum

**Date**: 2026-01-15  
**Issue**: User reports that a change from "1-cent minimum to 5-cent minimum" has disappeared from the code, and is concerned other changes may have disappeared as well.

---

## Current State Analysis

### Backend: `calculate_max_charge_cents()` Function

**Location**: `supabase/remote_rpcs/calculate_max_charge_cents.sql`

**Current Minimum**: **$15.00 (1500 cents)**

```sql
-- Line 100-101
-- Apply bounds: minimum $15 (1500 cents), maximum $1000 (100000 cents)
v_result_cents := GREATEST(1500, LEAST(100000, FLOOR(v_base_amount_cents)::integer));
```

**Also in early return case**:
```sql
-- Line 48-49
IF v_minutes_remaining <= 0 THEN
    RETURN 1500; -- $15 minimum
END IF;
```

---

## Historical State Analysis

### Old Schema Files (Backup/Dump Files)

**Location**: `supabase/remote_schema.sql` and `supabase/remote_schema_staging.sql`

**Old Minimum**: **$5.00 (500 cents)**

```sql
-- Line 140-141
if v_minutes_remaining > 0 then
    v_max_charge_cents := greatest(500, floor(v_max_charge_cents)::int);
else
    v_max_charge_cents := 0;
end if;
```

**Context**: This was in the old `rpc_create_commitment` function, which had inline calculation logic (not using `calculate_max_charge_cents()`).

---

## Migration History

### Migration: `20251231180000_update_calculate_max_charge_cents.sql`

**Date**: 2025-12-31  
**Purpose**: Update authorization amount calculation with new formula

**Changes**:
- Created/updated `calculate_max_charge_cents()` function
- **Set minimum to $15.00 (1500 cents)**
- Replaced old inline calculation in `rpc_create_commitment`

**Key Change**:
```sql
-- OLD (in rpc_create_commitment):
v_max_charge_cents := greatest(500, floor(v_max_charge_cents)::int);  -- $5.00 minimum

-- NEW (in calculate_max_charge_cents):
v_result_cents := GREATEST(1500, LEAST(100000, FLOOR(v_base_amount_cents)::integer));  -- $15.00 minimum
```

### Migration: `20260101000000_cap_strictness_multiplier.sql`

**Date**: 2026-01-01  
**Purpose**: Cap strictness multiplier at 10x

**No minimum change** - still $15.00 (1500 cents)

---

## What Happened?

### Timeline of Changes

1. **Original Code** (in old schema dumps):
   - Minimum: **$5.00 (500 cents)**
   - Logic: `greatest(500, floor(v_max_charge_cents)::int)`
   - Location: Inline in `rpc_create_commitment` function

2. **Migration 2025-12-31**:
   - **Changed minimum from $5.00 to $15.00**
   - Moved calculation to `calculate_max_charge_cents()` function
   - Updated both `rpc_preview_max_charge` and `rpc_create_commitment` to use new function

3. **Current State**:
   - Minimum: **$15.00 (1500 cents)**
   - All calculations use `calculate_max_charge_cents()` (single source of truth)

---

## User's Concern: "1-Cent to 5-Cent Minimum"

**Possible Interpretations**:

1. **User meant $1.00 to $5.00**:
   - Could have been an even earlier version with $1.00 (100 cents) minimum
   - Then changed to $5.00 (500 cents)
   - Now changed to $15.00 (1500 cents)

2. **User meant 1 cent to 5 cents** (literal):
   - This would be $0.01 to $0.05
   - **No evidence of this in codebase** - minimums have always been in dollars, not cents

3. **User confused about amounts**:
   - May have seen "500" in code and thought it was 5 cents
   - Actually 500 cents = $5.00

---

## Current Implementation Status

### ✅ Backend Functions Using New Minimum

1. **`calculate_max_charge_cents()`**:
   - ✅ Minimum: $15.00 (1500 cents)
   - ✅ Maximum: $1000.00 (100000 cents)
   - ✅ Used by both preview and commitment creation

2. **`rpc_preview_max_charge()`**:
   - ✅ Calls `calculate_max_charge_cents()`
   - ✅ Uses $15.00 minimum

3. **`rpc_create_commitment()`**:
   - ✅ Calls `calculate_max_charge_cents()`
   - ✅ Uses $15.00 minimum

### ⚠️ iOS App Fallback

**Location**: `AppModel.swift:203-204`

```swift
// Fallback to minimum if backend call fails
return 5.0  // $5.00 fallback
```

**Issue**: iOS app fallback is **$5.00**, but backend minimum is **$15.00**. This is a **mismatch**.

**Impact**: If backend call fails, iOS app will show $5.00, but actual commitment would require $15.00 minimum.

---

## Potential Issues Found

### 1. **iOS App Fallback Mismatch** ⚠️

**Problem**: iOS app fallback ($5.00) doesn't match backend minimum ($15.00)

**Location**: `AppModel.swift:204`

**Recommendation**: Update iOS app fallback to $15.00 to match backend minimum.

### 2. **Old Minimum Logic Removed** ✅

**Status**: This is **intentional** - the old $5.00 minimum was replaced with $15.00 minimum in migration `20251231180000_update_calculate_max_charge_cents.sql`.

**Not a bug** - it's a feature change (minimum increased from $5 to $15).

### 3. **No Evidence of 1-Cent Minimum** ❓

**Status**: No evidence in codebase of a 1-cent ($0.01) minimum ever existing.

**Possible explanations**:
- User may be thinking of a different system
- User may be confusing amounts (1 cent vs $1.00)
- May have been in a very early version not in current codebase

---

## Recommendations

### 1. **Fix iOS App Fallback** (High Priority)

**Action**: Update `AppModel.swift` fallback to match backend minimum:

```swift
// Current:
return 5.0  // $5.00 fallback

// Should be:
return 15.0  // $15.00 fallback (matches backend minimum)
```

**Why**: Ensures consistency between frontend and backend minimums.

### 2. **Document Minimum Change** (Medium Priority)

**Action**: Add comment/documentation explaining why minimum was changed from $5.00 to $15.00.

**Location**: `calculate_max_charge_cents.sql` or migration file

### 3. **Verify No Other Missing Logic** (High Priority)

**Action**: Comprehensive code review to check for other missing logic:

- Check all RPC functions for removed logic
- Check all Edge Functions for removed logic
- Compare current code with old schema dumps
- Verify all migrations were applied correctly

### 4. **Add Minimum as Configurable Constant** (Low Priority)

**Action**: Extract minimum ($15.00) as a named constant or database setting for easier maintenance.

---

## Files to Review for Missing Logic

### Backend Files

1. ✅ `supabase/remote_rpcs/calculate_max_charge_cents.sql` - **Reviewed** (has $15 minimum)
2. ✅ `supabase/remote_rpcs/rpc_preview_max_charge.sql` - **Reviewed** (uses calculate_max_charge_cents)
3. ✅ `supabase/remote_rpcs/rpc_create_commitment.sql` - **Reviewed** (uses calculate_max_charge_cents)
4. ⚠️ `supabase/remote_schema.sql` - **Old backup** (has old $5 minimum - not current)
5. ⚠️ `supabase/remote_schema_staging.sql` - **Old backup** (has old $5 minimum - not current)

### Frontend Files

1. ⚠️ `AppModel.swift:204` - **Needs update** (fallback is $5.00, should be $15.00)
2. ✅ `AuthorizationView.swift` - **Uses backend** (no hardcoded minimum)
3. ✅ `BackendClient.swift` - **Uses backend** (no hardcoded minimum)

### Migration Files

1. ✅ `20251231180000_update_calculate_max_charge_cents.sql` - **Applied** (changed to $15)
2. ✅ `20260101000000_cap_strictness_multiplier.sql` - **Applied** (still $15)

---

## Summary

### What Changed

- **Old minimum**: $5.00 (500 cents) - in old `rpc_create_commitment` inline logic
- **New minimum**: $15.00 (1500 cents) - in `calculate_max_charge_cents()` function
- **Change date**: 2025-12-31 (migration `20251231180000_update_calculate_max_charge_cents.sql`)

### What's Missing

1. ⚠️ **iOS app fallback** still uses $5.00 (should be $15.00)
2. ❓ **No evidence of 1-cent minimum** ever existing in codebase

### What's Working

1. ✅ Backend consistently uses $15.00 minimum
2. ✅ Both preview and commitment use same calculation
3. ✅ Single source of truth (`calculate_max_charge_cents()`)

---

## Next Steps

1. **Fix iOS app fallback** to $15.00
2. **Review other potential missing logic** (comprehensive code audit)
3. **Document minimum change** in code comments
4. **Verify all migrations applied** correctly in database



