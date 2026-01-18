# Fix rpc_create_commitment Function Signature

**Date**: 2026-01-15  
**Issue**: Edge Function can't find `rpc_create_commitment` with the expected parameters

---

## Problem

The error shows:
```
Could not find the function public.rpc_create_commitment(p_app_count, p_apps_to_limit, p_deadline_date, p_deadline_timestamp, p_limit_minutes, p_penalty_per_minute_cents, p_saved_payment_method_id) in the schema cache
```

This indicates the database function signature doesn't match what the Edge Function is calling.

---

## Solution: Apply RPC Function Update

### Option 1: Manual Application (Recommended)

1. **Go to Supabase Dashboard**:
   - Navigate to: SQL Editor
   - Project: Your project

2. **Copy the SQL**:
   - Open: `supabase/remote_rpcs/rpc_create_commitment.sql`
   - Copy the entire contents

3. **Paste and Execute**:
   - Paste the SQL into the SQL Editor
   - Click "Run" to execute

4. **Verify**:
   - The function should be updated
   - Check for any errors in the output

### Option 2: Use Migration (If Available)

The migration file is at:
- `supabase/migrations/20260115230000_update_rpc_create_commitment_signature.sql`

You can try to apply it manually via Supabase Dashboard → SQL Editor.

---

## Expected Function Signature

After applying, the function should have this signature:

```sql
rpc_create_commitment(
  p_deadline_date date,
  p_limit_minutes integer,
  p_penalty_per_minute_cents integer,
  p_app_count integer,
  p_apps_to_limit jsonb,
  p_saved_payment_method_id text DEFAULT NULL,
  p_deadline_timestamp timestamptz DEFAULT NULL
)
```

---

## Verification

After applying, test the Edge Function call again. The error should be resolved and the commitment should be created successfully.



