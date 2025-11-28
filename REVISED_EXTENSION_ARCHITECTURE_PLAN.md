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

### Phase 6: Backend Settlement Rules ✅ ADD

**File:** `supabase/functions/weekly-close/index.ts`

**Update logic:**

**Option A: Settlement Only When Synced (Strict/Fair)**
- Only settle weeks where we have synced usage data
- Missing weeks remain "pending" until sync
- Retroactively apply penalties when data arrives

**Option B: No Sync = Worst Case (Punitive)**
- If no sync by deadline: Assume max overuse
- Charge maximum penalty
- No adjustment when real data arrives

**Option C: Estimate Then Reconcile (Complex)**
- Estimate missing usage (historical pattern or worst-case)
- Settle based on estimate
- Reconcile when real data arrives (adjust next week)

**Recommendation:** Option B (worst-case) - Simple, clear, motivating

**Implementation:**
```typescript
// In weekly-close function
for (const commitment of commitments) {
  const usageData = await getDailyUsageForWeek(commitment);
  
  if (usageData.length === 0) {
    // No sync received
    if (settlementRule === 'worst-case') {
      // Assume max overuse
      await chargeMaxPenalty(commitment);
    } else if (settlementRule === 'pending') {
      // Skip settlement, wait for sync
      await markAsPending(commitment);
    }
  } else {
    // Normal settlement with real data
    await calculateAndChargePenalty(commitment, usageData);
  }
}
```

---

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
Weekly Close → Check for Synced Data → 
  If synced: Calculate penalty
  If not synced: Apply "no sync rule" (worst-case/pending/estimate)
```

---

## Files to Create

1. `Utilities/UsageSyncManager.swift` - Sync manager for main app
2. `Models/DailyUsageEntry.swift` - Data model for daily usage entries
3. `supabase/migrations/rpc_sync_daily_usage.sql` - Backend RPC function
4. `supabase/functions/sync-usage/index.ts` - Edge function (optional)

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

1. **Settlement Rule:** Which option?
   - Option A: Pending (strict/fair)
   - Option B: Worst-case (punitive/motivating) ⭐ Recommended
   - Option C: Estimate + reconcile (complex)

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

