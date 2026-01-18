# pg_net.http_post Signature Fix

**Issue Found**: Function is in `net` schema, but `search_path` doesn't include `net` in cron context

## Function Signature

The actual `net.http_post` function signature is:
```sql
http_post(
  url text,
  body jsonb DEFAULT '{}'::jsonb,
  params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds integer DEFAULT 5000
)
```

**Key Points**:
1. Function is in `net` schema (not `public`)
2. Parameters are **positional** (not named)
3. Order: `url`, `body`, `params`, `headers`, `timeout_milliseconds`
4. We're using **named parameters** which should work, but...

## The Problem

1. **Schema Resolution**: Function is in `net` schema
2. **Search Path**: Cron context has `search_path = "$user", public, extensions` (missing `net`)
3. **set_config**: We try to set `search_path` with `PERFORM set_config('search_path', 'public, net, extensions', true);`
   - But this might not work in cron context, or might not persist

## Solutions

### Solution 1: Create Extension in Public Schema (RECOMMENDED)

Match the settlement pattern exactly:
```sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
```

This ensures the function is in `public` schema, which is always in search_path.

### Solution 2: Use Fully Qualified Name

If extension must stay in `net` schema:
```sql
SELECT net.http_post(...)  -- Fully qualified
```

But this still requires `net` to be accessible, which might not work in cron.

### Solution 3: Use Positional Parameters (Match Old Examples)

The old `call_weekly_close` examples use positional parameters:
```sql
SELECT net.http_post(
  function_url,           -- positional 1: url
  request_body,           -- positional 2: body
  '{}'::jsonb,            -- positional 3: params
  request_headers,        -- positional 4: headers
  30000                   -- positional 5: timeout
) INTO request_id;
```

But we're using named parameters which should work too.

## Recommended Fix

**Add extension creation to match settlement**:
```sql
-- At the start of process_reconciliation_queue function or in a migration
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
```

This ensures:
1. Extension is in `public` schema (always in search_path)
2. Function is accessible as `net.http_post` or `public.net.http_post`
3. Matches the working settlement pattern exactly

