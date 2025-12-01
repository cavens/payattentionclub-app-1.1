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

### Phase 6: Authorization-Based Settlement Rules ✅ ADD

**Approach:** Authorization charge at commitment start + 24-hour grace period + email notification + retroactive settlement with refunds

**Core Principle:**
- Authorization amount (worst-case) is calculated and held when commitment is created
- User has 24 hours after week end date to sync data
- Email notification sent at week end date reminding user to sync
- If user doesn't sync within 24h → Authorization is charged
- If user syncs later → Calculate actual penalty and refund difference (or charge additional)

---

#### 6.1 Database Schema Changes

**Add to `commitments` table:**
```sql
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS authorization_amount_cents INTEGER;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS authorization_charged_at TIMESTAMP;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS authorization_payment_intent_id TEXT;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS grace_period_ends_at TIMESTAMP;
```

**Add to `user_week_penalties` table:**
```sql
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS authorization_amount_cents INTEGER;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS actual_penalty_cents INTEGER;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS refund_amount_cents INTEGER;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS refund_payment_intent_id TEXT;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS settlement_status TEXT; 
-- Values: 'pending', 'authorization_charged', 'settled', 'refunded'
```

**Add to `payments` table:**
```sql
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_type TEXT; 
-- Values: 'authorization', 'penalty', 'refund'
ALTER TABLE payments ADD COLUMN IF NOT EXISTS related_payment_intent_id TEXT; 
-- For refunds, link to original charge
```

---

#### 6.2 Authorization Hold Creation

**File:** `BackendClient.createCommitment()` + Backend RPC function

**Update `createCommitment` to:**
- Calculate authorization amount (worst-case penalty)
- Create Stripe PaymentIntent with `capture_method: 'manual'` (authorization hold)
- Store `authorization_payment_intent_id` in commitment
- Calculate `grace_period_ends_at` = `week_end_date + 24 hours`
- Return authorization amount and PaymentIntent ID

**Stripe Flow:**
```typescript
const paymentIntent = await stripe.paymentIntents.create({
  amount: authorizationAmountCents,
  currency: 'usd',
  customer: stripeCustomerId,
  capture_method: 'manual',  // Authorization hold (not captured yet)
  description: `Authorization for commitment week ending ${weekEndDate}`,
  metadata: {
    commitment_id: commitmentId,
    type: 'authorization',
    week_end_date: weekEndDate
  }
});
```

---

#### 6.3 Grace Period Logic

**File:** `supabase/functions/charge-authorization-after-grace-period/index.ts` (NEW)

**Purpose:** Charge authorization amount if user hasn't synced within 24 hours

**Scheduled:** Hourly cron job

**Logic:**
```typescript
// Find commitments where:
// - grace_period_ends_at < NOW()
// - authorization_charged_at IS NULL (not charged yet)
// - No daily_usage entries exist for this week

const expiredCommitments = await findExpiredGracePeriods();

for (const commitment of expiredCommitments) {
  const hasSynced = await checkIfSynced(commitment);
  
  if (!hasSynced) {
    // Charge the authorization
    const paymentIntent = await stripe.paymentIntents.capture(
      commitment.authorization_payment_intent_id
    );
    
    await updateCommitment({
      authorization_charged_at: NOW(),
      status: 'authorization_charged'
    });
    
    await createUserWeekPenalties({
      authorization_amount_cents: commitment.authorization_amount_cents,
      actual_penalty_cents: null,  // Not synced yet
      settlement_status: 'authorization_charged'
    });
  }
}
```

---

#### 6.4 Email Notification System

**File:** `supabase/functions/send-week-end-notification/index.ts` (NEW)

**Purpose:** Send email at week end date reminding user to sync

**Scheduled:** Hourly cron job

**Email Template:**
```
Subject: "Your PayAttentionClub week ended - Check your results!"

Hi [User Name],

Your commitment week ending [Week End Date] has ended!

📊 Check your results:
- Attention Score: [Score]
- Penalty Amount: [Amount]
- Weekly Pool: [Pool Amount]

⏰ Important: You have 24 hours to open the app and sync your data.
After 24 hours, we'll charge the authorization amount.

[Open App Button]

Thanks,
PayAttentionClub Team
```

**Logic:**
```typescript
// Find commitments where week_end_date = TODAY
const endedCommitments = await findEndedCommitments();

for (const commitment of endedCommitments) {
  const hasSynced = await checkIfSynced(commitment);
  
  if (!hasSynced) {
    await sendEmail({
      to: user.email,
      template: 'week_end_notification',
      data: {
        userName: user.name,
        weekEndDate: commitment.week_end_date,
        gracePeriodEndsAt: commitment.grace_period_ends_at
      }
    });
  }
}
```

**Email Service:** Supabase Edge Function + Resend/SendGrid/SES

---

#### 6.5 Late Sync Handling

**File:** `rpc_sync_daily_usage.sql` (UPDATE)

**New Logic After Sync:**
1. Sync daily usage entries (existing)
2. Check if this week's commitment has authorization charged
3. Calculate actual penalty from synced data
4. Compare actual penalty vs authorization amount
5. If authorization was charged:
   - If actual < authorization → Refund difference
   - If actual > authorization → Charge additional amount
6. Update `user_week_penalties` with actual penalty and refund info

**Refund Logic:**
```typescript
if (authorizationCharged && actualPenalty < authorizationAmount) {
  const refundAmount = authorizationAmount - actualPenalty;
  
  const refund = await stripe.refunds.create({
    payment_intent: authorizationPaymentIntentId,
    amount: refundAmount,  // Partial refund
    reason: 'requested_by_customer',
    metadata: {
      commitment_id: commitmentId,
      week_end_date: weekEndDate,
      actual_penalty: actualPenalty,
      authorization_amount: authorizationAmount
    }
  });
  
  await updateUserWeekPenalties({
    actual_penalty_cents: actualPenalty,
    refund_amount_cents: refundAmount,
    refund_payment_intent_id: refund.id,
    settlement_status: 'refunded'
  });
}
```

---

#### 6.6 Weekly-Close Function Updates

**File:** `supabase/functions/weekly-close/index.ts` (UPDATE)

**Remove:** Option B code (no sync = worst case) - lines 101-167

**Add:** Authorization vs actual penalty logic

**New Logic:**
```typescript
for (const commitment of commitments) {
  // Check if authorization was charged
  if (commitment.authorization_charged_at) {
    // Authorization was charged (user didn't sync in 24h)
    const actualPenalty = await calculateActualPenalty(commitment);
    
    if (actualPenalty !== null) {
      // User synced later - handle refund/additional charge
      await handleLateSyncSettlement(commitment, actualPenalty);
    } else {
      // User never synced - keep authorization charge
      await finalizeAuthorizationCharge(commitment);
    }
  } else {
    // Authorization not charged (user synced within 24h)
    const actualPenalty = await calculateActualPenalty(commitment);
    await chargeActualPenalty(commitment, actualPenalty);
  }
}
```

---

#### 6.7 Frontend Updates

**File:** `Views/AuthorizationView.swift` (UPDATE)

**Add Clear Messaging:**
- "This amount will be held as authorization. If you don't sync within 24 hours after your week ends, this amount will be charged. If you sync, you'll only pay your actual penalty."
- Show grace period end date
- Show what happens if they sync vs don't sync

**File:** `Views/SettlementStatusView.swift` (NEW)

**Show Settlement Status:**
- Authorization amount
- Whether authorization was charged
- Actual penalty (if synced)
- Refund amount (if applicable)
- Status: "Pending", "Authorization Charged", "Settled", "Refunded"

**File:** Sync Flow (UPDATE)

**After sync completes:**
- Check if authorization was charged
- If yes, show: "We've calculated your actual penalty. You'll receive a refund of $X.XX"
- If no, show: "Your penalty has been calculated and charged."

---

#### 6.8 Scheduled Jobs (Cron)

**Email Notification Job:**
- Schedule: Every hour
- Function: `send_week_end_notifications`
- Logic: Find commitments where `week_end_date = TODAY` and send emails

**Authorization Charge Job:**
- Schedule: Every hour
- Function: `charge_authorization_after_grace_period`
- Logic: Find commitments where `grace_period_ends_at < NOW()` and `authorization_charged_at IS NULL`, then charge

**Weekly-Close Job:**
- Schedule: Every Monday at 12:00 EST (existing)
- Function: `weekly-close`
- Updates: Now handles authorization vs actual penalty logic

---

#### 6.9 Key Design Decisions

**1. Authorization Hold vs Immediate Charge**
- ✅ **Use Authorization Hold** (`capture_method: 'manual'`)
- Hold funds, capture after 24h if no sync
- No refund needed if user doesn't sync

**2. User Syncs During Grace Period**
- ✅ **Cancel authorization, charge actual penalty immediately**
- If user syncs within 24h, cancel authorization hold and charge actual penalty

**3. Partial Week Sync**
- ✅ **Settle synced days, wait for rest**
- Charge for synced days, wait for missing days

**4. Multiple Weeks Pending**
- ✅ **Settle all when user syncs (batch)**
- When user syncs, settle all pending weeks at once

**5. Email Timing**
- ✅ **Send at `week_end_date + 1 hour`**
- Give system time to process, then send notification

---

#### 6.10 Testing Scenarios

**Scenario 1: User Syncs Within 24h (Happy Path)**
1. User creates commitment → Authorization hold created
2. Week ends → Email sent
3. User opens app within 24h → Syncs data
4. Authorization hold cancelled → Actual penalty charged
5. ✅ User pays actual penalty only

**Scenario 2: User Doesn't Sync (Authorization Charged)**
1. User creates commitment → Authorization hold created
2. Week ends → Email sent
3. User doesn't open app → 24h passes
4. Authorization hold captured → User charged authorization amount
5. ✅ User pays authorization amount (worst-case)

**Scenario 3: User Syncs Late (Refund)**
1. Authorization charged after 24h
2. User opens app 3 days later → Syncs data
3. Actual penalty calculated → Refund issued (if actual < authorization)
4. ✅ User pays actual penalty, gets refund for difference

**Scenario 4: User Syncs Late (Additional Charge)**
1. Authorization charged after 24h
2. User opens app 3 days later → Syncs data
3. Actual penalty calculated → Additional charge (if actual > authorization)
4. ✅ User pays authorization + additional charge = actual penalty

---

#### 6.11 Edge Cases

**User Syncs Before Grace Period Ends:**
- Cancel authorization hold, charge actual penalty immediately
- Check in `rpc_sync_daily_usage` if `grace_period_ends_at > NOW()`

**User Never Syncs:**
- Authorization charge stays (no refund)
- By design - user had 24h warning

**Authorization Hold Expires:**
- Create new PaymentIntent and charge immediately
- Handle in `charge_authorization_after_grace_period`

**User Changes Payment Method:**
- Create new authorization hold with new payment method
- Handle in payment method update flow

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
Commitment Created → Authorization Hold Created → 
Week Ends → Email Notification Sent →
  If user syncs within 24h: Cancel authorization, charge actual penalty
  If user doesn't sync: Charge authorization after 24h →
    If user syncs later: Calculate actual penalty, refund difference (or charge additional)
```

---

## Files to Create

1. `Utilities/UsageSyncManager.swift` - Sync manager for main app ✅ DONE
2. `Models/DailyUsageEntry.swift` - Data model for daily usage entries ✅ DONE
3. `supabase/migrations/rpc_sync_daily_usage.sql` - Backend RPC function ✅ DONE
4. `supabase/functions/sync-usage/index.ts` - Edge function (optional)
5. `supabase/migrations/add_authorization_fields.sql` - Database schema for authorization fields
6. `supabase/functions/charge-authorization-after-grace-period/index.ts` - Charge authorization after 24h
7. `supabase/functions/send-week-end-notification/index.ts` - Email notification at week end
8. `Views/SettlementStatusView.swift` - Show settlement status to users

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

