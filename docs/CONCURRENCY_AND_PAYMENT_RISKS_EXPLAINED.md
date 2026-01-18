# Concurrency and Payment Delay Risks - Detailed Explanation

**Date**: 2026-01-15  
**Purpose**: Explain why concurrency and payment delays are risks in normal mode

---

## 1. Concurrency Risk: Multiple Users Settling Simultaneously

### The Problem

When the settlement function runs, it processes **ALL commitments for a week in a single execution** (not commitment-by-commitment). If the function is triggered **twice simultaneously**, both executions could try to charge the same users.

**Note**: Manual trigger + cron is unlikely if you're the only operator. However, there are other realistic scenarios where this could happen (see below).

### Why It's a Problem

**Current Code Flow** (from `bright-service/index.ts`):

```typescript
// Step 1: Fetch all candidates for the week
const candidates = await buildSettlementCandidates(supabase, target.weekEndDate);

// Step 2: Loop through each candidate
for (const candidate of candidates) {
  // Step 3: Check if already settled
  if (shouldSkipBecauseSettled(candidate)) {
    summary.alreadySettled += 1;
    continue;  // Skip if already settled
  }
  
  // Step 4: Check grace period
  if (!isGracePeriodExpired(candidate)) {
    continue;  // Skip if grace not expired
  }
  
  // Step 5: Charge the user
  const paymentIntent = await chargeCandidate(...);
  
  // Step 6: Update database with settlement status
  await updateUserWeekPenalty(...);
}
```

### The Race Condition

**Scenario**: Settlement function runs twice at the same time (e.g., cron fires at 12:00:00 ET, manual trigger at 12:00:01 ET)

**Timeline**:

```
Time    Execution 1                    Execution 2
----    -----------                    -----------
12:00:00  Fetch candidates (100 users)
12:00:01                              Fetch candidates (100 users)
12:00:02  Check user A: not settled
12:00:03                              Check user A: not settled (still not settled!)
12:00:04  Charge user A: $50
12:00:05                              Charge user A: $50 (DUPLICATE!)
12:00:06  Update DB: status = "charged_actual"
12:00:07                              Update DB: status = "charged_actual" (overwrites)
```

**What Happens**:
1. Both executions fetch the same list of candidates
2. Both check `shouldSkipBecauseSettled()` at nearly the same time
3. Both see `settlement_status = "pending"` (not settled yet)
4. Both proceed to charge the user
5. Both create Stripe payment intents
6. User gets charged **twice**

### Why the Current Protection Isn't Enough

**Current Protection** (`shouldSkipBecauseSettled`):
```typescript
function shouldSkipBecauseSettled(candidate: SettlementCandidate): boolean {
  const status = candidate.penalty?.settlement_status;
  return status ? SETTLED_STATUSES.has(status) : false;
}
```

**Problem**: This is a **read-check-then-write** pattern, which is inherently race-condition prone:
1. Execution 1 reads: `status = "pending"` → proceeds
2. Execution 2 reads: `status = "pending"` → proceeds (Execution 1 hasn't updated yet)
3. Execution 1 writes: `status = "charged_actual"`
4. Execution 2 writes: `status = "charged_actual"` (overwrites, but charge already happened)

**The Gap**: There's a window between reading the status and updating it where another execution can slip through.

### Real-World Scenarios

**Scenario A: Function Timeout + Retry (MOST LIKELY)**
- Cron job runs at 12:00:00 ET
- Function starts processing 100 users
- Function times out at 12:00:60 ET (60 second limit) after processing 80 users
- **Question**: Does Supabase Edge Functions automatically retry on timeout?
  - If YES: Retry starts immediately → processes all 100 users again → first 80 get duplicate charges
  - If NO: Cron might retry on next schedule, or operator manually triggers → duplicate charges

**Scenario B: Function Error + Manual Retry**
- Cron job runs at 12:00:00 ET
- Function processes 50 users, then errors (network issue, Stripe API error)
- Function returns error status
- Operator sees error, manually triggers at 12:01:00 ET
- Both executions overlap → users 1-50 get duplicate charges

**Scenario C: Database Lock Contention (LESS LIKELY)**
- 100 users need settlement
- Function processes users sequentially
- If database is slow/locked, updates might fail
- Function might retry internally → duplicate charges

**Scenario D: Edge Function Platform Retries (UNKNOWN)**
- If Supabase Edge Functions automatically retry on 5xx errors
- Function returns 500 error (even if some charges succeeded)
- Platform retries → duplicate charges

**Key Question**: Does Supabase Edge Functions automatically retry on timeout/error? This determines if Scenario A is realistic.

### Impact

**Financial**: ⚠️ **MEDIUM** - Users could be charged twice (depends on retry behavior)
**User Experience**: ⚠️ **MEDIUM** - Users might see duplicate charges
**Support**: ⚠️ **MEDIUM** - Complaints about double charges
**Data Integrity**: ⚠️ **LOW** - Database shows correct final state, but Stripe might have duplicates

**Reality Check**: 
- Manual trigger + cron is unlikely (you're the only operator)
- Function timeout + retry is the main risk (depends on Supabase Edge Function retry behavior)
- **This risk is MEDIUM, not HIGH**, unless Supabase automatically retries on timeout

### Why Testing Mode Misses This

- Testing mode processes 1-2 users at a time
- No concurrent executions (manual triggers only)
- No database lock contention (small dataset)
- No function timeouts (completes in seconds)

---

## 2. Payment Delay Risk: Function Timeout Before Database Update

### The Problem

**You're right**: Payments with `off_session: true` and saved payment methods typically succeed. Stripe returns immediately with status "succeeded" or "failed".

**However**, there's still a risk if the function times out **after** the payment succeeds but **before** the database is fully updated.

### Issue 1: Function Timeout/Error Before Database Update

**Current Code Flow**:

```typescript
// Step 1: Create Stripe payment intent (synchronous, waits for response)
const paymentIntent = await stripe.paymentIntents.create({
  amount: amountCents,
  confirm: true,  // Immediately confirms the payment
  ...
});

// Step 2: Record payment in database
await recordPayment(supabase, {
  paymentIntentId: paymentIntent.id,
  ...
});

// Step 3: Update settlement status
await updateUserWeekPenalty(supabase, {
  settlement_status: "charged_actual",
  charge_payment_intent_id: paymentIntent.id,
  ...
});
```

**The Problem**: If the function **times out or errors** between Step 1 and Step 3, the payment is created in Stripe, but the database isn't updated.

**Timeline** (if function times out):

```
Time    Action
----    ------
12:00:00  Function starts processing 100 users
12:00:45  User 80: Payment succeeds, recorded in DB
12:00:46  User 80: Updating settlement status → TIMEOUT (function killed at 60s)
12:00:47  Function returns error (didn't complete)
12:00:48  Retry: Check user 80 status → Still "pending" (update didn't complete)
12:00:49  Retry: Create payment intent → SUCCESS ($50 charged AGAIN)
12:00:50  Retry: Update settlement status → SUCCESS
```

**Result**: User 80 charged twice.

**But you're right**: This is only a risk if:
1. Function processes many users (approaching 60s timeout)
2. Function times out mid-processing
3. Retry happens (manual or automatic)

**If payments succeed quickly** (typical case), function completes in < 10 seconds → no timeout risk.

### Why This Happens

**Edge Function Time Limits**:
- Default: 60 seconds
- If processing 100 users, each taking 0.5 seconds = 50 seconds
- If Stripe API is slow (network delay), could timeout
- If database is slow (lock contention), could timeout

**Network Issues**:
- Stripe API might be slow to respond
- Database connection might drop
- Function might be killed by platform

**Error Handling**:
- If `updateUserWeekPenalty` throws an error, payment is already created
- Function retries, sees status still "pending"
- Creates another payment intent

### Issue 2: Stripe Webhook Delay (Less Likely)

**How Stripe Webhooks Work**:
1. Payment intent is created → Stripe processes payment
2. Stripe sends webhook to your server (can be delayed)
3. Your webhook handler updates database

**The Problem**: The settlement function **doesn't wait for webhooks**. It creates the payment intent and immediately updates the database based on the payment intent response.

**Current Code**:
```typescript
const paymentIntent = await stripe.paymentIntents.create({
  confirm: true,  // Payment is confirmed immediately
  ...
});

// Payment intent status is available immediately:
// - "succeeded" = payment successful
// - "requires_action" = needs 3D Secure
// - "processing" = still processing
// - "failed" = payment failed

await updateUserWeekPenalty(supabase, {
  status: paymentIntent.status,  // Uses immediate status, not webhook
  ...
});
```

**So webhook delay isn't actually the issue** - the function uses the payment intent response, not webhooks.

**However**, if there's a webhook handler that also updates the database:
- Settlement function updates: `status = "charged_actual"`
- Webhook arrives later, also updates: `status = "charged_actual"`
- This is fine (idempotent), but could cause confusion if webhook handler has bugs

### The Real Risk: No Idempotency Key

**Current Code** (no idempotency):
```typescript
const paymentIntent = await stripe.paymentIntents.create({
  amount: amountCents,
  customer: candidate.user.stripe_customer_id,
  payment_method: paymentMethodId,
  confirm: true,
  // ❌ NO idempotency_key!
});
```

**What Stripe Idempotency Does**:
- If you create a payment intent with the same `idempotency_key` twice
- Stripe returns the **same payment intent** (doesn't create a new one)
- Prevents duplicate charges

**Without Idempotency**:
- Each call creates a new payment intent
- Even if the function retries with the same parameters
- Stripe creates a new charge

### Real-World Scenarios

**Scenario A: Function Timeout**
- Settlement processes 80 users successfully
- User 81: Creates payment intent → SUCCESS
- User 81: Database update → TIMEOUT (function killed at 60 seconds)
- Retry: Sees user 81 still "pending" → Creates another payment intent → DUPLICATE

**Scenario B: Network Error**
- Creates payment intent → SUCCESS
- Network drops before database update
- Function retries → Creates another payment intent → DUPLICATE

**Scenario C: Database Lock**
- Creates payment intent → SUCCESS
- Database is locked (other settlement running)
- Update fails → Function retries → Creates another payment intent → DUPLICATE

### Impact

**Financial**: ⚠️ **LOW to MEDIUM** - Users could be charged twice (only if function times out + retry)
**User Experience**: ⚠️ **LOW to MEDIUM** - Unexpected duplicate charges (rare)
**Support**: ⚠️ **LOW to MEDIUM** - Need to refund duplicate charges (rare)
**Data Integrity**: ⚠️ **LOW** - Database shows correct state after retry, but Stripe might have duplicates

**When Would 100+ Users Be Processed?**

Settlement runs **once per week** (Tuesday 12:00 ET) and processes **ALL users whose week ended on the previous Monday** in a single execution.

So if you have:
- **10 users** → Settlement processes 10 users (~1-2 seconds)
- **100 users** → Settlement processes 100 users (~10-15 seconds)
- **1000 users** → Settlement processes 1000 users (~100-150 seconds) → **TIMEOUT RISK**

**Reality Check**:
- **Payments rarely fail** with `off_session: true` and saved payment methods ✅
- **Function completes quickly** if payments succeed (typically < 10 seconds for 100 users) ✅
- **Main risk**: Function timeout if processing many users (1000+) AND payments are slow
- **Likelihood**: VERY LOW (only if you scale to 1000+ users AND function times out AND retry happens)
- **Current scale**: Probably < 100 users → **No timeout risk** ✅

### Why Testing Mode Misses This

- Testing mode processes 1-2 users (completes in seconds)
- No function timeouts (fast execution)
- No network issues (local testing)
- No database lock contention (small dataset)
- No retries (manual triggers only)

---

## Summary

### Concurrency Risk

**Root Cause**: Race condition in read-check-then-write pattern
- Multiple executions read "pending" status simultaneously
- Both proceed to charge
- Both update database (last write wins, but both charges happened)

**Reality**: 
- **Manual trigger + cron is unlikely** (you're the only operator)
- **Main risk**: Function timeout/error causing retry → overlap
- **Depends on**: Whether Supabase Edge Functions automatically retry on timeout/error
- **Recommendation**: Check Supabase documentation on retry behavior, or test timeout scenario

**Solution Needed** (if retries are automatic):
- Database-level locking (`SELECT FOR UPDATE`)
- Idempotency keys for settlement runs
- Atomic status updates (use database transactions)
- Check for existing payment intents before creating new ones

### Payment Delay Risk

**Root Cause**: Function timeout/error between payment creation and database update
- Payment created in Stripe
- Database update fails
- Retry creates another payment

**Solution Needed**:
- Add idempotency keys to Stripe payment intents
- Use database transactions (all-or-nothing)
- Better error handling (don't retry if payment already created)
- Check for existing payment intents before creating new ones

### Testing Recommendations

**Concurrency Testing**:
- Trigger settlement function twice simultaneously
- Verify only one charge per user
- Check database for duplicate entries

**Payment Delay Testing**:
- Simulate function timeout after payment creation
- Verify retry doesn't create duplicate payment
- Check Stripe for duplicate charges

