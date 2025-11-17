# How to Download Supabase Functions & RPC Functions Locally

## Step 1: Link to Your Supabase Project

First, make sure you're linked to your Supabase project:

```bash
cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
supabase link --project-ref YOUR_PROJECT_REF
```

**To find your project ref:**
- Go to Supabase Dashboard → Project Settings → General
- Look for "Reference ID" (it's a short string like `abcdefghijklmnop`)

**Or if you're already linked, check status:**
```bash
supabase status
```

---

## Step 2: Pull Edge Functions from Supabase

This will download all Edge Functions from your Supabase project:

```bash
supabase functions pull
```

This will create/update files in:
```
supabase/functions/
├── billing-status/
│   └── index.ts
├── weekly-close/
│   └── index.ts
├── stripe-webhook/
│   └── index.ts
└── ... (other functions)
```

---

## Step 3: Get RPC Functions from Database

RPC functions are stored in the database, not as files. To get them:

### Option A: Use Supabase Dashboard (Easiest)

1. Go to Supabase Dashboard → SQL Editor
2. Run this query to see all RPC functions:

```sql
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
ORDER BY routine_name;
```

3. For each function, copy the definition and save it locally

### Option B: Use Supabase CLI to dump schema

```bash
# This will dump the entire schema including functions
supabase db dump --schema public -f supabase/migrations/$(date +%Y%m%d%H%M%S)_rpc_functions.sql
```

Then extract the function definitions from the migration file.

### Option C: Query specific functions

Run these queries in SQL Editor and save the results:

```sql
-- Get rpc_report_usage
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'rpc_report_usage';

-- Get rpc_create_commitment
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'rpc_create_commitment';

-- Get rpc_update_monitoring_status
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'rpc_update_monitoring_status';

-- Get rpc_get_week_status
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'rpc_get_week_status';
```

---

## Step 4: Organize Downloaded Files

After downloading, organize them like this:

```
supabase/
├── functions/
│   ├── billing-status/
│   │   └── index.ts
│   ├── weekly-close/
│   │   └── index.ts
│   ├── stripe-webhook/
│   │   └── index.ts
│   └── admin-close-week-now/
│       └── index.ts
├── migrations/
│   └── rpc_functions/
│       ├── rpc_report_usage.sql
│       ├── rpc_create_commitment.sql
│       ├── rpc_update_monitoring_status.sql
│       └── rpc_get_week_status.sql
└── config.toml
```

---

## Quick Commands Summary

```bash
# 1. Link to project (if not already linked)
supabase link --project-ref YOUR_PROJECT_REF

# 2. Pull all Edge Functions
supabase functions pull

# 3. Check what functions exist
supabase functions list

# 4. Dump database schema (includes RPC functions)
supabase db dump --schema public -f supabase/migrations/rpc_functions.sql
```

---

## After Downloading

Once you have the files, I can:
1. Compare local vs online versions
2. Check what's missing
3. Create the weekly close implementation plan (Step 1.3)
4. Help implement any missing pieces


