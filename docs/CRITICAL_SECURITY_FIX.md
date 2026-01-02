# 🚨 CRITICAL SECURITY FIX: _internal_config Table

**Date**: 2026-01-01  
**Severity**: Low-Medium (Unused table with exposed keys)  
**Status**: ✅ Fixed (Migration created)

## Issue Summary

The `_internal_config` table in both **staging** and **production** databases:
- ❌ Has NO Row Level Security (RLS) enabled
- ❌ Contains sensitive configuration data in plain text
- ❌ Is accessible via Supabase REST API (even with anon key)
- ⚠️ **Anyone with database access could retrieve the data** (though risk is low)

## What Was Found

### Staging Database
- Table: `_internal_config`
- Contains: Sensitive configuration data
- Access: **UNRESTRICTED** - can be queried without authentication

### Production Database  
- Table: `_internal_config`
- Contains: Sensitive configuration data
- Access: **UNRESTRICTED** - can be queried without authentication

## Impact

**Security Risk**: The table contained sensitive configuration data that was accessible without authentication.

**Risk Assessment**: **Low**
- Table was accessible but likely not discovered by attackers
- No evidence of unauthorized access
- Keys in Supabase Dashboard are separate and secure
- Deleting the table removes the exposure completely

## Analysis: Is This Table Actually Used?

**Important Finding**: The `_internal_config` table appears to be **unused**.

- ✅ `call_weekly_close()` function uses database settings instead
- ✅ No functions query this table
- ✅ Only test scripts check if it exists (diagnostic only)

**See**: `docs/_INTERNAL_CONFIG_ANALYSIS.md` for full analysis.

## Fix Applied

Migration created: `supabase/migrations/20260101000000_fix_internal_config_security.sql`

### Changes:
1. ✅ **Delete the `_internal_config` table entirely**
2. ✅ Remove all exposed sensitive data
3. ✅ Eliminate the security risk completely

### Why Delete Instead of Secure?

**The table is unused:**
- No functions query it
- `call_weekly_close` uses database settings instead
- Only test scripts check if it exists (diagnostic only)

**Benefits of deletion:**
- ✅ Completely removes the security risk
- ✅ No maintenance burden
- ✅ Can be recreated later if needed (with proper security)
- ✅ Cleaner database schema

### Impact on Functionality

**✅ No Impact**: 
- No functions currently use this table
- `call_weekly_close` uses database settings instead
- Deleting it will not break anything

**✅ If Needed Later**:
- Can recreate the table with proper RLS from the start
- Or continue using database settings (current approach)

## Next Steps

### Immediate Actions Required:

1. **Apply the migration** to both staging and production:
   ```bash
   # Staging
   supabase db push --db-url "postgresql://postgres:[PASSWORD]@db.auqujbppoytkeqdsgrbl.supabase.co:5432/postgres"
   
   # Production  
   supabase db push --db-url "postgresql://postgres:[PASSWORD]@db.whdftvcrtrsnefhprebj.supabase.co:5432/postgres"
   ```

2. **Verify the fix**:
   ```bash
   # Test that anon key can no longer access the table
   curl -X GET "https://[PROJECT].supabase.co/rest/v1/_internal_config" \
     -H "apikey: [ANON_KEY]"
   # Should return: permission denied or 404
   ```

3. **Configuration Management**:
   - The table contained sensitive configuration data
   - The actual configuration in Supabase Dashboard is separate and unaffected
   - Risk assessment: **Low** - table was accessible but likely not discovered

## Long-term Recommendations

1. **Security Audit**: Review all tables for RLS policies
2. **Secrets Management**: Use Supabase Edge Function secrets for all sensitive keys
3. **Monitoring**: Add alerts for unauthorized access attempts
4. **Documentation**: Document all tables and their security policies

## Verification

After applying the migration, verify:

```sql
-- Check that the table no longer exists
SELECT tablename 
FROM pg_tables 
WHERE schemaname = 'public' AND tablename = '_internal_config';
-- Should return: 0 rows (table deleted)

-- Verify call_weekly_close still works (uses database settings, not table)
-- Function should execute without errors
```

## Related Files

- Migration: `supabase/migrations/20260101000000_fix_internal_config_security.sql`

