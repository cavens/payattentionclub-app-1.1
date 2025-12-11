# Setting Service Role Key - Fixed Method

## Problem

The Supabase UI doesn't have an option to set `app.settings.service_role_key`, and SQL fails with:
```
ERROR: 42501: permission denied to set parameter "app.settings.service_role_key"
```

## Solution

Instead of using database configuration, we'll:
1. Store the service role key in a table (`_internal_config`)
2. Update the `call_weekly_close()` function to read from the table

## Step-by-Step Instructions

### For Staging Environment

1. **Go to Staging SQL Editor**
   - URL: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/sql/new

2. **Deploy the Fixed Function**
   - Copy and paste the entire contents of: `supabase/remote_rpcs/call_weekly_close_fixed.sql`
   - Click **"Run"**

3. **Set the Service Role Key**
   - Copy and paste the contents of: `supabase/sql-drafts/set_service_role_key_staging.sql`
   - Click **"Run"**

4. **Verify**
   ```sql
   SELECT key, LEFT(value, 20) || '...' as value_preview
   FROM public._internal_config
   WHERE key = 'service_role_key';
   ```

### For Production Environment

1. **Go to Production SQL Editor**
   - URL: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/sql/new

2. **Deploy the Fixed Function**
   - Copy and paste the entire contents of: `supabase/remote_rpcs/call_weekly_close_fixed.sql`
   - Click **"Run"**

3. **Set the Service Role Key**
   - Copy and paste the contents of: `supabase/sql-drafts/set_service_role_key_production.sql`
   - Click **"Run"**

4. **Verify**
   ```sql
   SELECT key, LEFT(value, 20) || '...' as value_preview
   FROM public._internal_config
   WHERE key = 'service_role_key';
   ```

## Test the Function

After setting up, test manually:

```sql
-- Test the function
SELECT public.call_weekly_close();
```

Then check Edge Function logs to verify it was called successfully.

## How It Works

1. **Table Storage**: The service role key is stored in `public._internal_config` table
2. **Function Update**: `call_weekly_close()` reads from the table instead of database config
3. **Auto-Detection**: The function automatically detects which environment (staging/production) based on the service role key

## Security Note

The `_internal_config` table is protected by:
- `SECURITY DEFINER` on the function (runs with elevated privileges)
- Only the function can read the key
- Regular users cannot access the table directly

## Troubleshooting

### Function Still Fails

If you get "service_role_key not set", verify:
```sql
SELECT * FROM public._internal_config WHERE key = 'service_role_key';
```

If empty, run the set script again.

### Wrong Project URL

The function auto-detects the project URL from the service role key. If it fails, check that:
- Staging key contains: `auqujbppoytkeqdsgrbl`
- Production key contains: `whdftvcrtrsnefhprebj`

## Files Reference

- **Fixed Function**: `supabase/remote_rpcs/call_weekly_close_fixed.sql`
- **Staging Setup**: `supabase/sql-drafts/set_service_role_key_staging.sql`
- **Production Setup**: `supabase/sql-drafts/set_service_role_key_production.sql`

