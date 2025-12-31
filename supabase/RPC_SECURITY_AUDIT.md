# RPC Function Security Audit

**Date**: 2025-01-15  
**Status**: ✅ Most functions secure, 2 functions need authentication checks

---

## Summary

Audited all RPC functions with `SECURITY DEFINER` to verify they properly validate user identity and prevent unauthorized data access.

**Total Functions Audited**: 10  
**Secure Functions**: 8  
**Functions Needing Fixes**: 2

---

## ✅ Secure Functions (8)

### 1. `rpc_create_commitment`
- ✅ Uses `auth.uid()` to get user ID
- ✅ Checks authentication (raises exception if not authenticated)
- ✅ All database operations filter by `v_user_id`
- ✅ Users can only create commitments for themselves

### 2. `rpc_sync_daily_usage`
- ✅ Uses `auth.uid()` to get user ID
- ✅ Checks authentication (raises exception if not authenticated)
- ✅ All database operations filter by `v_user_id`
- ✅ Users can only sync their own usage data

### 3. `rpc_get_week_status`
- ✅ Uses `auth.uid()` to get user ID
- ✅ Checks authentication (raises exception if not authenticated)
- ✅ All database operations filter by `v_user_id`
- ✅ Users can only see their own week status

### 4. `rpc_report_usage`
- ✅ Uses `auth.uid()` to get user ID
- ✅ Checks authentication (raises exception if not authenticated)
- ✅ All database operations filter by `v_user_id`
- ✅ Users can only report their own usage

### 5. `rpc_update_monitoring_status`
- ✅ Uses `auth.uid()` to get user ID
- ✅ Checks authentication (raises exception if not authenticated)
- ✅ Verifies commitment ownership (checks `c.user_id = v_user_id`)
- ✅ Users can only update their own commitments

### 6. `handle_new_user`
- ✅ Trigger function (runs automatically on auth.users insert)
- ✅ Uses `NEW.id` from auth.users (secure by design)
- ✅ No user input, no security risk

### 7. `call_weekly_close`
- ✅ Admin function (intended for cron jobs)
- ✅ Uses service role key from database settings
- ✅ No user authentication needed (admin operation)

### 8. `calculate_max_charge_cents`
- ✅ Internal calculation function (IMMUTABLE)
- ✅ No user data access
- ✅ No authentication needed (pure calculation)

---

## ⚠️ Functions Needing Fixes (2)

### 1. `rpc_preview_max_charge`

**Issue**: Does not verify user authentication

**Current Code**:
```sql
CREATE OR REPLACE FUNCTION public.rpc_preview_max_charge(...)
SECURITY DEFINER AS $$
DECLARE
    -- No auth.uid() check!
    -- No authentication verification!
BEGIN
    -- Just calculates max charge, doesn't access user data
    ...
END;
$$;
```

**Risk**: Low (function doesn't access user data, just calculates)
**Recommendation**: Add authentication check for consistency and to prevent abuse

**Fix**:
```sql
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    -- Verify authentication
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    -- ... rest of function
```

**Priority**: Medium (low risk, but should be consistent)

---

### 2. `rpc_setup_test_data`

**Issue**: Does not verify user authentication or restrict to test users

**Current Code**:
```sql
CREATE OR REPLACE FUNCTION public.rpc_setup_test_data(...)
SECURITY DEFINER AS $$
DECLARE
    -- No auth.uid() check!
    -- No authentication verification!
    -- No restriction to test users!
BEGIN
    -- Creates test data for any user
    ...
END;
$$;
```

**Risk**: Medium (any authenticated user can create test data)
**Recommendation**: Restrict to test users only or remove from production

**Fix Options**:

**Option A**: Restrict to test users
```sql
DECLARE
    v_user_id uuid := auth.uid();
    v_is_test_user boolean;
BEGIN
    -- Verify authentication
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    
    -- Check if user is a test user
    SELECT is_test_user INTO v_is_test_user
    FROM public.users
    WHERE id = v_user_id;
    
    IF COALESCE(v_is_test_user, false) = false THEN
        RAISE EXCEPTION 'Only test users can call this function' USING ERRCODE = '42501';
    END IF;
    -- ... rest of function
```

**Option B**: Remove from production (recommended)
- Keep function in staging/test environment only
- Remove from production database
- Document that this is a test-only function

**Priority**: High (should not be callable by regular users in production)

---

## Recommendations

### Immediate Actions

1. **Fix `rpc_preview_max_charge`**: Add authentication check for consistency
2. **Fix `rpc_setup_test_data`**: Either restrict to test users or remove from production

### Best Practices

1. ✅ All user-facing RPC functions should:
   - Use `auth.uid()` to get user ID
   - Check if `v_user_id IS NULL` and raise exception
   - Filter all queries by `v_user_id`
   - Verify ownership when updating/deleting resources

2. ✅ Admin functions (like `call_weekly_close`) should:
   - Use service role key
   - Not require user authentication
   - Be clearly documented as admin-only

3. ✅ Test functions should:
   - Be restricted to test users only
   - Or be removed from production entirely

---

## Next Steps

1. ✅ Create migration to fix `rpc_preview_max_charge` (add auth awareness)
   - Migration: `20251231001942_add_auth_check_to_rpc_preview_max_charge.sql`
   - Note: Function still allows anonymous users (intentional for preview before sign-up)
   - Added `auth.uid()` for audit/logging purposes

2. ✅ Create migration to fix `rpc_setup_test_data` (restrict to test users)
   - Migration: `20251231001943_restrict_rpc_setup_test_data_to_test_users.sql`
   - Added authentication check
   - Added test user restriction (is_test_user = true)

3. ⏳ Test fixes to ensure they work correctly
   - Run migrations on staging environment
   - Test `rpc_preview_max_charge` with authenticated and anonymous users
   - Test `rpc_setup_test_data` with test user and regular user (should fail)

4. ✅ Document security model for each function (this document)

