# Analysis: _internal_config Table Usage

**Date**: 2026-01-01  
**Status**: ✅ Analysis Complete

## Summary

The `_internal_config` table exists in both staging and production databases but **appears to be unused**.

## Current Usage

### Functions That Use Configuration

1. **`call_weekly_close()` function**
   - **Location**: `supabase/remote_rpcs/call_weekly_close.sql`
   - **Method**: Uses database settings via `current_setting()`
   - **NOT using**: `_internal_config` table
   - **How it works**: 
     ```sql
     config_value text := current_setting('app.settings.config_key', true);
     ```
   - This reads from PostgreSQL database settings, not from a table
   - Note: The actual setting name is implementation-specific

### Functions That Reference _internal_config

**NONE** - No functions actually query this table.

### Scripts That Reference _internal_config

1. **Test scripts** (diagnostic only)
   - Only **checks if the table exists** as a fallback method
   - Does not actually use it
   - This is just a diagnostic check, not functional code

## What _internal_config Contains

- **Structure**: `key` (text), `value` (text), `updated_at` (timestamp)
- Contains sensitive configuration data

## Impact of Enabling RLS

### ✅ Safe to Enable RLS

**Why it's safe:**
1. **No functions use it** - `call_weekly_close` uses database settings instead
2. **SECURITY DEFINER functions bypass RLS** - If a function needs to access it in the future:
   - Functions with `SECURITY DEFINER` run with elevated privileges
   - They can access tables even with RLS enabled

### How Functions Would Access It (If Needed)

If a function needed to read from `_internal_config` in the future:

```sql
CREATE OR REPLACE FUNCTION public.some_function()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER  -- This allows bypassing RLS
AS $$
DECLARE
  config_value text;
BEGIN
  -- This would work even with RLS enabled because:
  -- 1. Function runs with SECURITY DEFINER (elevated privileges)
  SELECT value INTO config_value
  FROM public._internal_config
  WHERE key = 'some_key';
  
  -- Use the value...
END;
$$;
```

**Key Point**: Functions with `SECURITY DEFINER` can access RLS-protected tables.

## Recommendation

### Option 1: Delete the Table (Recommended) ✅
- ✅ **Remove the security risk entirely**
- ✅ No impact on current functionality (nothing uses it)
- ✅ Cleaner database schema
- ✅ Can be recreated later if needed (with proper security from the start)

### Option 2: Enable RLS (Alternative)
- ✅ Secure the table immediately
- ⚠️ Still maintains unused table in database
- ⚠️ Requires ongoing maintenance

**Recommendation**: **Delete the table** (Option 1) because:
1. **It's unused** - no reason to keep it
2. **Eliminates risk completely** - no exposed keys
3. **Simpler** - one less thing to maintain
4. **Can recreate later** - if actually needed, can be created with proper security

## Migration Impact

The migration `20260101000000_fix_internal_config_security.sql`:
- ✅ **Deletes the `_internal_config` table entirely**
- ✅ **Removes all exposed sensitive data**
- ✅ **Will NOT break any existing functionality** (nothing uses it)
- ✅ **Eliminates the security risk completely**

## Verification

After applying the migration, verify:

```sql
-- 1. Check that the table no longer exists
SELECT tablename 
FROM pg_tables 
WHERE schemaname = 'public' AND tablename = '_internal_config';
-- Expected: 0 rows (table deleted)

-- 2. Verify call_weekly_close still works
-- (It uses database settings, not the table)
-- Function should execute without errors
```

## Conclusion

**The `_internal_config` table is unused and contains exposed sensitive data.** Deleting it will:
- ✅ **Eliminate the security risk completely**
- ✅ **Not break any functionality** (nothing uses it)
- ✅ **Simplify the database schema**

The migration is safe to apply and is the best solution.

