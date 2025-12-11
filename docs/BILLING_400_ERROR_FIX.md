# Fix: Billing Status 400 Error

## Problem

When trying to pay, you get:
```
BILLING BackendClient: ❌ Failed to decode BillingStatusResponse: httpError(code: 400, data: 46 bytes)
LOCKIN AuthorizationView: ❌ Error during lock in: Edge Function returned a non-2xx status code: 400
```

## Root Cause

The `billing-status` Edge Function returns a 400 error when:
- User exists in `auth.users` (from Apple Sign-In)
- But user row is **missing** in `public.users` table

This happens because:
1. The `handle_new_user()` trigger might not have fired
2. The trigger might have failed silently
3. The user was created before the trigger was set up

## Solution

### Quick Fix: Create Missing User Row

1. **Go to Supabase SQL Editor**
   - Staging: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/sql/new
   - Production: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/sql/new

2. **Run the fix script:**
   ```sql
   -- Create missing user rows
   INSERT INTO public.users (id, email, created_at)
   SELECT 
       au.id,
       au.email,
       au.created_at
   FROM auth.users au
   LEFT JOIN public.users pu ON au.id = pu.id
   WHERE pu.id IS NULL
   ON CONFLICT (id) DO NOTHING;
   ```

   Or use the full script: `supabase/sql-drafts/fix_missing_user_row.sql`

3. **Verify the fix:**
   ```sql
   SELECT 
       'auth.users' as table_name,
       COUNT(*) as count
   FROM auth.users
   UNION ALL
   SELECT 
       'public.users' as table_name,
       COUNT(*) as count
   FROM public.users;
   ```

   Both counts should match.

### Verify Trigger Exists

Make sure the `handle_new_user()` trigger is set up:

```sql
-- Check if trigger exists
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';
```

If it doesn't exist, create it:

```sql
-- Create trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.users (id, email, created_at)
  VALUES (NEW.id, NEW.email, NOW())
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Create trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
```

## Prevention

The trigger should automatically create `public.users` rows for new users. If it's not working:

1. **Check trigger is enabled:**
   ```sql
   SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created';
   ```

2. **Check trigger function exists:**
   ```sql
   SELECT proname FROM pg_proc WHERE proname = 'handle_new_user';
   ```

3. **Test the trigger:**
   - Create a test user in `auth.users`
   - Verify a row is created in `public.users`

## Testing After Fix

1. **Try the payment flow again**
   - The billing-status call should now succeed
   - You should be able to add a payment method

2. **Check Edge Function logs:**
   - Go to Functions → billing-status → Logs
   - Look for any errors

## Common Issues

### Trigger Not Firing

- Check that the trigger is created on `auth.users` table
- Verify the function has `SECURITY DEFINER` (required for auth.users access)
- Check Supabase logs for trigger errors

### Permission Errors

- The trigger function needs `SECURITY DEFINER` to access `auth.users`
- Make sure the function has proper permissions

### Race Condition

- If user signs in very quickly, the trigger might not have fired yet
- The fix script handles this by creating missing rows

## Files Reference

- **Fix Script**: `supabase/sql-drafts/fix_missing_user_row.sql`
- **Trigger Function**: Should be in `supabase/remote_schema.sql` or `supabase/remote_schema_staging.sql`

