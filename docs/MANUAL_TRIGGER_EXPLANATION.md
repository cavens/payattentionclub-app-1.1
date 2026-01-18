# Manual Trigger Explanation
**Date**: 2026-01-17  
**Purpose**: Explain what "manual trigger" means and how it relates to cron jobs

---

## What is "Manual Trigger"?

### The Term is Misleading

"Manual trigger" doesn't mean "manually executed by a human". It means **"includes the `x-manual-trigger: true` HTTP header"**.

### How It Works

**Code in `bright-service/index.ts` (lines 504-514)**:
```typescript
if (TESTING_MODE) {
  const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
  if (!isManualTrigger) {
    // Skip - return early
    return new Response(JSON.stringify({ 
      message: "Settlement skipped - testing mode active. Use x-manual-trigger: true header to run." 
    }), { status: 200 });
  }
  // Proceed with settlement
}
```

**Logic**:
1. Check if `TESTING_MODE` is enabled
2. Check if request has `x-manual-trigger: true` header
3. If header is **missing** → Skip (return early)
4. If header is **present** → Proceed with settlement

---

## Can Cron Jobs Include This Header?

### ✅ **YES - Cron Jobs CAN Include Custom Headers**

**Example: Reconciliation Queue Cron** (`process_reconciliation_queue.sql` lines 85-94):

```sql
SELECT net.http_post(
  function_url,                                    -- url
  jsonb_build_object('userId', queue_entry.user_id::text), -- body
  '{}'::jsonb,                                          -- params
  jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || svc_key,
    'x-manual-trigger', 'true'  -- ✅ Custom header CAN be included
  ),                                                     -- headers
  30000                                                  -- timeout
) INTO request_id;
```

**Key Point**: `pg_net.http_post()` supports custom headers in the 4th parameter (headers).

---

## What "Manual Trigger" Really Means

### Current Implementation

| Caller | Has Header? | Result in Testing Mode |
|--------|-------------|------------------------|
| **Cron job (without header)** | ❌ No | **Skipped** (returns early) |
| **Cron job (with header)** | ✅ Yes | **Proceeds** (runs settlement) |
| **HTTP request (with header)** | ✅ Yes | **Proceeds** (runs settlement) |
| **HTTP request (without header)** | ❌ No | **Skipped** (returns early) |

### The Real Purpose

The `x-manual-trigger` header is a **flag** to distinguish:
- **Intentional calls** (with header) - Should run settlement
- **Accidental/unintended calls** (without header) - Should skip

**In testing mode**, the function wants to:
- ✅ Allow **intentional** calls (from cron jobs, scripts, dashboard)
- ❌ Block **unintentional** calls (from old cron jobs, random requests)

---

## If We Add a Cron Job for Settlement

### Scenario: Cron Job Every 1-2 Minutes

**Question**: Would this trigger the "manual trigger"?

**Answer**: ✅ **YES, if the cron job includes the header**

### How to Set It Up

**Create a PostgreSQL function** (similar to `process_reconciliation_queue`):

```sql
CREATE OR REPLACE FUNCTION public.call_settlement()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  svc_key text;
  supabase_url text;
  function_url text;
  request_id bigint;
BEGIN
  -- Get settings from app_config
  SELECT value INTO svc_key FROM public.app_config WHERE key = 'service_role_key';
  SELECT value INTO supabase_url FROM public.app_config WHERE key = 'supabase_url';
  
  IF svc_key IS NULL OR supabase_url IS NULL THEN
    RAISE WARNING 'Cannot call settlement: app_config not configured';
    RETURN;
  END IF;
  
  function_url := supabase_url || '/functions/v1/bright-service';
  
  -- Call settlement with x-manual-trigger header
  SELECT net.http_post(
    function_url,                    -- url
    '{}'::jsonb,                      -- body
    '{}'::jsonb,                      -- params
    jsonb_build_object(
      'Content-Type', 'application/json',
      'x-manual-trigger', 'true'      -- ✅ Include the header
    ),                                 -- headers
    30000                              -- timeout
  ) INTO request_id;
  
  RAISE NOTICE 'Settlement triggered. Request ID: %', request_id;
END;
$$;
```

**Then create cron job**:
```sql
SELECT cron.schedule(
  'run-settlement-testing',
  '*/2 * * * *',  -- Every 2 minutes
  $$SELECT public.call_settlement()$$
);
```

**Result**: ✅ Cron job will include the header → Settlement will run

---

## Why This Design?

### The Problem It Solves

**Without the header check**:
- Old cron jobs (Monday 12:00 ET) would still run in testing mode
- They would try to settle commitments on wrong timeline
- Could cause incorrect charges

**With the header check**:
- Old cron jobs (without header) → Skipped ✅
- New cron jobs (with header) → Run ✅
- Manual scripts (with header) → Run ✅
- Random requests (without header) → Skipped ✅

### The "Manual" Part

The term "manual" is misleading because:
- ❌ It doesn't mean "human must click a button"
- ✅ It means "intentional call with proper header"
- ✅ Cron jobs CAN be "manual triggers" if they include the header

**Better term**: "Intentional trigger" or "Authorized trigger"

---

## Summary

### What "Manual Trigger" Means

1. **Not about human vs automated**
   - Cron jobs CAN be "manual triggers"
   - Scripts CAN be "manual triggers"
   - HTTP requests CAN be "manual triggers"

2. **About the HTTP header**
   - `x-manual-trigger: true` = "I'm authorized to run settlement"
   - Missing header = "Skip this call"

3. **Purpose**
   - Distinguish intentional calls from accidental ones
   - Prevent old cron jobs from running in testing mode
   - Allow new cron jobs to run if they include the header

### If We Add a Cron Job

**✅ YES, it will work** if:
- The cron job calls a PostgreSQL function
- That function uses `pg_net.http_post()`
- The HTTP call includes `x-manual-trigger: true` in headers

**Example**: The reconciliation queue cron already does this (lines 89-92 in `process_reconciliation_queue.sql`).

---

## Conclusion

**"Manual trigger" = "includes `x-manual-trigger: true` header"**

**Cron jobs CAN include this header** → They will work as "manual triggers"

**The term is misleading** → It's really about "authorized trigger" or "intentional trigger"


