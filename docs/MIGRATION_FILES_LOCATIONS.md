# Migration SQL Files - Exact Locations

**Date**: 2026-01-15

---

## File Locations

All migration SQL files are in your project. Here are the exact paths:

### 1. Table Migration
**Path**: `supabase/migrations/20260111220000_create_reconciliation_queue.sql`

**Full Path**: 
```
/Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1/supabase/migrations/20260111220000_create_reconciliation_queue.sql
```

**What it does**: Creates the `reconciliation_queue` table

---

### 2. Cron Setup Migration
**Path**: `supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql`

**Full Path**:
```
/Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1/supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql
```

**What it does**: Sets up cron jobs to process the queue

---

### 3. RPC Function: Process Queue
**Path**: `supabase/remote_rpcs/process_reconciliation_queue.sql`

**Full Path**:
```
/Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1/supabase/remote_rpcs/process_reconciliation_queue.sql
```

**What it does**: Creates the function that processes queue entries

---

### 4. Updated RPC Function: Sync Daily Usage
**Path**: `supabase/remote_rpcs/rpc_sync_daily_usage.sql`

**Full Path**:
```
/Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1/supabase/remote_rpcs/rpc_sync_daily_usage.sql
```

**What it does**: Updated function with queue insertion logic

---

## Quick Access Commands

### View Migration 1 (Table)
```bash
cat supabase/migrations/20260111220000_create_reconciliation_queue.sql
```

### View Migration 2 (Cron)
```bash
cat supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql
```

### View RPC Function 1 (Process Queue)
```bash
cat supabase/remote_rpcs/process_reconciliation_queue.sql
```

### View RPC Function 2 (Updated Sync)
```bash
cat supabase/remote_rpcs/rpc_sync_daily_usage.sql
```

---

## Application Order

Apply in this order:

1. **First**: `20260111220000_create_reconciliation_queue.sql` (creates table)
2. **Second**: `process_reconciliation_queue.sql` (creates function)
3. **Third**: `20260111220100_setup_reconciliation_queue_cron.sql` (sets up cron, uses function)
4. **Fourth**: `rpc_sync_daily_usage.sql` (updates function, uses table)

---

## How to Apply

### Via Supabase Dashboard

1. Go to: https://supabase.com/dashboard
2. Select your project
3. Go to: **SQL Editor** → **New Query**
4. Open each file (from paths above) and copy/paste the SQL
5. Click **Run**

### Via Terminal (View SQL)

```bash
cd /Users/jefcavens/Dropbox/Tech-projects/payattentionclub-app-1.1

# View all SQL files
cat supabase/migrations/20260111220000_create_reconciliation_queue.sql
cat supabase/remote_rpcs/process_reconciliation_queue.sql
cat supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql
cat supabase/remote_rpcs/rpc_sync_daily_usage.sql
```

---

## File Sizes

- `20260111220000_create_reconciliation_queue.sql`: ~3 KB
- `process_reconciliation_queue.sql`: ~4 KB
- `20260111220100_setup_reconciliation_queue_cron.sql`: ~2 KB
- `rpc_sync_daily_usage.sql`: ~11 KB (updated with queue logic)

---

All files are ready and located in your project directory!


