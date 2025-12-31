# Apply Critical Security Fixes

## ⚠️ CRITICAL: Two Security Vulnerabilities Found

Two RPC functions have security vulnerabilities that need to be fixed immediately:

1. **`rpc_preview_max_charge`** - Missing authentication check
2. **`rpc_setup_test_data`** - No authentication or test user restriction

## How to Apply Fixes

### Option 1: Via Supabase Dashboard (Recommended)

1. Go to your Supabase Dashboard: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl
2. Navigate to **SQL Editor**
3. Copy and paste the contents of `SECURITY_FIXES_APPLY_NOW.sql`
4. Click **Run**

### Option 2: Apply Individual Migrations

Since the automated migration push is blocked by an older migration error, you can apply the fixes manually:

#### Fix 1: rpc_preview_max_charge
- File: `supabase/migrations/20251231001942_add_auth_check_to_rpc_preview_max_charge.sql`
- Copy the entire file content and run in SQL Editor

#### Fix 2: rpc_setup_test_data  
- File: `supabase/migrations/20251231001943_restrict_rpc_setup_test_data_to_test_users.sql`
- Copy the entire file content and run in SQL Editor

## What These Fixes Do

### Fix 1: rpc_preview_max_charge
- ✅ Adds authentication check (`IF v_user_id IS NULL THEN RAISE EXCEPTION`)
- ✅ Revokes access from anonymous users
- ✅ Grants access only to authenticated users

### Fix 2: rpc_setup_test_data
- ✅ Adds authentication check
- ✅ Restricts access to test users only (`is_test_user = true`)
- ✅ Prevents regular users from creating test data

## Verification

After applying the fixes, verify they work:

```sql
-- Test 1: Verify rpc_preview_max_charge requires auth
-- This should fail if called without authentication
SELECT public.rpc_preview_max_charge('2025-12-31', 120, 10, '{}'::jsonb);
-- Expected: Error "Not authenticated"

-- Test 2: Verify rpc_setup_test_data is restricted
-- This should fail for non-test users
SELECT public.rpc_setup_test_data();
-- Expected: Error "Only test users can call this function"
```

## Status

- [ ] Fix 1 applied (rpc_preview_max_charge)
- [ ] Fix 2 applied (rpc_setup_test_data)
- [ ] Verified both fixes work correctly

## Next Steps

After applying these fixes:
1. Test the app to ensure `rpc_preview_max_charge` still works (it should, since the app is authenticated)
2. Verify test users can still call `rpc_setup_test_data`
3. Confirm regular users cannot call `rpc_setup_test_data`

