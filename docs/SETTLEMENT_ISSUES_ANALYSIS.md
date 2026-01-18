# Settlement Issues Analysis
**Date**: 2026-01-17  
**Commitment ID**: `14566fd5-ea73-413d-8d56-d6394837591c`

---

## Issue 1: Why Settlement Hasn't Triggered Automatically

### Root Cause
**Settlement requires manual trigger in testing mode, but no cron job is set up to provide it.**

### Current Behavior

1. **Settlement Function** (`bright-service/index.ts`):
   ```typescript
   // In testing mode, also require manual trigger header (in addition to secret)
   if (isTestingMode) {
     const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
     if (!isManualTrigger) {
       console.log("run-weekly-settlement: Skipped - testing mode active");
       return new Response(
         JSON.stringify({ message: "Settlement skipped - testing mode active. Use x-manual-trigger: true header to run." }),
         { status: 200 }
       );
     }
   }
   ```

2. **No Cron Job**: 
   - ❌ No migration exists to create a settlement cron job
   - ❌ No automatic trigger in testing mode
   - ✅ Reconciliation queue has automatic cron (every 1 minute in testing mode)
   - ❌ Settlement does not have automatic cron

### Why This Happened

The settlement function was updated to require `x-manual-trigger: true` header in testing mode for safety, but:
- No corresponding cron job was created to automatically call it with this header
- This was identified in `docs/SETTLEMENT_AUTOMATIC_TRIGGER_ANALYSIS.md` but never implemented

### Solution

**Create a migration** to set up automatic settlement cron job for testing mode:

```sql
-- Schedule settlement for TESTING MODE (every 2 minutes)
-- This ensures settlement runs automatically after grace period expires
SELECT cron.schedule(
  'run-settlement-testing',
  '*/2 * * * *',  -- Every 2 minutes
  $$
  SELECT
    net.http_post(
      url := 'https://YOUR_PROJECT.supabase.co/functions/v1/bright-service',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-manual-trigger', 'true',  -- Required header for testing mode
        'x-settlement-secret', 'YOUR_SECRET'  -- Required for authentication
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);
```

**Note**: The cron job needs:
1. `x-manual-trigger: true` header (to bypass testing mode check)
2. `x-settlement-secret` header (for authentication)

---

## Issue 2: Why Charged Amount Would Be $5 When App Shows $1.48

### Root Cause
**The app calculates penalty locally, but settlement uses database data. If usage hasn't been synced, settlement charges worst case ($5.00).**

### How It Works

#### 1. **App's Local Calculation** (Shows $1.48)

**File**: `AppModel.swift` (lines 307-313)
```swift
func updateCurrentPenalty() {
    let usageMinutes = Double(currentUsageSeconds - baselineUsageSeconds) / 60.0
    let limitMinutes = self.limitMinutes
    let excessMinutes = max(0, usageMinutes - limitMinutes)
    currentPenalty = excessMinutes * penaltyPerMinute
}
```

- **Source**: Local `currentUsageSeconds` from DeviceActivityMonitor
- **Calculation**: `(usage - limit) * penaltyPerMinute`
- **Display**: Shows $1.48 in the app
- **Problem**: This is **local data only** - not in the database

#### 2. **Settlement's Database Check** (Would Charge $5.00)

**File**: `bright-service/index.ts` (lines 249-272)
```typescript
function hasSyncedUsage(candidate: SettlementCandidate): boolean {
  const penalty = candidate.penalty;
  if (!penalty || (penalty.actual_amount_cents ?? 0) <= 0) {
    return false; // No actual amount set
  }
  
  const deadline = getCommitmentDeadline(candidate);
  if (!penalty.last_updated) {
    return true; // Legacy behavior
  }
  
  const lastUpdated = new Date(penalty.last_updated);
  return lastUpdated.getTime() > deadline.getTime();
}
```

**Settlement Logic** (lines 607-609):
```typescript
const chargeType: ChargeType = hasUsage ? "actual" : "worst_case";
const amountCents = getChargeAmount(candidate, chargeType);
```

- **Source**: `user_week_penalties.actual_amount_cents` in database
- **Check**: If `actual_amount_cents` is 0 or NULL → charge worst case
- **Result**: Charges $5.00 (worst case) if usage not synced

#### 3. **Usage Sync Process**

**File**: `rpc_sync_daily_usage.sql` (lines 100-150)

When usage is synced:
1. App calls `rpc_sync_daily_usage` with daily usage entries
2. RPC calculates penalty: `exceeded_minutes * penalty_per_minute_cents`
3. RPC updates `user_week_penalties.actual_amount_cents` with calculated penalty
4. Settlement then sees `actual_amount_cents > 0` and charges actual amount

**If usage is NOT synced**:
- `actual_amount_cents` remains 0 or NULL
- Settlement sees no usage → charges worst case ($5.00)

### Why Usage Might Not Be Synced

1. **App hasn't called `syncDailyUsage()`**:
   - Usage sync is triggered by `UsageSyncManager.syncToBackend()`
   - This is called on app foreground, but may not have run yet
   - Or sync may have failed silently

2. **Sync happened before deadline**:
   - Settlement checks if `last_updated > deadline`
   - If usage was synced before deadline, it's ignored
   - Only usage synced AFTER deadline counts

3. **Sync failed**:
   - Network error
   - Authentication error
   - RPC error

### Current Status

**From verification results**:
- **Penalty record**: `actual_amount_cents: 0` (no usage synced)
- **Settlement status**: `pending` (not settled yet)
- **Expected charge**: $5.00 (worst case) when settlement runs

**App shows**: $1.48 (local calculation, not in database)

### Solution

**Ensure usage is synced before settlement runs**:

1. **Manual sync**: Open the app and let it sync usage
2. **Check sync status**: Verify `actual_amount_cents` is set in `user_week_penalties`
3. **Timing**: Usage must be synced AFTER the deadline to count

**Or wait for automatic sync**:
- App syncs usage on foreground
- But if app isn't opened, usage won't sync
- Settlement will charge worst case

---

## Summary

| Issue | Root Cause | Impact | Solution |
|-------|------------|--------|----------|
| **Settlement not automatic** | No cron job with `x-manual-trigger` header | Settlement must be manually triggered | Create cron job migration |
| **$5 vs $1.48 discrepancy** | Usage not synced to database | Settlement charges worst case instead of actual | Ensure usage sync runs before settlement |

---

## Recommendations

### Immediate Actions

1. **Create settlement cron job** for testing mode:
   - Every 2 minutes
   - Include `x-manual-trigger: true` header
   - Include `x-settlement-secret` header

2. **Verify usage sync**:
   - Check if `actual_amount_cents` is set in `user_week_penalties`
   - If not, manually trigger sync from app
   - Or wait for app to sync on next foreground

### Long-term Improvements

1. **Better sync reliability**:
   - Background sync task
   - Retry logic for failed syncs
   - Notification when sync fails

2. **Settlement timing**:
   - Consider extending grace period if usage not synced
   - Or send notification to user to sync before settlement

3. **User communication**:
   - Show in app when usage is synced vs. not synced
   - Warn user if settlement will charge worst case

---

## Files to Check

1. ✅ `docs/SETTLEMENT_AUTOMATIC_TRIGGER_ANALYSIS.md` - Identified the cron job issue
2. ❌ **Missing**: Settlement cron job migration
3. ✅ `supabase/functions/bright-service/index.ts` - Has manual trigger check
4. ✅ `supabase/remote_rpcs/rpc_sync_daily_usage.sql` - Updates `actual_amount_cents`
5. ✅ `payattentionclub-app-1.1/Utilities/UsageSyncManager.swift` - Handles usage sync


