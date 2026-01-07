# Settlement Testing Script - Compressed Timeline

**Purpose**: Test all settlement cases using compressed timeline (3 min week, 1 min grace)  
**Duration**: ~15-20 minutes for complete test suite  
**Prerequisites**: Testing mode implementation complete

---

## Pre-Test Setup

### Step 1: Enable Testing Mode

**Location**: Supabase Dashboard → Project Settings → Edge Functions → Environment Variables

```bash
# Set environment variable
TESTING_MODE=true
```

**Verify**:
- Check that `TESTING_MODE` is set in staging environment
- ✅ **Cron will automatically skip** - Settlement function checks `TESTING_MODE` and skips if enabled (unless manually triggered)
- No need to disable cron manually - it's handled automatically

---

### Step 2: Clear Test Data

**Method**: Use existing test data clearing script

```bash
# Navigate to project root
cd /Users/jefcavens/Dropbox/Cursor-projects/payattentionclub-app-1.1

# Run test data clearing script
./scripts/clear_test_data.sh
```

**Or manually via Supabase SQL Editor**:

```sql
-- Delete test user and all associated data
-- (This should be done via the reset_my_user.ts script)
-- Check: supabase/tests/reset_my_user.ts
```

**Verify Clean State**:
```sql
-- Check no commitments exist
SELECT COUNT(*) FROM public.commitments WHERE user_id = '<your-test-user-id>';

-- Check no daily_usage exists
SELECT COUNT(*) FROM public.daily_usage WHERE user_id = '<your-test-user-id>';

-- Check no user_week_penalties exists
SELECT COUNT(*) FROM public.user_week_penalties WHERE user_id = '<your-test-user-id>';
```

**Expected**: All counts should be 0

---

### Step 3: Prepare Verification Tools

**Create Verification Script**: `supabase/tests/verify_test_results.ts`

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

async function verifyTestResults(userId: string) {
  // Get comprehensive test results
  const { data: commitment } = await supabase
    .from("commitments")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  const { data: penalty } = await supabase
    .from("user_week_penalties")
    .select("*")
    .eq("user_id", userId)
    .order("week_start_date", { ascending: false })
    .limit(1)
    .single();

  const { data: payments } = await supabase
    .from("payments")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });

  const { data: usage } = await supabase
    .from("daily_usage")
    .select("date, used_minutes, penalty_cents")
    .eq("user_id", userId)
    .order("date", { ascending: false });

  console.log("\n📊 TEST RESULTS VERIFICATION");
  console.log("============================\n");
  
  if (commitment) {
    console.log("✅ Commitment:", {
      id: commitment.id,
      deadline: commitment.week_end_date,
      grace_expires: commitment.week_grace_expires_at,
      max_charge: commitment.max_charge_cents,
      status: commitment.status
    });
  }

  if (penalty) {
    console.log("\n✅ Penalty Record:", {
      status: penalty.settlement_status,
      charged: penalty.charged_amount_cents,
      actual: penalty.actual_amount_cents,
      needs_reconciliation: penalty.needs_reconciliation,
      delta: penalty.reconciliation_delta_cents
    });
  }

  console.log(`\n✅ Payments: ${payments?.length || 0}`);
  payments?.forEach((p, i) => {
    console.log(`  ${i + 1}. ${p.type}: ${p.amount_cents} cents (${p.status})`);
  });

  console.log(`\n✅ Usage Entries: ${usage?.length || 0}`);
  console.log("\n============================\n");
}

const userId = Deno.args[0];
if (!userId) {
  console.error("Usage: deno run verify_test_results.ts <user-id>");
  Deno.exit(1);
}

await verifyTestResults(userId);
```

**Save this script for quick verification after each test case**

---

### Step 4: Prepare Manual Settlement Trigger

**Option A: Supabase CLI**

```bash
# Function invocation command (save for later use)
supabase functions invoke bright-service \
  --method POST \
  --body '{"targetWeek": null, "now": null}'
```

**Option B: Create Test Scripts**

**Create Manual Trigger Script**: `supabase/tests/manual_settlement_trigger.ts`

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Trigger settlement with optional timing control
async function triggerSettlement(options?: { targetWeek?: string; now?: string }) {
  const response = await supabase.functions.invoke("bright-service", {
    body: options || {}
  });
  
  if (response.error) {
    console.error("❌ Settlement trigger failed:", response.error);
    return;
  }
  
  console.log("✅ Settlement triggered:", response.data);
  return response.data;
}

// Usage with manual trigger header (required in testing mode)
const now = new Date().toISOString();
await triggerSettlement({ now });
```

**Note**: In testing mode, settlement function checks for `x-manual-trigger: true` header to distinguish manual triggers from cron. Update the function invocation to include this header.

**Save trigger command for later steps**

---

### Step 5: Create Verification Script File

**Action**: Create the verification script file

**File**: `supabase/tests/verify_test_results.ts`

Copy the verification script code from Step 3 above into this file.

**Make it executable**:
```bash
chmod +x supabase/tests/verify_test_results.ts
```

**Test it** (after creating a test user):
```bash
deno run --allow-net --allow-env supabase/tests/verify_test_results.ts <test-user-id>
```

---

## Test Case 1: User Syncs Before Grace Period Expires

**Scenario**: User syncs usage after deadline but before grace period expires → Charge actual penalty

**Timeline**:
- T+0:00 - Create commitment (deadline = T+3:00)
- T+0:30 - Sync usage (before grace expires at T+4:00)
- T+4:00 - Trigger settlement → Should charge actual

---

### Step 1: Create Commitment (T+0:00)

**Action**: Open iOS app and create commitment

1. **Open iOS app** (staging build)
2. **Navigate to SetupView**
3. **Select apps** to limit
4. **Set limit** (e.g., 60 minutes)
5. **Set penalty** (e.g., $0.10/minute = 10 cents/minute)
6. **Tap "Lock In"**
7. **Complete payment setup** (if needed)

**Verify in Database**:
```sql
-- Check commitment was created
SELECT 
  id,
  week_end_date,
  week_grace_expires_at,
  max_charge_cents,
  status,
  created_at
FROM public.commitments
WHERE user_id = '<your-test-user-id>'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `week_end_date`: Date ~3 minutes from now (compressed)
- `week_grace_expires_at`: Timestamp ~4 minutes from now (deadline + 1 min grace)
- `status`: 'pending' or 'active'
- `max_charge_cents`: Calculated authorization amount

**Verify in iOS App**:
- ✅ **Countdown should show ~3 minutes** - iOS app now uses `commitmentResponse.deadlineDate` from backend
- If countdown shows ~7 days, iOS app fix not yet implemented

**Record**:
- Commitment ID: `_________________`
- Deadline timestamp: `_________________`
- Grace expires timestamp: `_________________`

---

### Step 2: Wait 30 Seconds (T+0:30)

**Action**: Wait for 30 seconds to simulate time passing

**Purpose**: Allow some time to pass before syncing (simulates user opening app after deadline)

**Note**: In compressed mode, 30 seconds = significant portion of the 3-minute week

---

### Step 3: Sync Usage Data (T+0:30)

**Action**: Open iOS app and trigger usage sync

1. **Open iOS app** (if not already open)
2. **Navigate to MonitorView** (or any view that triggers sync)
3. **Wait for sync to complete** (check logs)

**Verify Sync in Database**:
```sql
-- Check daily_usage entries were created
SELECT 
  date,
  used_minutes,
  exceeded_minutes,
  penalty_cents,
  commitment_id
FROM public.daily_usage
WHERE user_id = '<your-test-user-id>'
ORDER BY date DESC;
```

**Expected**:
- At least one `daily_usage` row exists
- `commitment_id` matches the commitment from Step 1
- `penalty_cents` > 0 (if user exceeded limit)

**Check user_week_penalties**:
```sql
-- Check penalty was calculated
SELECT 
  week_start_date,
  total_penalty_cents,
  status
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Expected**:
- `total_penalty_cents` = sum of daily penalties
- `status` = NULL or 'pending' (not yet settled)

**Record**:
- Actual penalty amount: `_________________` cents
- Number of daily_usage entries: `_________________`

---

### Step 4: Wait for Grace Period to Expire (T+4:00)

**Action**: Wait until grace period expires

**Timeline Check**:
```sql
-- Check current time vs grace expiration
SELECT 
  week_end_date,
  week_grace_expires_at,
  NOW() as current_time,
  (week_grace_expires_at - NOW()) as time_until_expiry
FROM public.commitments
WHERE id = '<commitment-id-from-step-1>';
```

**Wait until**: `time_until_expiry` is negative (grace period expired)

**Or**: Wait 4 minutes total from commitment creation

---

### Step 5: Trigger Settlement (T+4:00)

**Action**: Manually trigger settlement function

**Using Supabase CLI**:
```bash
supabase functions invoke bright-service \
  --method POST \
  --body '{}'
```

**Or using test script**:
```bash
deno run --allow-net --allow-env supabase/tests/manual_settlement_trigger.ts
```

**Verify Settlement Results**:
```sql
-- Check settlement status
SELECT 
  week_start_date,
  total_penalty_cents,
  charged_amount_cents,
  actual_amount_cents,
  status,
  settlement_charged_at
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Expected**:
- `status` = 'charged_actual'
- `charged_amount_cents` = MIN(actual_penalty, max_charge_cents)
- `actual_amount_cents` = true actual penalty (may exceed authorization)
- `settlement_charged_at` = timestamp of settlement

**Check Payment Record**:
```sql
-- Check payment was created
SELECT 
  id,
  amount_cents,
  type,
  status,
  created_at
FROM public.payments
WHERE user_id = '<your-test-user-id>'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `type` = 'penalty_actual'
- `amount_cents` = charged_amount_cents from user_week_penalties
- `status` = 'succeeded' or 'pending'

**Record**:
- Settlement status: `_________________`
- Charged amount: `_________________` cents
- Actual amount: `_________________` cents

---

### Step 6: Quick Verification (Case 1)

**Action**: Run verification script to check all results at once

```bash
# Get your user ID first
# Then run verification
deno run --allow-net --allow-env supabase/tests/verify_test_results.ts <your-user-id>
```

**Or use SQL verification**:
```sql
-- Quick verification query
SELECT 
  'Commitment' as type,
  c.week_end_date as deadline,
  c.max_charge_cents as max_charge,
  c.status as commitment_status
FROM public.commitments c
WHERE c.user_id = '<your-user-id>'
ORDER BY c.created_at DESC
LIMIT 1

UNION ALL

SELECT 
  'Penalty' as type,
  uwp.week_start_date::text as deadline,
  uwp.charged_amount_cents as max_charge,
  uwp.settlement_status as commitment_status
FROM public.user_week_penalties uwp
WHERE uwp.user_id = '<your-user-id>'
ORDER BY uwp.week_start_date DESC
LIMIT 1;
```

**Expected Results for Case 1**:
- ✅ Commitment status: 'pending' or 'active'
- ✅ Penalty status: 'charged_actual'
- ✅ Charged amount = MIN(actual, authorization)
- ✅ Payment exists with type 'penalty_actual'
- ✅ Usage entries exist

---

## Test Case 2: User Does NOT Sync Before Grace Period Expires

**Scenario**: User does not sync usage before grace period expires → Charge worst case (authorization)

**Timeline**:
- T+0:00 - Create commitment (deadline = T+3:00)
- T+4:00 - Trigger settlement (no sync) → Should charge worst case

---

### Step 1: Clear Previous Test Data

**Action**: Clean up from Case 1

```bash
./scripts/clear_test_data.sh
```

**Or manually**:
```sql
-- Delete previous commitment and related data
DELETE FROM public.daily_usage WHERE user_id = '<your-test-user-id>';
DELETE FROM public.user_week_penalties WHERE user_id = '<your-test-user-id>';
DELETE FROM public.payments WHERE user_id = '<your-test-user-id>';
DELETE FROM public.commitments WHERE user_id = '<your-test-user-id>';
```

---

### Step 2: Create Commitment (T+0:00)

**Action**: Same as Case 1, Step 1

1. **Open iOS app**
2. **Create new commitment**
3. **Record commitment details**

**Verify**:
- Commitment created with compressed deadline (~3 minutes)
- No daily_usage entries exist yet

**Record**:
- Commitment ID: `_________________`
- Max charge (authorization): `_________________` cents

---

### Step 3: DO NOT Sync Usage

**Action**: Intentionally do NOT open the app or sync usage

**Purpose**: Simulate user not opening app before grace period expires

**Wait**: Until grace period expires (4 minutes from commitment creation)

---

### Step 4: Verify No Usage Data (T+3:30)

**Action**: Check database to confirm no sync occurred

```sql
-- Verify no usage data
SELECT COUNT(*) as usage_count
FROM public.daily_usage
WHERE user_id = '<your-test-user-id>';

-- Verify no penalties calculated
SELECT COUNT(*) as penalty_count
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>';
```

**Expected**: Both counts = 0

---

### Step 5: Trigger Settlement After Grace Expires (T+4:00)

**Action**: Wait for grace period to expire, then trigger settlement

**Timeline Check**:
```sql
-- Verify grace period expired
SELECT 
  week_grace_expires_at,
  NOW() as current_time,
  (NOW() - week_grace_expires_at) as time_since_expiry
FROM public.commitments
WHERE id = '<commitment-id-from-step-2>';
```

**Wait until**: `time_since_expiry` is positive (grace period expired)

**Trigger Settlement**:
```bash
supabase functions invoke bright-service --method POST --body '{}'
```

---

### Step 6: Verify Worst Case Charge (T+4:01)

**Action**: Check settlement results

```sql
-- Check settlement status
SELECT 
  week_start_date,
  total_penalty_cents,
  charged_amount_cents,
  actual_amount_cents,
  status,
  settlement_charged_at
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Expected**:
- `status` = 'charged_worst_case'
- `charged_amount_cents` = max_charge_cents (authorization amount)
- `actual_amount_cents` = 0 or NULL (unknown at charge time)
- `total_penalty_cents` = 0 (no usage data)

**Check Payment Record**:
```sql
SELECT 
  amount_cents,
  type,
  status
FROM public.payments
WHERE user_id = '<your-test-user-id>'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `type` = 'penalty_worst_case'
- `amount_cents` = max_charge_cents from commitment

**Record**:
- Settlement status: `_________________`
- Charged amount: `_________________` cents (should = authorization)
- Actual amount: `_________________` (should be 0 or NULL)

---

### Step 7: Quick Verification (Case 2)

**Action**: Run verification script

```bash
deno run --allow-net --allow-env supabase/tests/verify_test_results.ts <your-user-id>
```

**Expected Results for Case 2**:
- ✅ Commitment status: 'pending' or 'active'
- ✅ Penalty status: 'charged_worst_case'
- ✅ Charged amount = max_charge_cents (authorization)
- ✅ Actual amount = 0 or NULL (unknown)
- ✅ Payment exists with type 'penalty_worst_case'
- ✅ No usage entries (or entries synced after settlement)

---

## Test Case 3: Late Sync (After Settlement)

**Scenario**: User syncs usage AFTER settlement already ran → Reconciliation (refund only, never extra charge)

**Timeline**:
- T+0:00 - Create commitment
- T+4:00 - Settlement runs (no sync) → Charges worst case
- T+5:00 - User syncs usage → Reconciliation needed

---

### Step 1: Clear Previous Test Data

**Action**: Clean up from Case 2

```bash
./scripts/clear_test_data.sh
```

---

### Step 2: Create Commitment (T+0:00)

**Action**: Same as previous cases

1. **Open iOS app**
2. **Create new commitment**
3. **Record commitment details**

**Record**:
- Commitment ID: `_________________`
- Max charge: `_________________` cents

---

### Step 3: Trigger Settlement (No Sync) (T+4:00)

**Action**: Wait for grace period to expire, trigger settlement

**Same as Case 2, Steps 4-5**

**Verify**:
- Settlement charged worst case
- Status = 'charged_worst_case'
- Charged amount = max_charge_cents

**Record**:
- Initial charged amount: `_________________` cents

---

### Step 4: Sync Usage After Settlement (T+5:00)

**Action**: Now sync usage data (after settlement already ran)

1. **Open iOS app**
2. **Navigate to MonitorView** (triggers sync)
3. **Wait for sync to complete**

**Verify Sync**:
```sql
-- Check usage was synced
SELECT 
  date,
  used_minutes,
  exceeded_minutes,
  penalty_cents
FROM public.daily_usage
WHERE user_id = '<your-test-user-id>'
ORDER BY date DESC;
```

**Expected**: Daily usage entries now exist

---

### Step 5: Check Reconciliation Flag (T+5:01)

**Action**: Verify reconciliation was flagged

```sql
-- Check reconciliation status
SELECT 
  week_start_date,
  total_penalty_cents,
  charged_amount_cents,
  actual_amount_cents,
  needs_reconciliation,
  reconciliation_delta_cents,
  status
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Expected**:
- `needs_reconciliation` = true
- `reconciliation_delta_cents` = capped_actual - charged_amount
- `status` = 'charged_worst_case' (still, until reconciliation runs)

**Calculate Expected Delta**:
- Capped actual = MIN(actual_penalty, max_charge_cents)
- Delta = capped_actual - charged_amount
- If delta < 0: Refund needed (Case 3A)
- If delta = 0: No change (Case 3B)
- If delta > 0: This is impossible for late syncs (validation prevents this)

**Record**:
- Actual penalty: `_________________` cents
- Capped actual: `_________________` cents
- Reconciliation delta: `_________________` cents

---

### Step 6: Trigger Reconciliation (T+5:02)

**Action**: Manually trigger reconciliation function

**Using Supabase CLI**:
```bash
supabase functions invoke quick-handler \
  --method POST \
  --body '{"action": "settlement-reconcile"}'
```

**Or check if reconciliation runs automatically** (may be triggered by sync)

**Verify Reconciliation**:
```sql
-- Check final status after reconciliation
SELECT 
  week_start_date,
  total_penalty_cents,
  charged_amount_cents,
  actual_amount_cents,
  needs_reconciliation,
  reconciliation_delta_cents,
  status,
  refund_amount_cents
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Check Payment Records**:
```sql
-- Check all payments (initial + reconciliation)
SELECT 
  id,
  amount_cents,
  type,
  status,
  created_at
FROM public.payments
WHERE user_id = '<your-test-user-id>'
ORDER BY created_at DESC;
```

---

## Test Case 3A: Refund (Overcharged)

**Scenario**: User was charged worst case, but actual penalty is lower → Refund difference

**Setup**: Ensure actual penalty < authorization amount

---

### Step 1-5: Same as Case 3

**But ensure**: Actual penalty < charged amount (worst case)

**Example**:
- Authorization: 4200 cents ($42.00)
- Charged (worst case): 4200 cents
- Actual penalty: 3000 cents
- Capped actual: 3000 cents (under authorization)
- Delta: 3000 - 4200 = -1200 cents (refund needed)

---

### Step 6: Verify Refund

**Check Reconciliation**:
```sql
SELECT 
  status,
  charged_amount_cents,
  actual_amount_cents,
  refund_amount_cents,
  needs_reconciliation
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Expected**:
- `status` = 'refunded' or 'refunded_partial'
- `refund_amount_cents` = abs(delta) = 1200 cents
- `charged_amount_cents` = 3000 cents (reduced from 4200)
- `needs_reconciliation` = false

**Check Refund Payment**:
```sql
SELECT 
  amount_cents,
  type,
  status
FROM public.payments
WHERE user_id = '<your-test-user-id>'
  AND type = 'penalty_refund'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `type` = 'penalty_refund'
- `amount_cents` = 1200 cents
- `status` = 'succeeded' or 'pending'

**Record**:
- Final charged amount: `_________________` cents
- Refund amount: `_________________` cents

---

### Step 7: Quick Verification (Case 3A)

**Action**: Run verification script

```bash
deno run --allow-net --allow-env supabase/tests/verify_test_results.ts <your-user-id>
```

**Expected Results for Case 3A**:
- ✅ Penalty status: 'refunded' or 'refunded_partial'
- ✅ Charged amount reduced from initial worst case
- ✅ Refund amount = abs(delta)
- ✅ Payment exists with type 'penalty_refund'
- ✅ needs_reconciliation = false
- ✅ Two payments: initial worst case + refund

---

## Test Case 3B: No Change (Already at Cap)

**Scenario**: User was charged worst case, actual exceeds authorization, but capped actual = charged → No reconciliation

**Setup**: Ensure actual penalty > authorization, so capped = authorization

---

### Step 1-5: Same as Case 3A

**But ensure**: Actual penalty ≥ authorization amount (so capped = authorization)

**Example**:
- Authorization: 4200 cents ($42.00)
- Charged (worst case): 4200 cents
- Actual penalty: 5000 cents
- Capped actual: MIN(5000, 4200) = 4200 cents
- Delta: 4200 - 4200 = 0 cents (no change)

---

### Step 6: Verify No Reconciliation

**Check**:
```sql
SELECT 
  reconciliation_delta_cents,
  needs_reconciliation,
  status
FROM public.user_week_penalties
WHERE user_id = '<your-test-user-id>'
ORDER BY week_start_date DESC
LIMIT 1;
```

**Expected**:
- `reconciliation_delta_cents` = 0
- `needs_reconciliation` = false (or true but delta = 0)
- `status` = 'charged_worst_case' (unchanged)
- No refund, no extra charge

**Check Payments**:
```sql
SELECT COUNT(*) as payment_count
FROM public.payments
WHERE user_id = '<your-test-user-id>';
```

**Expected**: Only 1 payment (initial worst case charge, no refund/adjustment)

---

## Comprehensive Verification Summary

### Quick Verification Command

After each test case, run:

```bash
deno run --allow-net --allow-env supabase/tests/verify_test_results.ts <your-user-id>
```

### SQL Verification Query

**File**: `supabase/tests/verify_settlement_complete.sql`

```sql
-- Comprehensive settlement verification
WITH latest_commitment AS (
  SELECT * FROM public.commitments
  WHERE user_id = '<your-user-id>'
  ORDER BY created_at DESC
  LIMIT 1
),
latest_penalty AS (
  SELECT * FROM public.user_week_penalties
  WHERE user_id = '<your-user-id>'
  ORDER BY week_start_date DESC
  LIMIT 1
),
payment_summary AS (
  SELECT 
    type,
    COUNT(*) as count,
    SUM(amount_cents) as total_cents,
    array_agg(status) as statuses
  FROM public.payments
  WHERE user_id = '<your-user-id>'
  GROUP BY type
),
usage_summary AS (
  SELECT 
    COUNT(*) as entry_count,
    SUM(penalty_cents) as total_penalty_cents
  FROM public.daily_usage
  WHERE user_id = '<your-user-id>'
)
SELECT 
  json_build_object(
    'commitment', (SELECT row_to_json(lc.*) FROM latest_commitment lc),
    'penalty', (SELECT row_to_json(lp.*) FROM latest_penalty lp),
    'payments', (SELECT json_agg(row_to_json(p.*)) FROM payment_summary p),
    'usage', (SELECT row_to_json(us.*) FROM usage_summary us),
    'verification_time', NOW()
  ) as verification;
```

### Stripe Verification

**Check Stripe Dashboard**:
1. Go to Stripe Dashboard → Payments
2. Filter by customer (your test user's Stripe customer ID)
3. Verify:
   - Payment intents created
   - Refunds issued (if Case 3A)
   - Amounts match database records

**Or via API**:
```bash
# Get Stripe customer ID from database
SELECT stripe_customer_id FROM public.users WHERE id = '<your-user-id>';

# Then check Stripe (using Stripe CLI or API)
stripe payments list --customer <stripe-customer-id>
```

### Verification Checklist

After each test case, verify:

- [ ] **Commitment**: Created with correct deadline (compressed in testing mode)
- [ ] **Penalty Record**: Status matches expected case
- [ ] **Charged Amount**: Matches expected (actual or worst case)
- [ ] **Payment Record**: Created in database with correct type
- [ ] **Stripe Payment**: Created in Stripe (check dashboard)
- [ ] **Usage Data**: Synced correctly (if applicable)
- [ ] **Reconciliation**: Flagged correctly (if late sync)
- [ ] **Refund**: Applied correctly (if Case 3A, delta < 0)

---

## Post-Test Cleanup

### Step 1: Disable Testing Mode

**Action**: Turn off testing mode

```bash
# In Supabase Dashboard
TESTING_MODE=false
```

**Or remove environment variable**

---

### Step 2: Clear All Test Data

**Action**: Clean up test data

```bash
./scripts/clear_test_data.sh
```

---

### Step 3: Re-enable Normal Operation

**Action**: Disable testing mode (cron will automatically work again)

```bash
# In Supabase Dashboard
TESTING_MODE=false
```

**Note**: No need to manually re-enable cron - it automatically works when `TESTING_MODE=false`

---

## Testing Checklist

### Case 1: Sync Before Grace Expires
- [ ] Commitment created with compressed deadline
- [ ] Usage synced before grace expires
- [ ] Settlement charges actual penalty
- [ ] Charged amount capped at authorization
- [ ] Status = 'charged_actual'

### Case 2: No Sync Before Grace Expires
- [ ] Commitment created
- [ ] No usage synced
- [ ] Settlement charges worst case
- [ ] Charged amount = authorization
- [ ] Status = 'charged_worst_case'

### Case 3A: Late Sync - Refund
- [ ] Settlement charged worst case
- [ ] Usage synced after settlement
- [ ] Reconciliation flagged
- [ ] Refund issued
- [ ] Status = 'refunded' or 'refunded_partial'

### Case 3B: Late Sync - No Change
- [ ] Settlement charged worst case
- [ ] Actual exceeds authorization
- [ ] Capped actual = charged amount
- [ ] No reconciliation needed
- [ ] Status = 'charged_worst_case' (unchanged)

---

## Troubleshooting

### Issue: Settlement doesn't run

**Check**:
- Testing mode enabled? (`TESTING_MODE=true`)
- Manual trigger command correct? (should include `x-manual-trigger: true` header)
- Function logs for errors (Supabase Dashboard → Edge Functions → Logs)
- Check if settlement function is skipping due to testing mode

**Solution**: In testing mode, settlement only runs when manually triggered with special header

### Issue: Wrong charge amount

**Check**:
- Compressed timing working?
- Grace period calculation correct?
- Usage data synced correctly?
- Authorization cap applied?

### Issue: Reconciliation not triggered

**Check**:
- `needs_reconciliation` flag set?
- `reconciliation_delta_cents` calculated?
- Reconciliation function triggered?
- Function logs for errors

---

## Notes

- **Timing**: All times are relative to commitment creation (T+0:00)
- **Compressed Timeline**: 3 minutes = week, 1 minute = grace period
- **Manual Triggers**: Settlement must be triggered manually in testing mode (cron automatically skips)
- **iOS App**: Countdown uses backend deadline (automatically shows compressed timeline in testing mode)
- **Verification**: Use verification script after each test case for quick results check
- **Database**: Always verify in database and Stripe, don't rely only on app UI

---

**End of Testing Script**

