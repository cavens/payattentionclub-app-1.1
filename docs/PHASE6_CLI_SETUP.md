# Phase 6: Cron Jobs Setup via CLI/psql

## Overview

This guide shows how to set up cron jobs using command-line tools (Supabase CLI + psql) instead of the Supabase Dashboard.

## Prerequisites

1. **Supabase CLI** (already installed)
2. **PostgreSQL client (psql)** - Install if needed:
   ```bash
   brew install postgresql@15
   # or
   brew install postgresql
   ```

3. **Database URLs** in `.env` file:
   - `STAGING_DB_URL`
   - `PRODUCTION_DB_URL`

## Method 1: Automated Script (Recommended)

### Quick Setup

```bash
# Setup for staging
./scripts/setup_cron_via_cli.sh staging

# Setup for production
./scripts/setup_cron_via_cli.sh production

# Setup for both
./scripts/setup_cron_via_cli.sh both
```

The script will:
1. Link to the Supabase project
2. Connect via psql using the database URL from `.env`
3. Execute the SQL to set up the cron job

### What the Script Does

1. **Links to Supabase project** (if not already linked)
2. **Connects to database** using `STAGING_DB_URL` or `PRODUCTION_DB_URL`
3. **Executes SQL** from `supabase/sql-drafts/setup_cron_*.sql`
4. **Sets up cron job** to run every Monday at 17:00 UTC

## Method 2: Manual psql Connection

### Step 1: Connect to Database

**Staging:**
```bash
# Get connection details from .env
source .env

# Connect (password will be prompted)
psql "$STAGING_DB_URL"
```

**Production:**
```bash
source .env
psql "$PRODUCTION_DB_URL"
```

### Step 2: Execute SQL

Once connected, run the SQL from the setup files:

**Staging:**
```sql
-- Copy-paste from supabase/sql-drafts/setup_cron_staging.sql
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-staging';

SELECT cron.schedule(
    'weekly-close-staging',
    '0 17 * * 1',
    $$SELECT public.call_weekly_close();$$
);
```

**Production:**
```sql
-- Copy-paste from supabase/sql-drafts/setup_cron_production.sql
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

SELECT cron.unschedule(jobid) 
FROM cron.job 
WHERE jobname = 'weekly-close-production';

SELECT cron.schedule(
    'weekly-close-production',
    '0 17 * * 1',
    $$SELECT public.call_weekly_close();$$
);
```

### Step 3: Set Service Role Key

**Important:** The `call_weekly_close()` function requires `app.settings.service_role_key` to be set.

This **cannot** be done via psql (requires superuser privileges). You must set it in Supabase Dashboard:

1. Go to **Database → Settings → Database Settings**
2. Scroll to **Custom Postgres Config**
3. Add:
   - **Key:** `app.settings.service_role_key`
   - **Value:** Your service role key from `.env`
     - Staging: `STAGING_SUPABASE_SERVICE_ROLE_KEY`
     - Production: `PRODUCTION_SUPABASE_SERVICE_ROLE_KEY`

## Method 3: Using Supabase CLI + SQL File

### Step 1: Link to Project

```bash
# Staging
supabase link --project-ref auqujbppoytkeqdsgrbl

# Production
supabase link --project-ref whdftvcrtrsnefhprebj
```

### Step 2: Execute SQL via psql

```bash
# Staging
source .env
psql "$STAGING_DB_URL" -f supabase/sql-drafts/setup_cron_staging.sql

# Production
psql "$PRODUCTION_DB_URL" -f supabase/sql-drafts/setup_cron_production.sql
```

## Verification

### Check Cron Job via psql

```bash
# Connect to database
psql "$STAGING_DB_URL"

# Run verification query
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active
FROM cron.job
WHERE jobname LIKE 'weekly-close%';
```

### Test Function Manually

```sql
-- Test the function
SELECT public.call_weekly_close();
```

Then check Edge Function logs in Supabase Dashboard.

## Troubleshooting

### psql Not Found

**Install PostgreSQL:**
```bash
brew install postgresql@15
```

**Add to PATH:**
```bash
# Add to ~/.zshrc or ~/.bash_profile
export PATH="/opt/homebrew/bin:$PATH"
# or
export PATH="/usr/local/bin:$PATH"
```

### Connection Failed

**Check database URL format:**
- Should be: `postgresql://postgres:PASSWORD@HOST:PORT/database`
- Password may be URL-encoded (e.g., `%23` for `#`)

**Test connection:**
```bash
psql "$STAGING_DB_URL" -c "SELECT version();"
```

### Permission Denied

Some operations (like setting `app.settings.service_role_key`) require superuser privileges and must be done in Supabase Dashboard, not via psql.

### Extension Not Found

If `pg_cron` extension is not available:
1. Go to Supabase Dashboard → Database → Extensions
2. Enable `pg_cron` extension
3. Then retry the setup script

## Quick Reference

| Task | Command |
|------|---------|
| Setup staging | `./scripts/setup_cron_via_cli.sh staging` |
| Setup production | `./scripts/setup_cron_via_cli.sh production` |
| Verify staging | `psql "$STAGING_DB_URL" -c "SELECT * FROM cron.job WHERE jobname = 'weekly-close-staging';"` |
| Test function | `psql "$STAGING_DB_URL" -c "SELECT public.call_weekly_close();"` |

## Next Steps

After setup:
1. ✅ Verify cron job is scheduled
2. ✅ Set service_role_key in Dashboard (if not done)
3. ✅ Test function manually
4. ✅ Monitor first scheduled run (next Monday at 17:00 UTC)


