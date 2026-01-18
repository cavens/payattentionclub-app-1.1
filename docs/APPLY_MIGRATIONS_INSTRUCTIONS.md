# Instructions: Apply Reconciliation Queue Migrations

**Date**: 2026-01-15  
**Status**: Ready to Apply

---

## Summary

The reconciliation queue infrastructure has been restored. You need to apply:

1. ✅ **Table Migration** - Creates `reconciliation_queue` table
2. ✅ **Cron Setup Migration** - Sets up cron jobs
3. ✅ **RPC Function** - `process_reconciliation_queue` function
4. ✅ **RPC Function Update** - Updated `rpc_sync_daily_usage` function

---

## Application Methods

### Option 1: Via Supabase Dashboard (Recommended)

**Step 1: Apply Table Migration**

1. Go to: https://supabase.com/dashboard
2. Select your project (staging or production)
3. Go to: **SQL Editor** → **New Query**
4. Copy and paste the contents of:
   ```
   supabase/migrations/20260111220000_create_reconciliation_queue.sql
   ```
5. Click **Run**
6. Verify: `SELECT * FROM reconciliation_queue LIMIT 1;` (should return empty result, not error)

---

**Step 2: Apply RPC Function**

1. In the same SQL Editor (or new query)
2. Copy and paste the contents of:
   ```
   supabase/remote_rpcs/process_reconciliation_queue.sql
   ```
3. Click **Run**
4. Verify: `SELECT pg_get_functiondef('public.process_reconciliation_queue'::regproc);` (should return function definition)

---

**Step 3: Apply Cron Setup Migration**

1. In the same SQL Editor (or new query)
2. Copy and paste the contents of:
   ```
   supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql
   ```
3. Click **Run**
4. Verify: `SELECT * FROM cron.job WHERE jobname LIKE '%reconcile%';` (should return 2 jobs)

---

**Step 4: Apply Updated rpc_sync_daily_usage Function**

1. In the same SQL Editor (or new query)
2. Copy and paste the **entire contents** of:
   ```
   supabase/remote_rpcs/rpc_sync_daily_usage.sql
   ```
3. Click **Run**
4. Verify: Function should update without errors

---

### Option 2: Via Supabase CLI (if project is linked)

**Link Project First** (if not already linked):
```bash
cd /Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1
supabase link --project-ref YOUR_PROJECT_REF
```

**Apply Migrations**:
```bash
# This will apply all pending migrations
supabase db push
```

**Apply RPC Functions**:
The RPC functions in `remote_rpcs/` need to be applied manually via SQL Editor, as they're not tracked as migrations.

---

## Verification Queries

After applying all migrations, run these to verify:

### 1. Check Table Exists
```sql
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'reconciliation_queue'
);
```
**Expected**: `true`

### 2. Check Table Schema
```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'reconciliation_queue'
ORDER BY ordinal_position;
```
**Expected**: Should show all columns (id, user_id, week_start_date, etc.)

### 3. Check RPC Function Exists
```sql
SELECT pg_get_functiondef('public.process_reconciliation_queue'::regproc);
```
**Expected**: Should return the function definition

### 4. Check Cron Jobs
```sql
SELECT jobid, jobname, schedule, command, active
FROM cron.job 
WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal');
```
**Expected**: Should return 2 rows (one for testing, one for normal)

### 5. Check rpc_sync_daily_usage Has Queue Logic
```sql
SELECT routine_definition 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name = 'rpc_sync_daily_usage';
```
**Expected**: Should contain `reconciliation_queue` in the function body

---

## Quick Apply Script

You can also use the script I created:

```bash
cd /Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1
deno run --allow-read --allow-run --allow-env scripts/apply_reconciliation_queue_migrations.ts
```

This will:
- Attempt to apply via CLI if linked
- Otherwise, display the SQL for manual application

---

## Important Notes

### Migration Order

**Apply in this order**:
1. Table migration (creates table)
2. RPC function (creates function)
3. Cron setup (uses function)
4. Updated rpc_sync_daily_usage (uses table)

### Environment

**Apply to**:
- ✅ Staging first (test)
- ✅ Then production (after verification)

### Rollback

If something goes wrong:
1. **Remove cron jobs**:
   ```sql
   SELECT cron.unschedule(jobid) 
   FROM cron.job 
   WHERE jobname IN ('process-reconciliation-queue-testing', 'process-reconciliation-queue-normal');
   ```

2. **Drop table** (if needed):
   ```sql
   DROP TABLE IF EXISTS public.reconciliation_queue CASCADE;
   ```

3. **Drop function** (if needed):
   ```sql
   DROP FUNCTION IF EXISTS public.process_reconciliation_queue();
   ```

---

## Files to Apply

1. **`supabase/migrations/20260111220000_create_reconciliation_queue.sql`**
   - Creates table and indexes

2. **`supabase/remote_rpcs/process_reconciliation_queue.sql`**
   - Creates RPC function

3. **`supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql`**
   - Sets up cron jobs

4. **`supabase/remote_rpcs/rpc_sync_daily_usage.sql`**
   - Updated function with queue insertion logic

---

## After Application

Once all migrations are applied:

1. ✅ Test end-to-end flow:
   - Create commitment
   - Let it settle
   - Sync late usage
   - Check queue entry created
   - Wait for cron to process
   - Verify reconciliation completed

2. ✅ Monitor logs:
   - Check Supabase logs for queue processing
   - Check for any errors in cron job execution

3. ✅ Verify in both environments:
   - Staging
   - Production

---

## Summary

**Status**: ✅ All files ready  
**Next Step**: Apply migrations via Supabase Dashboard SQL Editor  
**Time Estimate**: 5-10 minutes per environment


