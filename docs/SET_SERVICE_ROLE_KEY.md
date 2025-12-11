# Setting Service Role Key in Supabase (Updated UI)

## Overview

The `call_weekly_close()` function needs `app.settings.service_role_key` to be set as a database configuration parameter. This allows the function to authenticate when calling the Edge Function.

## Step-by-Step Instructions (New Supabase UI)

### For Staging Environment

1. **Go to Staging Project Dashboard**
   - URL: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl

2. **Navigate to Database Settings**
   - In the left sidebar, click **"Project Settings"** (gear icon at the bottom)
   - OR go directly: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/settings/database

3. **Find Database Configuration**
   - Look for **"Database"** section in the settings
   - Scroll to find **"Connection Pooling"** or **"Database Settings"**
   - Look for **"Custom Postgres Config"** or **"Postgres Configuration"**

4. **Alternative Path (if above doesn't work)**
   - Go to **"Database"** in left sidebar
   - Click **"Settings"** tab (or look for a settings icon)
   - Find **"Database Configuration"** or **"Postgres Config"**

5. **Add Custom Configuration**
   - Look for **"Add configuration"** or **"Custom settings"** button
   - Click to add a new configuration parameter
   - **Key:** `app.settings.service_role_key`
   - **Value:** Get from `.env` file: `STAGING_SUPABASE_SERVICE_ROLE_KEY`
   - ⚠️ **DO NOT commit this value to git!**
   - Click **"Save"** or **"Apply"**

### For Production Environment

1. **Go to Production Project Dashboard**
   - URL: https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj

2. **Follow same steps as staging**
   - Navigate to **Project Settings → Database**
   - Find **"Custom Postgres Config"** or **"Database Configuration"**
   - Add configuration:
     - **Key:** `app.settings.service_role_key`
     - **Value:** Get from `.env` file: `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY`
     - ⚠️ **DO NOT commit this value to git!**

## Alternative: Set via SQL (If UI Not Available)

If you can't find the UI option, you can try setting it via SQL Editor:

1. Go to **SQL Editor** in Supabase Dashboard
2. Run this SQL (requires superuser privileges):

**Staging:**
```sql
ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_STAGING_SERVICE_ROLE_KEY_FROM_ENV';
```

**Production:**
```sql
ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_PRODUCTION_SERVICE_ROLE_KEY_FROM_ENV';
```

⚠️ **Replace with actual values from your `.env` file - DO NOT commit these values!**

**Note:** This may fail with "insufficient privileges" - in that case, you must use the Dashboard UI.

## Verify It's Set

After setting, verify in SQL Editor:

```sql
SELECT current_setting('app.settings.service_role_key', true);
```

This should return the service role key value. If it returns `NULL`, it's not set correctly.

## Troubleshooting

### Can't Find "Custom Postgres Config"

The UI location may vary. Try:
1. **Project Settings → Database → Advanced Settings**
2. **Database → Configuration → Custom Settings**
3. **Project Settings → Infrastructure → Database Config**

### SQL Method Fails

If `ALTER DATABASE` fails with "insufficient privileges", you must use the Dashboard UI. The SQL method requires superuser access which may not be available.

### Still Can't Find It

1. Check Supabase documentation: https://supabase.com/docs/guides/database/custom-postgres-config
2. Contact Supabase support if the option is not available
3. As a workaround, you might need to modify the `call_weekly_close()` function to use a different authentication method

## What This Does

Setting `app.settings.service_role_key` allows PostgreSQL functions to access this value via:
```sql
current_setting('app.settings.service_role_key', true)
```

The `call_weekly_close()` function uses this to authenticate HTTP requests to the Edge Function.

