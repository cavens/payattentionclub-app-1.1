# Phase 6: Cron Jobs Setup - Status

## ✅ Completed

### Staging Environment
- **Status:** ✅ **COMPLETE**
- **Cron Job ID:** 1
- **Job Name:** `weekly-close-staging`
- **Schedule:** Every Monday at 17:00 UTC (12:00 PM EST)
- **Status:** Active
- **Function:** Calls `call_weekly_close()` which triggers the `weekly-close` Edge Function

**Verification:**
```sql
SELECT jobid, jobname, schedule, active 
FROM cron.job 
WHERE jobname = 'weekly-close-staging';
```

### Production Environment
- **Status:** ⚠️ **NEEDS MANUAL SETUP**
- **Issue:** psql connection authentication failed
- **Solution:** Set up via Supabase Dashboard

## 🔧 Production Setup (Manual)

### Step 1: Enable pg_cron Extension
1. Go to [Production Dashboard](https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj)
2. Navigate to **Database → Extensions**
3. Enable `pg_cron` if not already enabled

### Step 2: Schedule Cron Job
1. Go to **SQL Editor**
2. Copy-paste and run SQL from: `supabase/sql-drafts/setup_cron_production.sql`

```sql
-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Remove existing job if it exists
SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-production';

-- Schedule new cron job
SELECT cron.schedule(
    'weekly-close-production',
    '0 17 * * 1',  -- Every Monday at 17:00 UTC
    $$SELECT public.call_weekly_close();$$
);

-- Verify
SELECT jobid, jobname, schedule, active 
FROM cron.job 
WHERE jobname = 'weekly-close-production';
```

### Step 3: Verify
```sql
SELECT * FROM cron.job WHERE jobname = 'weekly-close-production';
```

## ⚠️ IMPORTANT: Service Role Key Setup

**Both environments require `app.settings.service_role_key` to be set!**

The `call_weekly_close()` function needs this to authenticate with the Edge Function.

### How to Set:

1. Go to **Database → Settings → Database Settings**
2. Scroll to **Custom Postgres Config**
3. Click **Add new config**
4. Set:
   - **Key:** `app.settings.service_role_key`
   - **Value:** Your service role key from `.env`

**Staging:**
- Key: `app.settings.service_role_key`
- Value: `STAGING_SUPABASE_SERVICE_ROLE_KEY` from `.env`
- Value: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF1cXVqYnBwb3l0a2VxZHNncmJsIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTQ1Nzg5NiwiZXhwIjoyMDgxMDMzODk2fQ.ZswLxpQlRnOUITjuK1WXdz-bL4A1pRGR0OxqX_A4TBI`

**Production:**
- Key: `app.settings.service_role_key`
- Value: `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY` from `.env`
- Value: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZGZ0dmNydHJzbmVmaHByZWJqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MzA0NzQ2NSwiZXhwIjoyMDc4NjIzNDY1fQ.l-qljQAkfgioPGv5gATTosBtA70oA_c_DZWXFuZaI44`

### Verify Service Role Key is Set:

```sql
-- Check if service_role_key is set
SELECT 
    CASE 
        WHEN current_setting('app.settings.service_role_key', true) IS NOT NULL 
        THEN '✅ Set'
        ELSE '❌ Not set'
    END AS status;
```

## 🧪 Testing

### Test Function Manually

**Staging:**
```sql
SELECT public.call_weekly_close();
```

**Production:**
```sql
SELECT public.call_weekly_close();
```

Then check Edge Function logs:
- **Staging:** [Functions → weekly-close → Logs](https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions/weekly-close/logs)
- **Production:** [Functions → weekly-close → Logs](https://supabase.com/dashboard/project/whdftvcrtrsnefhprebj/functions/weekly-close/logs)

## 📅 Schedule Details

- **Cron Expression:** `0 17 * * 1`
- **Meaning:** Every Monday at 17:00 UTC
- **EST Equivalent:** 12:00 PM EST (1:00 PM EDT during daylight saving)
- **Frequency:** Weekly

## ✅ Verification Checklist

### Staging
- [x] pg_cron extension enabled
- [x] Cron job scheduled (`weekly-close-staging`)
- [ ] Service role key set in database settings
- [ ] Manual test successful

### Production
- [ ] pg_cron extension enabled
- [ ] Cron job scheduled (`weekly-close-production`)
- [ ] Service role key set in database settings
- [ ] Manual test successful

## 🎯 Next Steps

1. **Set service_role_key in both environments** (Database Settings)
2. **Set up production cron job** (via Dashboard SQL Editor)
3. **Test manually** in both environments
4. **Monitor first scheduled run** (next Monday at 17:00 UTC)

## 📝 Notes

- The production psql connection failed due to authentication issues
- Staging setup was successful via CLI
- Both environments can be managed via Supabase Dashboard if CLI fails
- The cron job will automatically run every Monday

