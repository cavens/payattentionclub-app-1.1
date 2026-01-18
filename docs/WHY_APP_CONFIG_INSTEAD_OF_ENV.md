# Why We Need `app_config` Table Instead of Just `.env` Files

**Date**: 2026-01-18  
**Purpose**: Explain the architectural reasons for using `app_config` database table

---

## The Core Problem: Runtime Separation

Your application runs in **two completely separate runtime environments**:

### 1. **Edge Functions (Deno Runtime)**
- **Location**: Supabase Edge Functions (serverless Deno runtime)
- **Can access**: 
  - ✅ Environment variables via `Deno.env.get()`
  - ✅ Database via Supabase client
- **Cannot access**:
  - ❌ PostgreSQL environment variables
  - ❌ Local `.env` files (only in development)

### 2. **Database Functions & Cron Jobs (PostgreSQL Runtime)**
- **Location**: PostgreSQL database server
- **Can access**:
  - ✅ Database tables (including `app_config`)
  - ✅ PostgreSQL settings
- **Cannot access**:
  - ❌ Edge Function environment variables
  - ❌ Deno runtime environment
  - ❌ Local `.env` files (not on database server)

**Key Insight**: These are **two separate processes** running on different servers. They cannot share environment variables directly.

---

## Why `.env` Files Don't Work

### Problem 1: `.env` Files Are Local Development Files

**What `.env` files are**:
- Text files on your local development machine
- Loaded by your local development tools (Deno, Node.js, etc.)
- **Not deployed** to production servers

**What happens in production**:
- Edge Functions run on Supabase's servers (not your machine)
- Database runs on Supabase's PostgreSQL server (not your machine)
- **Neither has access to your local `.env` file**

**Solution**: Environment variables must be set in:
- **Edge Functions**: Supabase Dashboard → Edge Functions → Settings → Secrets
- **Database**: Cannot access Edge Function secrets → Need `app_config` table

---

### Problem 2: Database Functions Cannot Access Edge Function Secrets

**Example: `process_reconciliation_queue()` cron job**

This function runs **inside PostgreSQL** and needs to know:
- Is testing mode enabled?
- What's the Supabase URL?
- What's the service role key?
- What's the reconciliation secret?

**If we only used `.env` or Edge Function secrets**:
```sql
-- ❌ This doesn't work - PostgreSQL can't access Deno environment variables
SELECT Deno.env.get('TESTING_MODE');  -- ERROR: Function doesn't exist
```

**With `app_config` table**:
```sql
-- ✅ This works - PostgreSQL can query database tables
SELECT value FROM app_config WHERE key = 'testing_mode';
```

---

### Problem 3: Cron Jobs Run in Database Runtime

**Cron jobs are scheduled PostgreSQL functions**:
- They run **inside the database server**
- They execute SQL code
- They have **no access** to Edge Function runtime

**Example: Reconciliation Queue Cron**

```sql
-- This cron job runs every 1 minute (testing) or 10 minutes (normal)
SELECT cron.schedule(
  'process-reconciliation-queue-testing',
  '* * * * *',  -- Every minute
  $$SELECT public.process_reconciliation_queue()$$
);
```

**Inside `process_reconciliation_queue()`**:
- Needs to check: "Am I in testing mode or normal mode?"
- **Cannot** check `Deno.env.get('TESTING_MODE')` (not available in PostgreSQL)
- **Can** check `SELECT value FROM app_config WHERE key = 'testing_mode'` ✅

---

## Real-World Example: Testing Mode

### Scenario: Enable Testing Mode

**If we only used `.env` files**:

1. **Edge Functions**:
   - ✅ Can read `TESTING_MODE=true` from Edge Function secrets
   - ✅ `bright-service` can use testing mode timing (3 min week, 1 min grace)

2. **Database Cron Jobs**:
   - ❌ Cannot read `TESTING_MODE` from Edge Function secrets
   - ❌ `process_reconciliation_queue()` doesn't know if it's testing mode
   - ❌ Runs on wrong schedule (10 min instead of 1 min)
   - **Result**: System breaks

**With `app_config` table**:

1. **Edge Functions**:
   - ✅ Can read `app_config.testing_mode` from database
   - ✅ `bright-service` can use testing mode timing

2. **Database Cron Jobs**:
   - ✅ Can read `app_config.testing_mode` from database
   - ✅ `process_reconciliation_queue()` knows it's testing mode
   - ✅ Runs on correct schedule (1 min)
   - **Result**: System works correctly

---

## Additional Benefits of `app_config`

### 1. **Runtime Configuration Changes**

**With `.env` files**:
- Change requires:
  1. Update `.env` file locally
  2. Update Edge Function secrets in Supabase Dashboard
  3. Redeploy Edge Functions (or wait for cold start)
  4. **Cannot update database functions** (they can't read env vars)

**With `app_config` table**:
- Change requires:
  1. Update `app_config` table (single SQL query)
  2. Both Edge Functions and database functions see change immediately
  3. No redeployment needed

**Example**:
```sql
-- Switch from testing to normal mode instantly
UPDATE app_config SET value = 'false' WHERE key = 'testing_mode';
-- ✅ Both cron jobs and Edge Functions see this change
```

---

### 2. **Centralized Configuration**

**All configuration in one place**:
- `testing_mode`
- `service_role_key`
- `supabase_url`
- `reconciliation_secret`
- `settlement_secret`

**Benefits**:
- ✅ Single source of truth
- ✅ Easy to query: `SELECT * FROM app_config`
- ✅ Easy to audit: See all config values at once
- ✅ Easy to backup: Part of database backup

---

### 3. **Environment-Aware Configuration**

**Different values for staging vs production**:
- Staging: `app_config` has staging URLs and keys
- Production: `app_config` has production URLs and keys
- Same code, different config per environment

**With `.env` files**:
- Need separate `.env.staging` and `.env.production` files
- Must remember to set correct secrets in each environment
- Easy to mix up

**With `app_config`**:
- Each database (staging/production) has its own `app_config` table
- Automatically uses correct values for that environment
- Less error-prone

---

## Current Architecture

### Configuration Storage

| Location | Used By | Access Method | Example |
|----------|---------|---------------|---------|
| **Edge Function Secrets** | Edge Functions | `Deno.env.get()` | `TESTING_MODE`, `STRIPE_SECRET_KEY` |
| **`app_config` table** | Database functions, Cron jobs, Edge Functions (as fallback) | SQL query | `testing_mode`, `service_role_key` |
| **`.env` file** | Local development only | Local tool loading | Not used in production |

### Why Both Exist

**Edge Function Secrets** (Supabase Dashboard):
- ✅ Fast access (no database query)
- ✅ Secure (encrypted at rest)
- ✅ Used by Edge Functions for performance

**`app_config` table**:
- ✅ Accessible by database functions
- ✅ Accessible by cron jobs
- ✅ Can be queried by Edge Functions (with database call)
- ✅ Single source of truth for database runtime

---

## Summary

### Why Not Just `.env` Files?

1. **`.env` files are local only** - Not accessible in production
2. **Database functions can't read `.env`** - They run in PostgreSQL, not your local machine
3. **Cron jobs can't read `.env`** - They run in database runtime
4. **Edge Function secrets aren't accessible to database** - Separate runtime environments

### Why `app_config` Table?

1. **Works in both runtimes** - Database functions and Edge Functions can both access it
2. **Runtime changes** - Update config without redeployment
3. **Centralized** - All config in one place
4. **Environment-aware** - Each database has its own config
5. **Queryable** - Easy to check current configuration

### The Hybrid Approach

**Current best practice**:
- **`app_config` table** = Primary source of truth (works everywhere)
- **Edge Function secrets** = Performance optimization (fast access, cached)
- **Edge Functions check database first**, fallback to env var

This gives us:
- ✅ Single source of truth (database)
- ✅ Fast access in Edge Functions (cached env var)
- ✅ Works for all runtimes
- ✅ No breaking changes

---

## Conclusion

**You cannot use only `.env` files** because:
- Database functions and cron jobs run in PostgreSQL runtime
- PostgreSQL cannot access Edge Function environment variables
- `.env` files are local development files, not available in production

**`app_config` table is necessary** because:
- It's the only way database functions can access configuration
- It's the only way cron jobs can check testing mode
- It provides a single source of truth accessible by all runtimes
- It allows runtime configuration changes without redeployment

**The architecture requires both**:
- Edge Function secrets for fast access in Edge Functions
- `app_config` table for database functions and as primary source of truth

