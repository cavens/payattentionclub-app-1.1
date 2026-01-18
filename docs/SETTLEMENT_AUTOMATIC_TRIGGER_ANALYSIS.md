# Settlement Automatic Trigger Analysis
**Date**: 2026-01-17  
**Issue**: Settlement was running automatically in testing mode a few days ago, but now requires manual trigger

---

## Current State

### Settlement Function Behavior

**File**: `supabase/functions/bright-service/index.ts` (lines 504-514)

```typescript
if (TESTING_MODE) {
  const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
  if (!isManualTrigger) {
    console.log("run-weekly-settlement: Skipped - testing mode active (use x-manual-trigger header)");
    return new Response(
      JSON.stringify({ message: "Settlement skipped - testing mode active. Use x-manual-trigger: true header to run." }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }
}
```

**Current Behavior**: 
- In testing mode, settlement **requires** `x-manual-trigger: true` header
- Cron calls (without header) are **skipped**
- Settlement does **NOT** run automatically

---

## What Should Have Been There

### Comparison: Reconciliation Queue Cron

**File**: `supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql`

This migration sets up **two** cron jobs:
1. **Testing mode**: Runs every 1 minute (`* * * * *`)
2. **Normal mode**: Runs every 10 minutes (`*/10 * * * *`)

**Key Point**: The reconciliation queue has automatic cron jobs that run frequently in testing mode.

### Missing: Settlement Cron Job for Testing Mode

**What's Missing**: A similar cron job setup for settlement that:
- Runs every 1-2 minutes in testing mode
- Calls `bright-service` Edge Function
- Includes the `x-manual-trigger: true` header (or bypasses the check)

---

## Analysis: When Did This Change?

### Timeline of Changes

1. **Reconciliation Queue Cron** (2026-01-11):
   - Migration `20260111220100_setup_reconciliation_queue_cron.sql`
   - Sets up automatic cron jobs for reconciliation
   - **Testing mode**: Every 1 minute
   - **Normal mode**: Every 10 minutes

2. **Settlement Function** (Unknown date):
   - Added manual trigger requirement in testing mode
   - **But no corresponding cron job was created**

### The Problem

The settlement function was updated to **require manual triggers** in testing mode, but:
- ❌ **No cron job was created** to automatically call it with the header
- ❌ **No automatic settlement** in testing mode
- ✅ Reconciliation queue has automatic cron (working)
- ❌ Settlement does not have automatic cron (broken)

---

## What Was Likely Working Before

### Hypothesis: Automatic Settlement Cron Job

**Before (working)**:
- There was likely a cron job that:
  - Ran every 1-2 minutes in testing mode
  - Called `bright-service` Edge Function
  - Either:
    a) Included `x-manual-trigger: true` header, OR
    b) The function didn't have the manual trigger check yet

**After (broken)**:
- Manual trigger check was added to function
- But cron job was either:
  a) Never created, OR
  b) Removed/lost, OR
  c) Created but doesn't include the required header

---

## Solution: What Needs to Be Fixed

### Option 1: Create Settlement Cron Job for Testing Mode (Recommended)

**Create a migration** similar to reconciliation queue cron:

```sql
-- Schedule settlement for TESTING MODE (every 2 minutes)
-- This ensures settlement runs automatically after grace period expires
SELECT cron.schedule(
  'run-settlement-testing',  -- Job name
  '*/2 * * * *',             -- Every 2 minutes
  $$
  SELECT
    net.http_post(
      url := 'https://YOUR_PROJECT.supabase.co/functions/v1/bright-service',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-manual-trigger', 'true'  -- Required header for testing mode
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);
```

### Option 2: Remove Manual Trigger Requirement

**Alternative**: Remove the manual trigger check and let settlement run automatically:
- Function processes normally in testing mode
- Cron job can call it without special header
- Simpler, but less explicit control

### Option 3: Check app_config for Testing Mode

**Current Issue**: Function checks `TESTING_MODE` environment variable, but testing mode is now in `app_config` table.

**Fix**: Update function to check `app_config` table (like `super-service` does), and allow automatic cron if testing mode is enabled in database.

---

## Recommendation

**Create a migration** to set up automatic settlement cron job for testing mode:

1. **Create migration**: `20260117160000_setup_settlement_cron_testing_mode.sql`
2. **Set up cron job**: Every 2 minutes in testing mode
3. **Include header**: `x-manual-trigger: true` in cron call
4. **Match pattern**: Similar to reconciliation queue cron setup

This will restore automatic settlement in testing mode while maintaining the manual trigger requirement for explicit control.

---

## Files to Check

1. ✅ `supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql` - Example of working cron setup
2. ❌ **Missing**: Settlement cron job migration
3. ✅ `supabase/functions/bright-service/index.ts` - Has manual trigger check
4. ❓ Check git history for when manual trigger check was added

---

## Next Steps

1. **Verify**: Check if there was ever a settlement cron job migration
2. **Create**: Migration for automatic settlement cron in testing mode
3. **Test**: Verify settlement runs automatically after grace period expires


