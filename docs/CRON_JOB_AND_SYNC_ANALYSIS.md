# Cron Job and Usage Sync Analysis
**Date**: 2026-01-17  
**Issues**: 
1. Settlement cron job not actually created
2. Usage not syncing when opening app

---

## Issue 1: Settlement Cron Job - NOT Actually Created

### What We Did

**We documented it but didn't create it!**

- ✅ **Documented**: `docs/SETTLEMENT_ISSUES_ANALYSIS.md` - Explained the need for cron job
- ✅ **Documented**: `docs/SETTLEMENT_AUTOMATIC_TRIGGER_ANALYSIS.md` - Detailed the solution
- ❌ **NOT Created**: No migration file exists for settlement cron job

### Current Status

**Migrations directory** (`supabase/migrations/`):
- ✅ `20260111220100_setup_reconciliation_queue_cron.sql` - Reconciliation queue cron (exists)
- ❌ **Missing**: Settlement cron job migration

### What Should Exist

**Migration file**: `supabase/migrations/20260117180000_setup_settlement_cron_testing_mode.sql`

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
        'x-settlement-secret', current_setting('app.settings.settlement_secret', true)  -- From app_config
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);
```

**But this was never created!**

---

## Issue 2: Usage Not Syncing When Opening App

### How Sync Should Work

**File**: `payattentionclub_app_1_1App.swift` (lines 30-44)

```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    // Update daily usage and sync when app comes to foreground
    Task { @MainActor in
        // Check if deadline has passed and store consumedMinutes at deadline if needed
        let tracker = UsageTracker.shared
        if tracker.isCommitmentDeadlinePassed() {
            let consumedMinutes = tracker.getConsumedMinutes()
            // Only store if we don't already have a stored value
            if tracker.getConsumedMinutesAtDeadline() == nil {
                tracker.storeConsumedMinutesAtDeadline(consumedMinutes)
                NSLog("APP Foreground: ⏰ Deadline passed, stored consumedMinutes at deadline: \(consumedMinutes) min")
            }
        }
        await UsageSyncManager.shared.updateAndSync()
    }
}
```

**This should**:
1. ✅ Trigger when app comes to foreground
2. ✅ Call `UsageSyncManager.shared.updateAndSync()`
3. ✅ Update daily usage entries
4. ✅ Sync to backend

### Why It Might Not Be Working

#### Problem 1: Sync May Be Failing Silently

**File**: `UsageSyncManager.swift` (lines 369-380)

```swift
func updateAndSync() async {
    // First, update daily usage entries from consumedMinutes
    updateDailyUsageFromConsumedMinutes()
    
    // Then, sync to backend
    do {
        try await syncToBackend()
        NSLog("SYNC UsageSyncManager: ✅ Update and sync completed successfully")
    } catch {
        NSLog("SYNC UsageSyncManager: ❌ Update and sync failed: \(error)")
    }
}
```

**Issues**:
- ❌ Errors are only logged, not surfaced to user
- ❌ If sync fails, user doesn't know
- ❌ No retry logic

#### Problem 2: No Unsynced Entries

**File**: `UsageSyncManager.swift` (lines 146-151)

```swift
// Check for unsynced entries
let unsyncedEntries = getUnsyncedUsage()

guard !unsyncedEntries.isEmpty else {
    return  // ⚠️ Returns silently if no unsynced entries
}
```

**If**:
- All entries are already marked as `synced: true`
- Or no entries exist yet
- **Then**: Sync returns silently without doing anything

#### Problem 3: Usage Data Not Being Created

**File**: `UsageSyncManager.swift` (lines 230-360)

The `updateDailyUsageFromConsumedMinutes()` function:
- Checks if deadline has passed
- If deadline passed, uses stored value or history
- If deadline not passed, updates current entry

**Potential issues**:
1. **Deadline check may be wrong**:
   ```swift
   if tracker.isCommitmentDeadlinePassed() {
       // Use stored value
   } else {
       // Update current entry
   }
   ```
   - If deadline check fails, may not create entry

2. **Week start date mismatch**:
   ```swift
   let weekStartDateString = UsageTracker.shared.getWeekStartDateString()
   ```
   - If week start date doesn't match commitment's `week_end_date`, entry won't be associated correctly

3. **Entry already exists for different commitment**:
   ```swift
   if existingEntry.commitmentId != currentCommitmentId {
       NSLog("SYNC UsageSyncManager: ⚠️ Entry exists for different commitment, skipping update")
       return
   }
   ```
   - If commitment ID changed, entry won't be updated

#### Problem 4: Sync Coordinator Throttling

**File**: `UsageSyncManager.swift` (lines 130-137)

```swift
func syncToBackend() async throws {
    let canStart = await SyncCoordinator.shared.tryStartSync()
    
    guard canStart else {
        return  // ⚠️ Returns silently if sync already in progress or too soon
    }
}
```

**SyncCoordinator** (lines 16-42):
- Prevents concurrent syncs
- Enforces minimum 5-second interval between syncs
- If sync was called < 5 seconds ago, it returns silently

**This could cause**:
- If app opens multiple times quickly, sync may be skipped
- If sync is already in progress, new sync is skipped

#### Problem 5: Authentication Issues

**File**: `BackendClient.swift` (lines 754-757)

```swift
nonisolated func syncDailyUsage(_ entries: [DailyUsageEntry]) async throws -> [String] {
    guard await isAuthenticated else {
        throw BackendError.notAuthenticated
    }
```

**If**:
- User is not authenticated
- Token expired
- **Then**: Sync fails with authentication error

---

## Root Cause Analysis

### Why Usage Shows $1.48 in App But $0 in Database

**App calculation** (local):
- Uses `currentUsageSeconds` from DeviceActivityMonitor
- Calculates: `(usage - limit) * penaltyPerMinute = $1.48`

**Database** (from verification):
- Usage entry: 0 minutes used
- Penalty record: `actual_amount_cents: 0`

**Possible causes**:
1. **Usage entry created with 0 minutes**:
   - If `consumedMinutes` is 0 when entry is created
   - Or if `baselineMinutes` equals `totalMinutes`

2. **Usage not synced after deadline**:
   - If usage was synced before deadline
   - Settlement only counts usage synced AFTER deadline
   - But entry shows 0 minutes anyway

3. **Baseline issue**:
   - If `baselineUsageSeconds` was set incorrectly
   - Or if `consumedMinutes` doesn't account for baseline

4. **Entry created but not updated**:
   - Entry created with 0 minutes
   - Never updated with actual usage
   - Sync runs but has nothing to sync (entry already exists)

---

## Solutions

### Solution 1: Create Settlement Cron Job

**Create migration**: `supabase/migrations/20260117180000_setup_settlement_cron_testing_mode.sql`

**Note**: Need to get `SETTLEMENT_SECRET` from `app_config` or environment variable.

### Solution 2: Fix Usage Sync

**Immediate fixes**:
1. **Add logging** to see what's happening:
   - Log when `updateAndSync()` is called
   - Log when entries are found/not found
   - Log when sync succeeds/fails

2. **Check if entries exist**:
   - Verify `daily_usage` entries are being created
   - Verify entries have correct `commitment_id`
   - Verify entries have correct `week_start_date`

3. **Check sync status**:
   - Verify `synced` flag is being set correctly
   - Verify entries are being marked as synced

4. **Check authentication**:
   - Verify user is authenticated when sync runs
   - Verify token is valid

**Long-term fixes**:
1. **Add retry logic** for failed syncs
2. **Show sync status** to user
3. **Force sync** button in UI
4. **Background sync** task

---

## Action Items

### Immediate

1. ✅ **Create settlement cron job migration**
2. ✅ **Add detailed logging** to usage sync
3. ✅ **Check database** for usage entries
4. ✅ **Verify authentication** status

### Investigation

1. **Check logs** when app opens:
   - Is `updateAndSync()` being called?
   - Are entries being found?
   - Is sync succeeding or failing?

2. **Check database**:
   - Do `daily_usage` entries exist?
   - Are they marked as `synced: true`?
   - Do they have correct `commitment_id`?

3. **Check app state**:
   - Is user authenticated?
   - Is `consumedMinutes` being tracked?
   - Is `baselineUsageSeconds` set correctly?

---

## Files to Check

1. ❌ **Missing**: `supabase/migrations/20260117180000_setup_settlement_cron_testing_mode.sql`
2. ✅ `payattentionclub_app_1_1App.swift` - Calls `updateAndSync()` on foreground
3. ✅ `UsageSyncManager.swift` - Handles sync logic
4. ✅ `BackendClient.swift` - Calls `rpc_sync_daily_usage`
5. ✅ `UsageTracker.swift` - Tracks consumed minutes


