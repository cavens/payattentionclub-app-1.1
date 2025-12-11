# PAC Test Implementation Plan — Detailed

---

## Phase 1: Environment Configuration

**Goal:** Single source of truth for environment switching

---

### Step 1.1: Create iOS `Config.swift`

**File:** `payattentionclub-app-1.1/payattentionclub-app-1.1/Config.swift`

**Contents:**
- `Environment` enum: `.staging`, `.production`
- `supabaseUrl` — switches based on environment
- `supabaseAnonKey` — switches based on environment
- `stripePublishableKey` — switches based on environment
- `isTestMode` — true for staging, false for production
- Uses `#if DEBUG` to auto-select staging in dev builds

**Update required in:**
- `BackendClient.swift` — replace hardcoded URLs with `Config.supabaseUrl`
- `StripeManager.swift` (if exists) — use `Config.stripePublishableKey`

---

### Step 1.2: Create Deno test config

**File:** `supabase/tests/config.ts`

**Contents:**
- Reads from environment variables
- Exports: `supabaseUrl`, `supabaseServiceKey`, `stripeSecretKey`
- Includes validation (fail fast if keys missing)

---

### Step 1.3: Create `.env.example` template

**File:** `.env.example` (project root)

**Contents:**
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key
STRIPE_SECRET_KEY_TEST=sk_test_...
STRIPE_PUBLISHABLE_KEY_TEST=pk_test_...
```

**Also create:** `.env` (gitignored) with real values

---

### Step 1.4: Update `.gitignore`

**Add:**
```
.env
.env.staging
.env.production
```

---

## Phase 2: Backend Testing (Deno)

**Goal:** Automated tests for all 6 critical financial flows

---

### Step 2.1: Create test folder structure

**Create directories:**
```
supabase/tests/
supabase/tests/helpers/
```

---

### Step 2.2: Create test helper — `config.ts`

**File:** `supabase/tests/config.ts`

**Contents:**
- Load env vars
- Export typed config object
- Fail with clear error if missing

---

### Step 2.3: Create test helper — `client.ts`

**File:** `supabase/tests/helpers/client.ts`

**Contents:**
- Create and export Supabase client (service role)
- Create and export Stripe client
- Reusable across all tests

---

### Step 2.4: Create test helper — `seed.ts`

**File:** `supabase/tests/helpers/seed.ts`

**Contents:**
- `seedTestData()` — calls `rpc_setup_test_data`
- Returns test user IDs, commitment IDs for use in tests
- Accepts optional parameters to customize seed

---

### Step 2.5: Create `rpc_cleanup_test_data` SQL function

**File:** `supabase/remote_rpcs/rpc_cleanup_test_data.sql`

**What it deletes (in order for FK constraints):**
1. `payments` where `user_id` in test IDs
2. `daily_usage` where `user_id` in test IDs
3. `user_week_penalties` where `user_id` in test IDs
4. `commitments` where `user_id` in test IDs
5. `weekly_pools` where no remaining commitments reference them
6. Optionally: test users themselves

**Test user IDs (from existing `rpc_setup_test_data`):**
- `11111111-1111-1111-1111-111111111111`
- `22222222-2222-2222-2222-222222222222`
- `33333333-3333-3333-3333-333333333333`

---

### Step 2.6: Create test helper — `cleanup.ts`

**File:** `supabase/tests/helpers/cleanup.ts`

**Contents:**
- `cleanupTestData()` — calls `rpc_cleanup_test_data`
- Used in test teardown

---

### Step 2.7: Create test helper — `assertions.ts`

**File:** `supabase/tests/helpers/assertions.ts`

**Contents:**
- `assertCommitmentExists(userId, weekEndDate)` — query + assert
- `assertPenaltyEquals(userId, weekEndDate, expectedCents)`
- `assertPaymentStatus(userId, weekEndDate, expectedStatus)`
- `assertReconciliationFlagged(userId, weekEndDate)`

---

### Step 2.8: Write `test_create_commitment.ts`

**File:** `supabase/tests/test_create_commitment.ts`

**Test steps:**
1. Cleanup any existing test data
2. Seed test user with active payment method
3. Call `rpc_create_commitment` with test parameters
4. Assert: commitment row exists with correct `limit_minutes`, `penalty_per_minute_cents`
5. Assert: `weekly_pools` row exists for the week
6. Cleanup

---

### Step 2.9: Write `test_sync_usage_penalty.ts`

**File:** `supabase/tests/test_sync_usage_penalty.ts`

**Test steps:**
1. Cleanup + seed (user + commitment)
2. Call `rpc_sync_daily_usage` with usage that exceeds limit
3. Assert: `daily_usage.exceeded_minutes` correct
4. Assert: `daily_usage.penalty_cents` = exceeded × rate
5. Assert: `user_week_penalties.total_penalty_cents` updated
6. Cleanup

---

### Step 2.10: Write `test_weekly_close.ts`

**File:** `supabase/tests/test_weekly_close.ts`

**Test steps:**
1. Cleanup + seed (user + commitment + daily_usage with penalties)
2. Call `weekly-close` edge function via fetch
3. Assert: `user_week_penalties.status` changed
4. Assert: `payments` row created
5. Assert: `weekly_pools.status` = 'closed'
6. Cleanup

---

### Step 2.11: Write `test_settlement_actual.ts`

**File:** `supabase/tests/test_settlement_actual.ts`

**Test steps:**
1. Cleanup + seed (user + commitment + synced usage)
2. Call `run-weekly-settlement` edge function
3. Assert: `settlement_status` = 'charged_actual'
4. Assert: `charged_amount_cents` = actual penalty amount
5. Assert: `payments` row with correct amount
6. Cleanup

---

### Step 2.12: Write `test_settlement_worst_case.ts`

**File:** `supabase/tests/test_settlement_worst_case.ts`

**Test steps:**
1. Cleanup + seed (user + commitment, NO usage synced)
2. Set commitment `week_grace_expires_at` to past (simulate grace expired)
3. Call `run-weekly-settlement` edge function
4. Assert: `settlement_status` = 'charged_worst_case'
5. Assert: `charged_amount_cents` = `max_charge_cents`
6. Cleanup

---

### Step 2.13: Write `test_late_user_refund.ts`

**File:** `supabase/tests/test_late_user_refund.ts`

**Test steps:**
1. Cleanup + seed (user + commitment)
2. Manually set `settlement_status` = 'charged_worst_case', `charged_amount_cents` = 1000
3. Call `rpc_sync_daily_usage` with actual usage (lower penalty, e.g., 300 cents)
4. Assert: `needs_reconciliation` = true
5. Assert: `reconciliation_delta_cents` = -700 (refund owed)
6. Cleanup

---

### Step 2.14: Create `run_backend_tests.sh`

**File:** `supabase/tests/run_backend_tests.sh`

**Contents:**
```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../../.env
deno test . --allow-net --allow-env --allow-read
```

---

## Phase 3: iOS Unit Testing

**Goal:** Fast tests for Swift business logic

---

### Step 3.1: Create test target in Xcode

**In Xcode:**
- File → New → Target → Unit Testing Bundle
- Name: `payattentionclub-app-1.1Tests`
- Language: Swift

---

### Step 3.2: Write `AppModelTests.swift`

**File:** `payattentionclub-app-1.1Tests/AppModelTests.swift`

**Tests:**
- `testPenaltyCalculation_UnderLimit` — 0 penalty
- `testPenaltyCalculation_OverLimit` — correct penalty
- `testPenaltyCalculation_ExactlyAtLimit` — 0 penalty
- `testMaxChargeCalculation` — matches formula

---

### Step 3.3: Write `BackendClientTests.swift`

**File:** `payattentionclub-app-1.1Tests/BackendClientTests.swift`

**Tests:**
- `testParseBillingStatusResponse` — correct parsing
- `testParseCommitmentResponse` — correct parsing
- `testParseWeekStatusResponse` — correct parsing

---

### Step 3.4: Write `DateUtilsTests.swift`

**File:** `payattentionclub-app-1.1Tests/DateUtilsTests.swift`

**Tests:**
- `testNextMondayDeadline_FromTuesday` — correct date
- `testNextMondayDeadline_FromSunday` — correct date
- `testNextMondayDeadline_FromMonday` — same day or next week?
- `testWeekStartDate` — correct calculation

---

## Phase 4: iOS UI Testing

**Goal:** Automated tests for critical user flows

---

### Step 4.1: Create UI test target in Xcode

**In Xcode:**
- File → New → Target → UI Testing Bundle
- Name: `payattentionclub-app-1.1UITests`
- Language: Swift

---

### Step 4.2: Write `CommitFlowUITest.swift`

**File:** `payattentionclub-app-1.1UITests/CommitFlowUITest.swift`

**Tests:**
- `testSetupScreenAppears` — verify initial screen
- `testSliderAdjustment` — can adjust limit/penalty
- `testCommitButtonNavigates` — tapping Commit moves forward
- `testAuthorizationScreenAppears` — verify auth screen shows

---

### Step 4.3: Write `MonitorViewUITest.swift`

**File:** `payattentionclub-app-1.1UITests/MonitorViewUITest.swift`

**Tests:**
- `testProgressBarVisible` — UI element exists
- `testPenaltyDisplayVisible` — shows penalty amount
- `testCountdownVisible` — shows deadline countdown

---

### Step 4.4: Write `BulletinViewUITest.swift`

**File:** `payattentionclub-app-1.1UITests/BulletinViewUITest.swift`

**Tests:**
- `testWeekSummaryVisible` — shows totals
- `testRecommitButtonExists` — button present
- `testRecommitNavigatesToSetup` — correct navigation

---

## Phase 5: iOS Test Mode / Dev Menu

**Goal:** Manual testing controls for developers

---

### Step 5.1: Create `DevMenuView.swift`

**File:** `payattentionclub-app-1.1/Views/DevMenuView.swift`

**Contents:**
- Only visible when `Config.isTestMode` or user `is_test_user`
- Sections:
  - Current environment indicator
  - "Trigger Weekly Close" button
  - "Reset Test Data" button
  - "Skip to Deadline" button (advances displayed time)
  - Current user info display

---

### Step 5.2: Add secret gesture to access Dev Menu

**In `RootRouterView.swift` or main view:**
- Triple-tap on logo → shows Dev Menu
- Or: shake gesture
- Or: long-press on version number

---

### Step 5.3: Add environment badge

**In app UI (when staging):**
- Small "STAGING" badge in corner
- Different app icon tint (optional)
- Prevents confusion about which environment you're in

---

### Step 5.4: Wire up Dev Menu buttons

**Button actions:**
- "Trigger Weekly Close" → calls `admin-close-week-now` edge function
- "Reset Test Data" → calls `rpc_cleanup_test_data` then `rpc_setup_test_data`
- "Skip to Deadline" → adjusts local display (or triggers backend time simulation)

---

## Phase 6: Master Test Script

**Goal:** One command to run everything

---

### Step 6.1: Create `run_all_tests.sh`

**File:** `run_all_tests.sh` (project root)

**Contents:**
```bash
#!/bin/bash
set -e

echo "🧪 PAC Test Suite"
echo "================"
echo ""

# Backend tests
echo "📦 Backend Tests (Deno)"
echo "-----------------------"
cd supabase/tests
source ../../.env
deno test . --allow-net --allow-env --allow-read
cd ../..
echo ""

# iOS Unit tests
echo "📱 iOS Unit Tests"
echo "-----------------"
xcodebuild test \
  -project payattentionclub-app-1.1/payattentionclub-app-1.1.xcodeproj \
  -scheme payattentionclub-app-1.1 \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:payattentionclub-app-1.1Tests \
  | xcpretty
echo ""

echo "================"
echo "All tests passed! 🎉"
```

---

### Step 6.2: Make script executable

```bash
chmod +x run_all_tests.sh
```

---

## Implementation Order

| Order | Step | Time Est. | Dependency |
|-------|------|-----------|------------|
| 1 | 1.1 Create `Config.swift` | 20 min | None |
| 2 | 1.2 Create `config.ts` | 10 min | None |
| 3 | 1.3 Create `.env.example` | 5 min | None |
| 4 | 1.4 Update `.gitignore` | 2 min | None |
| 5 | 2.1 Create test folder structure | 2 min | None |
| 6 | 2.2-2.7 Create test helpers | 30 min | 2.1 |
| 7 | 2.5 Create `rpc_cleanup_test_data` | 15 min | None |
| 8 | 2.8 Write `test_create_commitment.ts` | 20 min | 2.2-2.7 |
| 9 | 2.9 Write `test_sync_usage_penalty.ts` | 20 min | 2.8 |
| 10 | 2.10 Write `test_weekly_close.ts` | 25 min | 2.9 |
| 11 | 2.11 Write `test_settlement_actual.ts` | 20 min | 2.10 |
| 12 | 2.12 Write `test_settlement_worst_case.ts` | 20 min | 2.11 |
| 13 | 2.13 Write `test_late_user_refund.ts` | 20 min | 2.12 |
| 14 | 2.14 Create `run_backend_tests.sh` | 5 min | 2.13 |
| 15 | 3.1 Create iOS test target | 5 min | None |
| 16 | 3.2-3.4 Write iOS unit tests | 45 min | 3.1 |
| 17 | 4.1 Create iOS UI test target | 5 min | None |
| 18 | 4.2-4.4 Write iOS UI tests | 60 min | 4.1 |
| 19 | 5.1-5.4 Create Dev Menu | 45 min | 1.1 |
| 20 | 6.1-6.2 Create master test script | 10 min | All above |

**Total estimated time:** ~6 hours

---

## Deliverables Checklist

### Files Created

**Config (Phase 1):**
- [x] `Config.swift` ✅ (Enhanced with AppEnvironment enum, staging/production switching)
- [x] `supabase/tests/config.ts` ✅
- [ ] `.env` — Create manually (see instructions below)
- [x] `.gitignore` updated ✅

**Backend Tests (Phase 2):**
- [x] `supabase/tests/helpers/client.ts` ✅
- [x] `supabase/tests/helpers/seed.ts` ✅
- [x] `supabase/tests/helpers/cleanup.ts` ✅
- [x] `supabase/tests/helpers/assertions.ts` ✅
- [x] `supabase/remote_rpcs/rpc_cleanup_test_data.sql` ✅
- [x] `supabase/tests/test_create_commitment.ts` ✅
- [x] `supabase/tests/test_sync_usage_penalty.ts` ✅
- [x] `supabase/tests/test_weekly_close.ts` ✅
- [x] `supabase/tests/test_settlement_actual.ts` ✅
- [x] `supabase/tests/test_settlement_worst_case.ts` ✅
- [x] `supabase/tests/test_late_user_refund.ts` ✅
- [x] `supabase/tests/run_backend_tests.sh` ✅

**iOS Unit Tests (Phase 3):**
- [ ] `payattentionclub-app-1.1Tests/AppModelTests.swift`
- [ ] `payattentionclub-app-1.1Tests/BackendClientTests.swift`
- [ ] `payattentionclub-app-1.1Tests/DateUtilsTests.swift`

**iOS UI Tests (Phase 4):**
- [ ] `payattentionclub-app-1.1UITests/CommitFlowUITest.swift`
- [ ] `payattentionclub-app-1.1UITests/MonitorViewUITest.swift`
- [ ] `payattentionclub-app-1.1UITests/BulletinViewUITest.swift`

**Dev Menu (Phase 5):**
- [ ] `DevMenuView.swift`
- [ ] Secret gesture wired up
- [ ] Environment badge added

**Master Script (Phase 6):**
- [ ] `run_all_tests.sh`

---

## How to Run Tests (After Implementation)

### One command for everything:
```bash
./run_all_tests.sh
```

### Run separately:

| What | Command | Where |
|------|---------|-------|
| Backend only | `deno test supabase/tests/ --allow-net --allow-env` | Terminal |
| iOS Unit only | `Cmd + U` | Xcode |
| iOS UI only | `Cmd + U` (select UI test scheme) | Xcode |

---

## Environment Switching Summary

| What | Staging | Production |
|------|---------|------------|
| Supabase URL | `staging-project.supabase.co` | `prod-project.supabase.co` |
| Stripe keys | `sk_test_...` / `pk_test_...` | `sk_live_...` / `pk_live_...` |
| Bundle ID | `com.payattentionclub.app.staging` | `com.payattentionclub.app` |
| App name | PAC (Staging) | Pay Attention Club |
| Tests run against | ✅ Yes | ❌ Never |

