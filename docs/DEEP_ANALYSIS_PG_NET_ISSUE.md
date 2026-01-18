# Deep Analysis: pg_net Extension Issue

**Date**: 2026-01-18  
**Issue**: `quick-handler` not being called despite cron jobs running  
**User Note**: "This is the exact same path we were at last Monday and then at some point we cracked it"

---

## Critical Discovery: Function Signature Order

The actual `net.http_post` function signature is:
```sql
http_post(
  url text,                                    -- 1st parameter
  body jsonb DEFAULT '{}'::jsonb,             -- 2nd parameter
  params jsonb DEFAULT '{}'::jsonb,           -- 3rd parameter
  headers jsonb DEFAULT '{"Content-Type": "application/json"}'::jsonb,  -- 4th parameter
  timeout_milliseconds integer DEFAULT 5000   -- 5th parameter
)
```

**Parameter Order**: `url`, `body`, `params`, `headers`, `timeout`

---

## Current Code Comparison

### Settlement (WORKING) ✅
```sql
SELECT net.http_post(
  url := function_url,                    -- named: url (1st)
  headers := jsonb_build_object(...),     -- named: headers (4th)
  body := '{}'::jsonb                    -- named: body (2nd)
) INTO request_id;
```

**Uses named parameters** - order doesn't matter ✅

### Reconciliation (NOT WORKING) ❌
```sql
SELECT net.http_post(
  url := function_url,        -- named: url (1st)
  headers := request_headers, -- named: headers (4th)
  body := request_body        -- named: body (2nd)
) INTO request_id;
```

**Uses named parameters** - same pattern as settlement ❌

---

## Key Differences Between Working and Non-Working

### 1. Extension Location

**Settlement Migration**:
```sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
```

**Reconciliation**:
- No explicit extension creation
- Extension is currently in `extensions` schema (not `public`)

### 2. Schema Resolution

**Both functions set search_path**:
```sql
PERFORM set_config('search_path', 'public, net, extensions', true);
```

**But**:
- Settlement creates extension in `public` → `net` schema might be `public.net`
- Reconciliation has extension in `extensions` → `net` schema might be `extensions.net` or just `net`

### 3. Function Call Pattern

**Settlement**: Direct `jsonb_build_object` in headers
**Reconciliation**: Uses variables (`request_headers`, `request_body`)

---

## The Real Problem: Schema Resolution in Cron Context

When `pg_net` extension is in `extensions` schema:
- The `net` schema might be created as `extensions.net` or as a separate `net` schema
- Cron context has `search_path = "$user", public, extensions`
- `set_config` with `true` (local) might not persist in cron context
- `net.http_post` can't be found because `net` schema isn't in search_path

---

## Solutions (In Order of Likelihood)

### Solution 1: Move Extension to Public Schema (MOST LIKELY)

The settlement function works because extension is in `public`. We need to move it:

```sql
-- Drop and recreate in public schema
DROP EXTENSION IF EXISTS pg_net CASCADE;
CREATE EXTENSION pg_net WITH SCHEMA public;
```

**Why this works**:
- `public` is always in search_path
- `net` schema becomes `public.net` or accessible via search_path
- Matches working settlement pattern exactly

### Solution 2: Use Positional Parameters in Correct Order

If extension must stay in `extensions`, try positional parameters matching the exact signature order:

```sql
SELECT net.http_post(
  function_url,        -- 1: url
  request_body,        -- 2: body
  '{}'::jsonb,         -- 3: params (empty)
  request_headers,     -- 4: headers
  30000                -- 5: timeout (optional)
) INTO request_id;
```

**Why this might work**:
- Positional parameters don't rely on named parameter resolution
- Matches the exact function signature order
- Old examples use positional parameters

### Solution 3: Use Fully Qualified Schema Name

Try explicitly referencing the schema:

```sql
-- If extension is in public schema
SELECT public.net.http_post(...)

-- OR if net is a separate schema
SELECT net.http_post(...)  -- But this requires net in search_path
```

### Solution 4: Check if set_config is Actually Working

The `set_config('search_path', 'public, net, extensions', true)` with `true` means "local to this transaction". In cron context, this might not work as expected.

**Test**: Add logging to see if search_path is actually being set:
```sql
RAISE NOTICE 'Current search_path: %', current_setting('search_path');
PERFORM set_config('search_path', 'public, net, extensions', true);
RAISE NOTICE 'After set_config search_path: %', current_setting('search_path');
```

---

## What We Know

1. ✅ Cron jobs are running successfully
2. ✅ Function is being called (queue entry goes to `processing`)
3. ❌ `net.http_post` is not executing (no HTTP request)
4. ❌ `quick-handler` never receives the request
5. ✅ Settlement function works with same pattern (but extension in `public`)

---

## Most Likely Root Cause

**The extension needs to be in `public` schema for cron context to resolve `net.http_post` correctly.**

Even though both functions set `search_path`, the cron context might:
- Reset search_path before function execution
- Not respect `set_config` with `true` (local) flag
- Require extension in `public` schema for proper resolution

---

## Recommended Fix

**Move extension to public schema** (matches working settlement):

```sql
-- Step 1: Check dependencies (to be safe)
SELECT 
  dependent_ns.nspname,
  dependent_pro.proname
FROM pg_proc dependent_pro
JOIN pg_namespace dependent_ns ON dependent_pro.pronamespace = dependent_ns.oid
JOIN pg_depend ON dependent_pro.oid = pg_depend.objid
JOIN pg_proc source_pro ON pg_depend.refobjid = source_pro.oid
JOIN pg_namespace source_ns ON source_pro.pronamespace = source_ns.oid
WHERE source_ns.nspname = 'net' AND source_pro.proname = 'http_post';

-- Step 2: Drop and recreate in public
DROP EXTENSION IF EXISTS pg_net CASCADE;
CREATE EXTENSION pg_net WITH SCHEMA public;

-- Step 3: Verify
SELECT extname, extnamespace::regnamespace 
FROM pg_extension WHERE extname = 'pg_net';
-- Should show: public
```

This matches the exact pattern that works for settlement.

