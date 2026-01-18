# pg_net Extension Analysis - Reconciliation Queue Issue

**Date**: 2026-01-18  
**Issue**: `quick-handler` not being called despite cron jobs running successfully  
**Suspected Cause**: pg_net extension setup/signature issue (similar to Monday 12th issue)

---

## Key Findings

### 1. Extension Creation Difference

**Settlement (WORKING)**:
```sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
```

**Reconciliation Queue (NOT WORKING)**:
- No explicit extension creation
- Only sets `search_path` to include `net` schema

### 2. Function Signature Comparison

**Settlement (WORKING)** - Uses named parameters:
```sql
SELECT net.http_post(
  url := function_url,
  headers := jsonb_build_object(...),
  body := '{}'::jsonb
) INTO request_id;
```

**Reconciliation Queue (NOT WORKING)** - Also uses named parameters:
```sql
SELECT net.http_post(
  url := function_url,
  headers := request_headers,
  body := request_body
) INTO request_id;
```

**Old Examples (call_weekly_close)** - Uses positional parameters:
```sql
SELECT net.http_post(
  'https://...',                    -- url (positional)
  jsonb_build_object(...),          -- headers (positional)
  '{}'::jsonb,                      -- body (positional)
  30000                             -- timeout (positional)
) INTO request_id;
```

### 3. Schema Setup

**Settlement**:
- Explicitly creates extension in `public` schema
- Sets `search_path` to `'public, net, extensions'`
- Uses `net.http_post` (assumes it's in `net` schema or search_path finds it)

**Reconciliation**:
- No explicit extension creation
- Sets `search_path` to `'public, net, extensions'`
- Uses `net.http_post` (assumes it's in `net` schema or search_path finds it)

---

## Potential Issues

### Issue 1: Extension Not in Public Schema

If `pg_net` extension is installed in a different schema (e.g., `extensions` or `net`), and the cron job context doesn't have proper search_path, `net.http_post` might not be found.

**Solution**: Ensure extension is in `public` schema:
```sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
```

### Issue 2: Function Signature Mismatch

The named parameter syntax (`url :=`, `headers :=`, `body :=`) might not work if the function expects positional parameters.

**Solution**: Try positional parameters (matching old working examples):
```sql
SELECT net.http_post(
  function_url,           -- positional
  request_headers,       -- positional
  request_body           -- positional
  -- No timeout parameter (optional)
) INTO request_id;
```

### Issue 3: Schema Resolution in Cron Context

Cron jobs might have a different `search_path` than regular SQL execution, so `net.http_post` might not resolve correctly.

**Solution**: Use fully qualified name:
```sql
SELECT public.net.http_post(...)  -- If extension is in public schema
-- OR
SELECT net.http_post(...)         -- If extension is in net schema and search_path includes it
```

---

## Recommended Fixes (In Order)

### Fix 1: Ensure Extension is in Public Schema

Add to the reconciliation queue function or create a migration:
```sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
```

### Fix 2: Try Positional Parameters

Change from named to positional parameters (matching old working examples):
```sql
SELECT net.http_post(
  function_url,
  request_headers,
  request_body
) INTO request_id;
```

### Fix 3: Use Fully Qualified Function Name

If extension is in `public` schema:
```sql
SELECT public.net.http_post(...)
```

If extension is in `net` schema:
```sql
SELECT net.http_post(...)  -- Should work if search_path includes 'net'
```

---

## Diagnostic Queries

Run these to diagnose:

1. **Check extension location**:
   ```sql
   SELECT extname, extnamespace::regnamespace, extversion
   FROM pg_extension WHERE extname = 'pg_net';
   ```

2. **Check function exists**:
   ```sql
   SELECT n.nspname, p.proname, pg_get_function_arguments(p.oid)
   FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE p.proname = 'http_post';
   ```

3. **Check search_path in function**:
   ```sql
   -- The function already sets: PERFORM set_config('search_path', 'public, net, extensions', true);
   ```

---

## Next Steps

1. **Run diagnostic queries** to see where extension is installed
2. **Try Fix 1**: Add explicit extension creation in public schema
3. **If still fails, try Fix 2**: Use positional parameters instead of named
4. **If still fails, try Fix 3**: Use fully qualified function name

The settlement function works, so we should match its exact pattern as closely as possible.

