# Authorization-Based Settlement Implementation Plan

## Overview

**Hybrid Approach:** Authorization charge at commitment start + 24-hour grace period + email notification + retroactive settlement with refunds.

---

## Current State Analysis

### What Exists Today

1. **Authorization Amount Calculation** (`AppModel.calculateAuthorizationAmount()`)
   - Calculates worst-case penalty amount upfront
   - Shown to user in `AuthorizationView`
   - Stored in `AppModel.authorizationAmount`

2. **Commitment Creation** (`BackendClient.createCommitment()`)
   - Returns `maxChargeCents` (authorization amount)
   - Currently stored but **NOT charged** (just calculated)

3. **Weekly-Close Function** (`weekly-close/index.ts`)
   - Runs every Monday
   - Calculates penalties from `daily_usage`
   - Charges users via Stripe

4. **Sync Function** (`rpc_sync_daily_usage`)
   - Syncs daily usage entries
   - Updates `daily_usage` table
   - Recalculates weekly totals

### What's Missing

1. **Authorization Charge** - Not actually charging/holding the authorization amount
2. **24-Hour Grace Period Logic** - No tracking of grace period
3. **Email Notification** - No email system at end date
4. **Late Sync Handling** - No refund logic for late syncs
5. **Settlement Status Tracking** - No way to track if authorization was charged vs actual penalty

---

## Required Implementation Components

### 1. Database Schema Changes

#### 1.1 Add Fields to `commitments` Table

```sql
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS authorization_amount_cents INTEGER;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS authorization_charged_at TIMESTAMP;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS authorization_payment_intent_id TEXT;
ALTER TABLE commitments ADD COLUMN IF NOT EXISTS grace_period_ends_at TIMESTAMP;
```

**Purpose:**
- `authorization_amount_cents`: The worst-case amount calculated upfront
- `authorization_charged_at`: When authorization was actually charged (after 24h)
- `authorization_payment_intent_id`: Stripe PaymentIntent ID for the authorization charge
- `grace_period_ends_at`: End date + 24 hours (when authorization can be charged)

#### 1.2 Add Fields to `user_week_penalties` Table

```sql
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS authorization_amount_cents INTEGER;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS actual_penalty_cents INTEGER;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS refund_amount_cents INTEGER;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS refund_payment_intent_id TEXT;
ALTER TABLE user_week_penalties ADD COLUMN IF NOT EXISTS settlement_status TEXT; -- 'pending', 'authorization_charged', 'settled', 'refunded'
```

**Purpose:**
- Track authorization vs actual penalty
- Track refunds
- Track settlement status

#### 1.3 Add Fields to `payments` Table (if needed)

```sql
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_type TEXT; -- 'authorization', 'penalty', 'refund'
ALTER TABLE payments ADD COLUMN IF NOT EXISTS related_payment_intent_id TEXT; -- For refunds, link to original charge
```

**Purpose:**
- Distinguish authorization charges from penalty charges
- Link refunds to original charges

---

### 2. Backend API Changes

#### 2.1 Update `createCommitment` RPC Function

**Current:** Returns `maxChargeCents` (calculated but not charged)

**New:** 
- Calculate authorization amount (worst-case)
- **Create Stripe PaymentIntent** with `capture_method: 'manual'` (authorization hold)
- Store `authorization_payment_intent_id` in commitment
- Calculate `grace_period_ends_at` = `week_end_date + 24 hours`
- Return authorization amount and PaymentIntent ID

**Stripe Flow:**
```typescript
// Create authorization hold (not captured yet)
const paymentIntent = await stripe.paymentIntents.create({
  amount: authorizationAmountCents,
  currency: 'usd',
  customer: stripeCustomerId,
  capture_method: 'manual',  // Authorization hold
  description: `Authorization for commitment week ending ${weekEndDate}`,
  metadata: {
    commitment_id: commitmentId,
    type: 'authorization',
    week_end_date: weekEndDate
  }
});
```

#### 2.2 Update `rpc_sync_daily_usage` Function

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
  
  // Create refund via Stripe
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
  
  // Store refund info
  await updateUserWeekPenalties({
    actual_penalty_cents: actualPenalty,
    refund_amount_cents: refundAmount,
    refund_payment_intent_id: refund.id,
    settlement_status: 'refunded'
  });
}
```

#### 2.3 Create New Function: `charge_authorization_after_grace_period`

**Purpose:** Charge authorization amount if user hasn't synced within 24 hours

**Trigger:** Scheduled job (cron) that runs every hour checking for expired grace periods

**Logic:**
```typescript
// Find commitments where:
// - grace_period_ends_at < NOW()
// - authorization_charged_at IS NULL (not charged yet)
// - No daily_usage entries exist for this week

const expiredCommitments = await findExpiredGracePeriods();

for (const commitment of expiredCommitments) {
  // Check if user synced (has daily_usage)
  const hasSynced = await checkIfSynced(commitment);
  
  if (!hasSynced) {
    // Charge the authorization
    const paymentIntent = await stripe.paymentIntents.capture(
      commitment.authorization_payment_intent_id
    );
    
    // Update commitment
    await updateCommitment({
      authorization_charged_at: NOW(),
      status: 'authorization_charged'
    });
    
    // Create user_week_penalties record
    await createUserWeekPenalties({
      user_id: commitment.user_id,
      week_start_date: commitment.week_end_date,
      authorization_amount_cents: commitment.authorization_amount_cents,
      actual_penalty_cents: null,  // Not synced yet
      settlement_status: 'authorization_charged'
    });
  }
}
```

---

### 3. Email Notification System

#### 3.1 Create Email Template

**Subject:** "Your PayAttentionClub week ended - Check your results!"

**Content:**
```
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

#### 3.2 Create Email Function: `send_week_end_notification`

**Trigger:** Scheduled job that runs at `week_end_date` (or shortly after)

**Logic:**
```typescript
// Find commitments where week_end_date = TODAY
const endedCommitments = await findEndedCommitments();

for (const commitment of endedCommitments) {
  // Check if user has synced
  const hasSynced = await checkIfSynced(commitment);
  
  if (!hasSynced) {
    // Send email notification
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

#### 3.3 Email Service Integration

**Options:**
- **Supabase Edge Function** + SendGrid/Resend/SES
- **Supabase Database Function** + pg_net extension
- **Third-party service** (Postmark, Mailgun, etc.)

**Recommendation:** Supabase Edge Function + Resend (simple, good free tier)

---

### 4. Weekly-Close Function Updates

#### 4.1 Handle Authorization vs Actual Penalty

**New Logic:**
```typescript
// For each commitment in the week:
const commitment = await getCommitment(commitmentId);

// Check if authorization was charged
if (commitment.authorization_charged_at) {
  // Authorization was charged (user didn't sync in 24h)
  // Check if user synced later
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
  // Calculate actual penalty and charge normally
  const actualPenalty = await calculateActualPenalty(commitment);
  await chargeActualPenalty(commitment, actualPenalty);
}
```

#### 4.2 Remove Option B Code

**Action:** Remove the "no sync = worst case" code we added earlier (lines 101-167 in `weekly-close/index.ts`)

**Reason:** We're using authorization instead

---

### 5. Frontend Changes

#### 5.1 Update AuthorizationView

**Current:** Shows authorization amount, but doesn't explain it's a hold

**New:** 
- Clear messaging: "This amount will be held as authorization. If you don't sync within 24 hours after your week ends, this amount will be charged. If you sync, you'll only pay your actual penalty."
- Show grace period end date
- Show what happens if they sync vs don't sync

#### 5.2 Add Settlement Status View

**New View:** Show user their settlement status
- Authorization amount
- Whether authorization was charged
- Actual penalty (if synced)
- Refund amount (if applicable)
- Status: "Pending", "Authorization Charged", "Settled", "Refunded"

#### 5.3 Update Sync Flow

**After sync completes:**
- Check if authorization was charged
- If yes, show: "We've calculated your actual penalty. You'll receive a refund of $X.XX"
- If no, show: "Your penalty has been calculated and charged."

---

### 6. Scheduled Jobs (Cron)

#### 6.1 Email Notification Job

**Schedule:** Every hour (or more frequent)
**Function:** `send_week_end_notifications`
**Logic:** Find commitments where `week_end_date = TODAY` and send emails

#### 6.2 Authorization Charge Job

**Schedule:** Every hour
**Function:** `charge_authorization_after_grace_period`
**Logic:** Find commitments where `grace_period_ends_at < NOW()` and `authorization_charged_at IS NULL`, then charge

#### 6.3 Weekly-Close Job (Existing)

**Schedule:** Every Monday at 12:00 EST
**Function:** `weekly-close`
**Updates:** Now handles authorization vs actual penalty logic

---

## Implementation Order

### Phase 1: Database Schema
1. ✅ Add fields to `commitments` table
2. ✅ Add fields to `user_week_penalties` table
3. ✅ Add fields to `payments` table (if needed)
4. ✅ Create migration script

### Phase 2: Authorization Charge
1. ✅ Update `createCommitment` to create Stripe authorization hold
2. ✅ Store authorization PaymentIntent ID
3. ✅ Calculate and store `grace_period_ends_at`
4. ✅ Test authorization hold creation

### Phase 3: Grace Period Logic
1. ✅ Create `charge_authorization_after_grace_period` function
2. ✅ Create scheduled job to run it hourly
3. ✅ Test charging authorization after 24h
4. ✅ Test that synced users don't get charged

### Phase 4: Email Notifications
1. ✅ Set up email service (Resend/SendGrid)
2. ✅ Create email template
3. ✅ Create `send_week_end_notification` function
4. ✅ Create scheduled job to send emails
5. ✅ Test email delivery

### Phase 5: Late Sync Handling
1. ✅ Update `rpc_sync_daily_usage` to check authorization status
2. ✅ Implement refund logic (if actual < authorization)
3. ✅ Implement additional charge logic (if actual > authorization)
4. ✅ Test late sync scenarios

### Phase 6: Weekly-Close Updates
1. ✅ Remove Option B code (no sync = worst case)
2. ✅ Add authorization vs actual penalty logic
3. ✅ Handle refunds in weekly-close
4. ✅ Test weekly-close with authorization charges

### Phase 7: Frontend Updates
1. ✅ Update AuthorizationView messaging
2. ✅ Create SettlementStatusView
3. ✅ Update sync flow to show refund info
4. ✅ Test user experience

### Phase 8: Testing & Polish
1. ✅ Test full flow: authorization → sync → refund
2. ✅ Test full flow: authorization → no sync → charge
3. ✅ Test edge cases (partial sync, multiple weeks, etc.)
4. ✅ Update documentation
5. ✅ Deploy to production

---

## Key Design Decisions Needed

### 1. Authorization Hold vs Immediate Charge

**Question:** Should we use Stripe's authorization hold (`capture_method: 'manual'`) or immediately charge and refund later?

**Option A: Authorization Hold** (Recommended)
- Hold funds, capture after 24h if no sync
- No refund needed if user doesn't sync
- Simpler for users who don't sync

**Option B: Immediate Charge + Refund**
- Charge immediately, refund if user syncs
- More complex refund logic
- Better for users who sync (no hold)

**Recommendation:** Option A (Authorization Hold)

### 2. What If User Syncs During Grace Period?

**Question:** If user syncs within 24 hours, do we:
- A) Cancel authorization hold immediately
- B) Wait until grace period ends, then refund
- C) Never charge authorization, charge actual penalty instead

**Recommendation:** Option C - If user syncs during grace period, cancel authorization and charge actual penalty immediately

### 3. What If User Syncs Partial Week?

**Question:** If user syncs some days but not all:
- A) Wait for all days before settling
- B) Settle synced days, wait for rest
- C) Treat missing days as 0 usage

**Recommendation:** Option B - Settle synced days, wait for rest (same as Option A analysis)

### 4. Multiple Weeks Pending

**Question:** If user has multiple weeks with authorization charged:
- A) Settle all when they sync
- B) Settle oldest first
- C) User chooses

**Recommendation:** Option A - Settle all when they sync (batch)

### 5. Email Timing

**Question:** When should we send the email?
- A) Exactly at `week_end_date`
- B) `week_end_date + 1 hour` (give system time to process)
- C) `week_end_date + 12 hours` (morning after)

**Recommendation:** Option B - `week_end_date + 1 hour`

---

## Edge Cases to Handle

### 1. User Syncs Before Grace Period Ends
- **Scenario:** User syncs 12 hours after week ends
- **Action:** Cancel authorization hold, charge actual penalty immediately
- **Implementation:** Check in `rpc_sync_daily_usage` if `grace_period_ends_at > NOW()`

### 2. User Syncs After Authorization Charged
- **Scenario:** User syncs 48 hours after week ends (authorization already charged)
- **Action:** Calculate actual penalty, refund difference if needed
- **Implementation:** Already handled in Phase 5

### 3. User Never Syncs
- **Scenario:** User never opens app again
- **Action:** Authorization charge stays (no refund)
- **Implementation:** No action needed (by design)

### 4. Authorization Hold Expires
- **Scenario:** Stripe authorization hold expires before we capture it
- **Action:** Create new PaymentIntent and charge immediately
- **Implementation:** Handle in `charge_authorization_after_grace_period`

### 5. User Changes Payment Method
- **Scenario:** User updates payment method after authorization hold
- **Action:** Create new authorization hold with new payment method
- **Implementation:** Handle in payment method update flow

---

## Testing Scenarios

### Scenario 1: Happy Path (User Syncs Within 24h)
1. User creates commitment → Authorization hold created
2. User uses apps → Extension tracks usage
3. Week ends → Email sent
4. User opens app within 24h → Syncs data
5. Authorization hold cancelled → Actual penalty charged
6. ✅ User pays actual penalty only

### Scenario 2: User Doesn't Sync (Authorization Charged)
1. User creates commitment → Authorization hold created
2. User uses apps → Extension tracks usage
3. Week ends → Email sent
4. User doesn't open app → 24h passes
5. Authorization hold captured → User charged authorization amount
6. ✅ User pays authorization amount (worst-case)

### Scenario 3: User Syncs Late (Refund)
1. User creates commitment → Authorization hold created
2. User uses apps → Extension tracks usage
3. Week ends → Email sent
4. User doesn't open app → 24h passes → Authorization charged
5. User opens app 3 days later → Syncs data
6. Actual penalty calculated → Refund issued (if actual < authorization)
7. ✅ User pays actual penalty, gets refund for difference

### Scenario 4: User Syncs Late (Additional Charge)
1. User creates commitment → Authorization hold created
2. User uses apps → Extension tracks usage
3. Week ends → Email sent
4. User doesn't open app → 24h passes → Authorization charged
5. User opens app 3 days later → Syncs data
6. Actual penalty calculated → Additional charge (if actual > authorization)
7. ✅ User pays authorization + additional charge = actual penalty

---

## Summary

**What We Need to Build:**

1. ✅ **Database schema** - Track authorization amounts, charges, refunds
2. ✅ **Authorization hold** - Create Stripe authorization when commitment created
3. ✅ **Grace period logic** - Charge authorization after 24h if no sync
4. ✅ **Email notifications** - Send email at week end date
5. ✅ **Late sync handling** - Refund/additional charge when user syncs late
6. ✅ **Weekly-close updates** - Handle authorization vs actual penalty
7. ✅ **Frontend updates** - Show settlement status to users
8. ✅ **Scheduled jobs** - Email and authorization charge jobs

**Key Benefits:**
- ✅ Fair: Users who sync pay actual penalty
- ✅ Safe: Users who don't sync pay worst-case (but had 24h warning)
- ✅ Clear: Email notification gives users chance to sync
- ✅ Transparent: Users see authorization vs actual penalty

**Next Steps:**
1. Review this plan
2. Make design decisions on open questions
3. Start with Phase 1 (Database Schema)


