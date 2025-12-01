# Option A: Settlement Only When Synced - Deep Dive Analysis

## Core Principle

**Only settle weeks where we have synced usage data. Missing weeks remain "pending" until sync, then retroactively apply penalties when data arrives.**

---

## Key Questions to Answer

### 1. What Does "Pending" Mean?

**Question:** When a week has no sync data, what status should it have?

**Options:**
- **A1.1:** Mark commitment as `status: 'pending_settlement'` (new status)
- **A1.2:** Mark week in `user_week_penalties` as `status: 'pending'` (already exists)
- **A1.3:** Don't create any records, just skip settlement entirely
- **A1.4:** Create `user_week_penalties` with `total_penalty_cents: 0` and `status: 'pending'`

**Recommendation:** A1.2 or A1.4 - Use existing `pending` status, create record with 0 penalty

**Why:** 
- Keeps audit trail of which weeks were skipped
- Easy to query "pending weeks" later
- Clear status for retroactive processing

---

### 2. When Does Retroactive Settlement Happen?

**Question:** When user finally syncs data, when do we calculate/charge penalties?

**Options:**
- **A2.1:** Immediately when sync happens (in `rpc_sync_daily_usage`)
- **A2.2:** Next time `weekly-close` runs (checks for pending weeks)
- **A2.3:** Separate "retroactive-settle" function that runs periodically
- **A2.4:** Manual trigger (admin function)

**Recommendation:** A2.1 - Immediate settlement on sync

**Why:**
- User opens app → syncs → immediately sees penalty
- No delay, clear cause-and-effect
- Simpler than scheduling retroactive jobs

**Implementation:**
- After `rpc_sync_daily_usage` completes successfully
- Check if this week was previously "pending"
- If yes, recalculate penalties and charge immediately

---

### 3. What About Partial Weeks?

**Question:** What if user syncs some days but not all?

**Example:**
- Week: Mon-Sun
- User syncs: Mon, Tue, Wed (3 days)
- Missing: Thu, Fri, Sat, Sun (4 days)

**Options:**
- **A3.1:** Settle only synced days, mark week as "partial"
- **A3.2:** Wait until all 7 days synced before settling
- **A3.3:** Settle synced days immediately, add missing days when they sync
- **A3.4:** Treat missing days as 0 usage (benefit of the doubt)

**Recommendation:** A3.3 - Settle synced days immediately, add missing days later

**Why:**
- Fair: Only charge for what we know
- Progressive: Penalties accumulate as more data arrives
- Clear: User sees penalty grow as they sync more days

**Implementation:**
- Calculate penalty for synced days only
- Mark week as `status: 'partial'` or `status: 'pending'`
- When more days sync, recalculate total penalty
- Update `user_week_penalties.total_penalty_cents`

---

### 4. How Do We Track "Pending" Weeks?

**Question:** How do we know which weeks are pending vs settled?

**Options:**
- **A4.1:** `user_week_penalties.status = 'pending'` with `total_penalty_cents = 0`
- **A4.2:** Separate table `pending_settlements(user_id, week_start_date)`
- **A4.3:** Check if `daily_usage` exists for all days of week
- **A4.4:** `commitments.status = 'pending_settlement'` (commitment-level)

**Recommendation:** A4.1 - Use existing `user_week_penalties` table

**Why:**
- Already exists, designed for this
- Can query: `WHERE status = 'pending' AND total_penalty_cents = 0`
- Easy to update when settlement happens

**Implementation:**
- In `weekly-close`: If no `daily_usage` for week → create `user_week_penalties` with `total_penalty_cents: 0, status: 'pending'`
- In `rpc_sync_daily_usage`: After sync, check if week was pending, recalculate

---

### 5. What About Multiple Weeks Pending?

**Question:** What if user doesn't open app for 3 weeks?

**Example:**
- Week 1 (Nov 4-10): No sync → pending
- Week 2 (Nov 11-17): No sync → pending  
- Week 3 (Nov 18-24): No sync → pending
- User opens app on Nov 25 → syncs all 3 weeks

**Options:**
- **A5.1:** Settle all pending weeks immediately (batch)
- **A5.2:** Settle oldest week first, then next, etc. (sequential)
- **A5.3:** Settle only most recent week, keep others pending
- **A5.4:** User chooses which weeks to settle

**Recommendation:** A5.1 - Settle all pending weeks in batch

**Why:**
- Fair: User gets charged for all weeks they used
- Simple: One transaction, all penalties calculated
- Clear: User sees total impact of not syncing

**Implementation:**
- In `rpc_sync_daily_usage`: After syncing entries, find all pending weeks for user
- Recalculate penalties for each pending week
- Charge all at once (or sequentially if Stripe limits)

---

### 6. What About Weekly Pool Distribution?

**Question:** If a week is pending, what happens to the weekly pool?

**Example:**
- Week 1: 10 users, 9 synced, 1 pending
- Pool = sum of 9 users' penalties
- User 1 syncs later → their penalty is calculated
- Does pool get updated?

**Options:**
- **A6.1:** Pool is frozen at deadline, late penalties go to next week's pool
- **A6.2:** Pool is updated when late penalties arrive (reopen pool)
- **A6.3:** Late penalties go to a separate "late penalties" pool
- **A6.4:** Pool stays open until all users synced (no deadline)

**Recommendation:** A6.2 - Update pool when late penalties arrive

**Why:**
- Fair: All penalties from same week go to same pool
- Accurate: Pool reflects actual total for that week
- Simple: Just update `weekly_pools.total_penalty_cents`

**Implementation:**
- When retroactive settlement happens, update `weekly_pools` for that week
- Recalculate `total_penalty_cents` = sum of all `user_week_penalties` for that week
- Pool status can stay `closed` (we're just updating the total)

---

### 7. What About Stripe Charges?

**Question:** When do we charge users for retroactive penalties?

**Options:**
- **A7.1:** Charge immediately when sync happens (in `rpc_sync_daily_usage`)
- **A7.2:** Charge on next `weekly-close` run (batch all pending)
- **A7.3:** Charge when user manually triggers settlement
- **A7.4:** Don't charge retroactively, only charge future weeks

**Recommendation:** A7.1 - Charge immediately on sync

**Why:**
- Clear cause-and-effect: User opens app → syncs → charged
- No delay, user knows what happened
- Simpler than scheduling charges

**Implementation:**
- In `rpc_sync_daily_usage`: After syncing entries
- Check for pending weeks
- Calculate penalties
- Create Stripe PaymentIntent immediately
- Update `user_week_penalties.status = 'paid'` or `'charge_initiated'`

---

### 8. What About Commitment Status?

**Question:** If a week is pending, does commitment status change?

**Example:**
- Commitment: Week 1 (Nov 4-10), status: `active`
- Weekly-close runs: No sync → week pending
- Commitment deadline passed: Should status change?

**Options:**
- **A8.1:** Keep `status: 'active'` until all weeks settled
- **A8.2:** Change to `status: 'pending_settlement'` when week pending
- **A8.3:** Change to `status: 'completed'` at deadline, but mark week as pending
- **A8.4:** Don't change commitment status, only week status

**Recommendation:** A8.4 - Don't change commitment status

**Why:**
- Commitment status = overall commitment state
- Week status = individual week settlement state
- Separation of concerns

**Implementation:**
- Commitment stays `active` or `completed` based on deadline
- Week settlement tracked in `user_week_penalties.status`

---

### 9. What About Notifications?

**Question:** Should we notify users about pending weeks?

**Options:**
- **A9.1:** Push notification when week becomes pending
- **A9.2:** In-app notification when user opens app
- **A9.3:** Email notification
- **A9.4:** No notification, user discovers when they sync

**Recommendation:** A9.2 - In-app notification when user opens app

**Why:**
- Non-intrusive
- User is already engaging with app
- Can show: "You have 2 pending weeks to sync"

**Implementation:**
- Query `user_week_penalties` where `status = 'pending'`
- Show banner/alert in app: "You have X pending weeks"
- Link to sync or view details

---

### 10. What About Edge Cases?

#### 10.1 User Deletes App, Reinstalls Later
- **Scenario:** User deletes app, loses local data, reinstalls 2 weeks later
- **Question:** Can they sync old weeks?
- **Answer:** No - extension data is lost. Week stays pending forever (or we need backup strategy)

#### 10.2 User Changes Device
- **Scenario:** User gets new iPhone, old device had unsynced data
- **Question:** Can they sync from old device?
- **Answer:** No - unless we implement cross-device sync (complex)

#### 10.3 User Never Syncs
- **Scenario:** User never opens app again
- **Question:** What happens to pending weeks?
- **Answer:** Stay pending forever, never charged (by design of Option A)

#### 10.4 User Syncs After Commitment Expired
- **Scenario:** Commitment ended Nov 10, user syncs on Nov 25
- **Question:** Can they still sync Nov 4-10 week?
- **Answer:** Yes - retroactive settlement allows this

---

## Proposed Implementation Flow

### Weekly-Close Function (Monday 12:00 EST)

```typescript
// 1. Determine week being closed (deadline that just passed)
const deadlineStr = calculateDeadline();

// 2. Handle revoked monitoring (existing logic)
// ... insert estimated usage for revoked commitments ...

// 3. For each active commitment:
for (const commitment of activeCommitments) {
  // 3a. Check if daily_usage exists for this week
  const usageData = await getDailyUsageForWeek(commitment, deadlineStr);
  
  if (usageData.length === 0) {
    // NO SYNC DATA - Mark as pending
    await supabase.from("user_week_penalties").upsert({
      user_id: commitment.user_id,
      week_start_date: deadlineStr,
      total_penalty_cents: 0,  // Zero because no data
      status: 'pending',        // Pending settlement
      last_updated: new Date().toISOString()
    });
    
    // Also update weekly_pools (with 0 penalty for now)
    await updateWeeklyPool(deadlineStr);
    
    console.log(`Week ${deadlineStr} marked as pending for user ${commitment.user_id}`);
  } else {
    // HAS SYNC DATA - Normal settlement
    const totalPenalty = calculatePenalty(usageData);
    
    await supabase.from("user_week_penalties").upsert({
      user_id: commitment.user_id,
      week_start_date: deadlineStr,
      total_penalty_cents: totalPenalty,
      status: 'pending',  // Will be charged in next step
      last_updated: new Date().toISOString()
    });
    
    // Charge user (existing logic)
    await chargeUser(commitment.user_id, totalPenalty);
  }
}

// 4. Close weekly pool (existing logic)
await closeWeeklyPool(deadlineStr);
```

### Sync Function (`rpc_sync_daily_usage`)

```typescript
// 1. Sync daily usage entries (existing logic)
const result = await syncEntries(entries);

// 2. After successful sync, check for pending weeks
for (const syncedDate of result.synced_dates) {
  const weekDeadline = getWeekDeadline(syncedDate);
  
  // Check if this week was pending
  const { data: pendingWeek } = await supabase
    .from("user_week_penalties")
    .select("*")
    .eq("user_id", userId)
    .eq("week_start_date", weekDeadline)
    .eq("status", "pending")
    .single();
  
  if (pendingWeek && pendingWeek.total_penalty_cents === 0) {
    // This week was pending, now we have data - recalculate!
    const usageData = await getDailyUsageForWeek(commitment, weekDeadline);
    const totalPenalty = calculatePenalty(usageData);
    
    // Update penalty
    await supabase.from("user_week_penalties").update({
      total_penalty_cents: totalPenalty,
      status: totalPenalty > 0 ? 'pending' : 'paid',  // Will charge if > 0
      last_updated: new Date().toISOString()
    });
    
    // Update weekly pool
    await updateWeeklyPool(weekDeadline);
    
    // Charge user if penalty > 0
    if (totalPenalty > 0) {
      await chargeUser(userId, totalPenalty);
    }
    
    console.log(`Retroactively settled week ${weekDeadline} for user ${userId}`);
  }
}
```

---

## Open Questions for Discussion

1. **Should we limit how far back users can sync?**
   - Example: Only allow syncing weeks from last 30 days?
   - Or: Allow syncing any week, no limit?

2. **What if user syncs partial week, then never syncs rest?**
   - Example: Syncs Mon-Wed, never syncs Thu-Sun
   - Do we charge for Mon-Wed only? Or wait forever?

3. **Should we show pending weeks in UI?**
   - Example: "You have 2 pending weeks (Nov 4-10, Nov 11-17)"
   - Or: Hide until user syncs?

4. **What about users who legitimately can't sync?**
   - Example: Traveling, no internet for 2 weeks
   - Should we have exceptions? Or strict rule?

5. **Should we notify users about pending weeks?**
   - Push notification? Email? In-app only?

6. **What happens to weekly pool if users never sync?**
   - Pool stays smaller (missing their penalties)
   - Is that okay? Or should we estimate?

---

## Summary: Option A Design Decisions Needed

1. ✅ **Pending tracking:** Use `user_week_penalties.status = 'pending'` with `total_penalty_cents = 0`
2. ✅ **Retroactive timing:** Immediate when sync happens
3. ✅ **Partial weeks:** Settle synced days, add missing days later
4. ✅ **Multiple pending:** Settle all in batch
5. ✅ **Pool updates:** Update pool when late penalties arrive
6. ✅ **Stripe charges:** Charge immediately on sync
7. ✅ **Commitment status:** Don't change, only week status
8. ⚠️ **Notifications:** Need to decide (in-app? push? email?)
9. ⚠️ **Sync limits:** Need to decide (time limit? or unlimited?)
10. ⚠️ **Partial week handling:** Need to decide (charge partial? or wait?)

---

## Next Steps

1. **Review this analysis** - Does this match your vision?
2. **Answer open questions** - Make decisions on unclear points
3. **Design UI/UX** - How do we show pending weeks to users?
4. **Implement** - Once decisions are made, implement Option A


