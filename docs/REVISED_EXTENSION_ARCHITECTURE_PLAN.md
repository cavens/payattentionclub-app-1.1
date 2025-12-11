# Revised Extension Architecture Plan

## Critical Issue Identified

**Problem:** Extension network reporting fails when app is force-quit. Most users will have the app killed most of the time, making extension-based reporting unreliable for weekly settlements.

**Root Cause:** iOS terminates extension processes aggressively when the main app is force-quit. Network requests cannot complete before termination.

**Solution:** Redesign architecture to separate tracking (extension) from reporting (main app).

---

## New Architecture: Tracking vs Reporting

### Core Principle
- **Tracking** = Extension writes usage data to App Group (local storage, no network)
- **Reporting** = Main app syncs to server opportunistically (when app opens)
- **Settlement** = Backend handles missing data with clear rules

### Why This Works
- Extension doesn't need network access → No termination issues
- iOS Screen Time continues tracking even when app is force-quit
- Main app syncs all missing data when it opens
- Backend has clear rules for missing data

---

## Implementation Plan

### Phase 1: Remove Extension Network Reporting ❌ REMOVE

**Files to modify:**
- `DeviceActivityMonitorExtension/ExtensionBackendClient.swift` - **DELETE** (no longer needed)
- `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` - Remove network reporting code

**What to remove:**
- `ExtensionBackendClient` class (entire file)
- Network reporting calls from `eventDidReachThreshold()`
- Rate limiting for network reports (keep for local writes)
- Network test code (can keep for diagnostics)

**What to keep:**
- App Group storage (writing usage data locally)
- Threshold event handling
- Usage aggregation logic

---

### Phase 2: Enhanced Local Storage in Extension ✅ ADD

**File:** `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`

**New functionality:**
- Write daily usage summaries to App Group
- Store per-day usage data in structured format
- Track last sync timestamp per day

**Data structure in App Group:**
```swift
// Daily usage entry
{
  "date": "2025-11-27",
  "total_minutes": 141,
  "baseline_minutes": 0,
  "used_minutes": 141,
  "last_updated_at": 1764285465.0,
  "synced": false  // Has this been synced to server?
}
```

**Implementation:**
- On threshold events: Update daily usage totals
- Store in App Group UserDefaults or JSON file
- Key format: `daily_usage_YYYY-MM-DD`

---

### Phase 3: Sync Logic in Main App ✅ ADD

**File:** `Utilities/UsageSyncManager.swift` (NEW)

**Purpose:** Sync unsynced usage data from App Group to backend

**Functionality:**
- On app launch/foreground: Read all unsynced daily usage entries
- Compare with server's "last synced" timestamp
- Upload only new/updated periods
- Mark as synced after successful upload

**Methods:**
```swift
class UsageSyncManager {
    // Read all unsynced usage from App Group
    func getUnsyncedUsage() -> [DailyUsageEntry]
    
    // Sync to backend
    func syncToBackend() async throws
    
    // Mark entries as synced
    func markAsSynced(dates: [String])
}
```

**Integration points:**
- `AppModel.init()` - Check for unsynced data on launch
- `ContentView.onAppear` - Sync when app comes to foreground
- After successful commitment creation - Sync baseline

---

### Phase 4: Update BackendClient ✅ MODIFY

**File:** `Utilities/BackendClient.swift`

**New method:**
```swift
/// Sync multiple daily usage entries at once
func syncDailyUsage(_ entries: [DailyUsageEntry]) async throws -> SyncResponse
```

**Modify existing:**
- `reportUsage()` - Keep for single-day reporting (backward compatibility)
- Add batch reporting endpoint support

---

### Phase 5: Backend Changes ✅ ADD

**New RPC Function:** `rpc_sync_daily_usage`

**Purpose:** Accept multiple daily usage entries in one call

**Input:**
```json
{
  "entries": [
    {
      "date": "2025-11-27",
      "used_minutes": 141,
      "week_start_date": "2025-12-01"
    },
    ...
  ]
}
```

**Process:**
- For each entry: Upsert `daily_usage` table
- Recompute weekly totals
- Return sync status

**Edge Function:** `sync-usage` (optional, if needed)

---

### Phase 6: Weekly Settlement Flow (Setup Intent + Fixed Grace Period) ✅ PLAN UPDATE

**Reality check (current state)**
- Stripe Setup Intents already run during commitment lock-in, giving us a reusable off-session payment method (PaymentMethod ID).
- Worst-case penalty math already exists today (Option B logic inside `supabase/functions/weekly-close/index.ts`).
- loops.so is our email provider.

**North star**
- Every commitment follows the same cadence: week ends Monday at 12:00 ET, grace ends Tuesday at 12:00 ET.
- Monday 12:05 ET → send a single loops.so reminder email telling users to open the app before Tuesday noon.
- Tuesday 12:00 ET → settlement job charges actual penalties for synced users and worst-case penalties for unsynced users, using the saved payment method.
- Late syncs automatically reconcile by refunding or charging the difference.

#### Step-by-step plan (each step is testable before moving on)

1. **Step 0 – Requirements lock (this update) ✅**
   - Replace authorization-hold language with Setup Intent + saved payment method.
   - Document the global Monday/Tues schedule and loops.so reminder.
   - Capture the step-by-step flow below so every future change references the same plan.

2. **Step 1 – Schema prep & backfill**
   - Add/rename columns: `saved_payment_method_id`, `week_grace_expires_at`, `charge_payment_intent_id`, `charged_amount_cents`, `actual_amount_cents`, `refund_amount_cents`, `settlement_status`, timestamps, etc.
   - Remove or deprecate authorization-specific columns that no longer apply.
   - Backfill existing rows with sensible defaults and regenerate Supabase types.
   - **Tests:** run migrations locally and ensure backend builds compile.

3. **Step 2 – Reminder flow (Monday 12:05 ET)**
   - Create `supabase/functions/send-week-end-reminders/index.ts`.
   - Integrate loops.so template (name, week_end_date, grace_deadline placeholders).
   - Schedule a single weekly cron right after Monday noon ET (no hourly retries).
   - **Tests:** dry-run with staging users and confirm loops delivery/logging.

4. **Step 3 – Settlement job (Tuesday 12:00 ET)**
   - Create `supabase/functions/run-weekly-settlement/index.ts`.
   - For each commitment: if synced → charge actual penalty; if unsynced → charge existing worst-case value.
   - Record PaymentIntent IDs + amounts on the commitment/week tables.
   - **Tests:** invoke manually with fixtures covering synced/unsynced users and verify Stripe + DB records.

5. **Step 4A – Detect late-sync reconciliation needs ✅**
   - Extend `rpc_sync_daily_usage` (and any shared helpers) to look up already-settled weeks and compare new totals against `charged_amount_cents`.
   - Populate `needs_reconciliation`, `reconciliation_delta_cents`, `reconciliation_reason`, and timestamps on `user_week_penalties`.
   - **Tests:** simulate a late sync in SQL and confirm the RPC response plus table rows flag the delta correctly.

6. **Step 4B – Reconciliation processor (Edge Function) ✅**
   - `supabase/functions/settlement-reconcile/index.ts` scans `user_week_penalties` for `needs_reconciliation = true`, issues Stripe refunds (negative deltas) or incremental PaymentIntents (positive deltas), and logs each update in `payments`.
   - On success it brings rows back to steady state (`needs_reconciliation = false`, `settlement_status` → `refunded[_partial]` or `charged_actual_adjusted`).
   - **Tests:** seed via `rpc_setup_test_data`, flag deltas with `rpc_sync_daily_usage`, then POST to the new function (optionally `dryRun`) and verify Stripe + DB mutations.

7. **Step 4C – Integration + guardrails ✅**
   - Added structured logging + dry-run output so `quick-handler` can be monitored directly from Supabase logs.
   - Documented cron setup + curl tester instructions in `supabase/functions/settlement-reconcile/README.md` (recommendation: run every 6 h or immediately post-settlement).
   - Expanded `test_rpc_sync_daily_usage.sql` with reconciliation QA notes to keep Scenario C reproducible.
   - **Tests:** full dry-run + live refund executed (`quick-handler` → Stripe refund) following the documented seed/run steps.

8. **Step 5 – Frontend & copy ✅**
   - Authorization screen now explains the saved-card + Tuesday noon cadence to set expectations upfront.
   - Added `SettlementStatusView` and wired it into Monitor + Bulletin so users can see waiting/worst-case/refund/settled states with a manual refresh hook.
   - Countdown stack now includes a weekly deadline banner that repeats the “open the app before Tuesday 12:00 PM ET” rule of thumb.
   - **Tests:** open the app, lock in a commitment, and visit Monitor/Bulletin to confirm the new copy plus settlement card show the correct amounts/status after running the weekly jobs.

9. **Step 6 – Monitoring & alerts**
   - Add structured logs + alerting for reminder job, settlement job, and refund/extra-charge flows.
   - Define alert channels (Slack/PagerDuty) for failures or missed cron executions.
   - **Tests:** inject failures to confirm alerts trigger.

10. **Step 7 – End-to-end QA**
   - Scenario A: user syncs Monday afternoon → only actual penalty is charged.
   - Scenario B: user never opens the app → Tuesday worst-case charge fires.
   - Scenario C: user syncs Wednesday → refund/extra charge path completes.
   - Scenario D: payment method missing/expired → verify fallback copy + reminder to re-run Setup Intent.
   - Log each outcome in QA notes for regression.

### Phase 7: UX Updates ✅ ADD

**File:** `Views/MonitorView.swift` or new `SyncStatusView.swift`

**Show sync status:**
- "Last synced: 2 hours ago"
- "Unsynced data: 3 days"
- Sync progress indicator

**Onboarding updates:**
- Explain: "Open the app at least once per week to sync your usage"
- Clear messaging about sync requirement

**Push notifications (future):**
- "Time to sync your week and see your results"
- Send Sunday evening reminder

---

## Data Flow (New Architecture)

### Tracking (Extension)
```
Threshold Event → Update Daily Usage → Write to App Group → Done
```

### Reporting (Main App)
```
App Opens → Read Unsynced Usage → Upload to Backend → Mark as Synced
```

### Settlement (Backend)
```
Commitment Created → Setup Intent completed (payment method saved) →
Week Ends (Mon 12:00 ET) → loops.so reminder @ 12:05 ET →
  If user opens app before Tue 12:00 ET: Sync + charge actual penalty
  If user does not open app: Tue 12:00 ET settlement charges worst-case →
    If user syncs later: Recalculate actual penalty, refund difference or charge additional
```

---

## Files to Create

1. `Utilities/UsageSyncManager.swift` - Sync manager for main app ✅ DONE
2. `Models/DailyUsageEntry.swift` - Data model for daily usage entries ✅ DONE
3. `supabase/migrations/rpc_sync_daily_usage.sql` - Backend RPC function ✅ DONE
4. `supabase/functions/sync-usage/index.ts` - Edge function (optional)
5. `supabase/migrations/add_weekly_settlement_columns.sql` - Adds saved payment method + charge/refund fields
6. `supabase/functions/send-week-end-reminders/index.ts` - loops.so blast Monday 12:05 ET
7. `supabase/functions/run-weekly-settlement/index.ts` - Tuesday settlement (actual vs worst-case)
8. `supabase/functions/settlement-reconcile/index.ts` - Late-sync refunds & extra charges
9. `Views/SettlementStatusView.swift` - Show settlement status to users

---

## Files to Modify

1. `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`
   - Remove network reporting
   - Add enhanced local storage
   - Write daily usage summaries to App Group

2. `Utilities/BackendClient.swift`
   - Add `syncDailyUsage()` method
   - Keep `reportUsage()` for backward compatibility

3. `Models/AppModel.swift`
   - Add sync check on launch
   - Track sync status

4. `Views/MonitorView.swift`
   - Show sync status
   - Trigger sync on appear

5. `supabase/functions/weekly-close/index.ts`
   - Add "no sync" handling logic
   - Implement chosen settlement rule

---

## Files to Delete

1. `DeviceActivityMonitorExtension/ExtensionBackendClient.swift` - **DELETE**
   - No longer needed (extension doesn't make network calls)

---

## Implementation Order

### Day 1: Remove Extension Network Code
1. ✅ Delete `ExtensionBackendClient.swift`
2. ✅ Remove network reporting from `DeviceActivityMonitorExtension.swift`
3. ✅ Keep local storage (App Group writes)
4. ✅ Test that extension still writes to App Group

### Day 2: Enhanced Local Storage
1. ✅ Add daily usage aggregation in extension
2. ✅ Store structured daily usage entries in App Group
3. ✅ Track sync status per day
4. ✅ Test that data is stored correctly

### Day 3: Sync Manager in Main App
1. ✅ Create `UsageSyncManager.swift`
2. ✅ Implement reading unsynced usage from App Group
3. ✅ Implement syncing to backend
4. ✅ Test sync on app launch

### Day 4: Backend Support
1. ✅ Create `rpc_sync_daily_usage` RPC function
2. ✅ Update `weekly-close` with "no sync" rules
3. ✅ Test batch sync endpoint
4. ✅ Test settlement with missing data

### Day 5: UX & Polish
1. ✅ Add sync status UI
2. ✅ Update onboarding messaging
3. ✅ Test full flow
4. ✅ Document settlement rules

---

## Testing Plan

### Test 1: Extension Local Storage
- Create commitment
- Use device (trigger thresholds)
- Check App Group for daily usage entries
- Verify data structure is correct

### Test 2: Sync on App Launch
- Force-quit app
- Use device (extension writes to App Group)
- Open app
- Verify sync happens automatically
- Check backend for synced data

### Test 3: Multiple Days Sync
- Use device over multiple days
- Don't open app
- Open app after 3 days
- Verify all 3 days sync correctly

### Test 4: Settlement with Missing Data
- Create commitment
- Don't open app for a week
- Run weekly settlement
- Verify "no sync" rule is applied

### Test 5: Settlement with Synced Data
- Create commitment
- Open app daily (sync happens)
- Run weekly settlement
- Verify normal settlement with real data

---

## Key Decisions Needed

1. **Settlement Rule:** ✅ Locked — Setup Intent + Tuesday noon ET fallback (worst-case charge) with late-sync reconciliation (Phase 6 plan). Future consideration: adjust grace window length if user feedback demands it.

2. **Data Storage Format:**
   - UserDefaults (simple)
   - JSON file in App Group (more structured)
   - SQLite in App Group (overkill?)

3. **Sync Frequency:**
   - On every app launch?
   - Throttled (max once per hour)?
   - Manual sync button?

4. **Backward Compatibility:**
   - Keep `reportUsage()` for single-day calls?
   - Or migrate everything to batch sync?

---

## Benefits of New Architecture

✅ **Technically Compliant:** Works within iOS limitations
✅ **Reliable:** Extension doesn't depend on network
✅ **Accurate:** All usage data eventually synced
✅ **Simple:** Clear mental model for users
✅ **Motivating:** Incentive to open app weekly (fits mission)

---

## Risks & Mitigations

**Risk:** Users forget to open app → Missing settlements
**Mitigation:** Clear onboarding + push notifications + "no sync" rule

**Risk:** Large sync payloads if many days unsynced
**Mitigation:** Batch sync endpoint + compression if needed

**Risk:** App Group storage limits
**Mitigation:** Clean up old synced data periodically

---

## Next Steps

1. **Decide on settlement rule** (Option A, B, or C)
2. **Design data structure** for App Group storage
3. **Start with Phase 1** (remove extension network code)
4. **Implement Phase 2** (enhanced local storage)
5. **Build Phase 3** (sync manager)

---

## Notes

- Extension network reporting was a good attempt but hits iOS limitations
- New architecture is more robust and iOS-compliant
- Settlement rules are product decisions, not just technical
- UX messaging is critical for user understanding

