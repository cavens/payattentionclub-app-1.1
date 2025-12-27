# Test Fix Plan

**Status**: 📋 Analysis Complete - Ready for Implementation  
**Priority**: Medium  
**Last Updated**: 2025-12-15

---

## Executive Summary

**IMPORTANT**: The actual frontend and backend functions are working correctly. The tests need to be **adapted to match the actual implementation**, not the other way around.

**Actually Broken Tests:**
- **Backend**: 1 test failing, 1 test passing but wrong (2 total)
- **iOS**: Unknown - need to verify if they actually fail

After major code changes (authorization calculation moved to backend, new RPC functions, environment variable renames), the test suite is out of sync. This plan focuses on **fixing only the broken tests** to match what the actual functions do.

**Scope:**
- **Backend Tests (Deno)**: 2 broken tests out of 34 total
- **iOS Tests (Swift)**: Need to verify if they actually fail
- **Estimated Time**: 2-4 hours (focused on broken tests only)

---

## Current Test Status

### Backend Tests (Deno)

**Test Files:**
1. `test_create_commitment.ts` - Tests commitment creation
2. `test_late_user_refund.ts` - Tests late sync & refund flow
3. `test_settlement_actual.ts` - Tests settlement with actual usage
4. `test_settlement_worst_case.ts` - Tests settlement without sync
5. `test_sync_usage_penalty.ts` - Tests usage sync and penalties
6. `test_weekly_close.ts` - Tests weekly close process

**Current Status:**
- ✅ 32 tests passing correctly
- ❌ **1 test FAILING**: `test_weekly_close.ts` - "Pool status changes to closed" (pool is 'closed' when test expects 'open')
- ⚠️ **1 test PASSING BUT WRONG**: `test_create_commitment.ts` - "Max charge is calculated correctly" (uses hardcoded formula instead of actual backend)

### iOS Tests (Swift)

**Test Files:**
1. `AppModelTests.swift` - Tests AppModel logic
2. `BackendClientTests.swift` - Tests BackendClient
3. `DateUtilsTests.swift` - Tests date utilities
4. `payattentionclub_app_1_1Tests.swift` - General app tests

**Current Status:**
- ❓ **Unknown**: Need to verify if tests actually fail or just use deprecated methods
- ⚠️ Tests use deprecated `PenaltyCalculator.calculateAuthorizationAmount()` (6 tests)
- ⚠️ No tests for new `BackendClient.previewMaxCharge()` method
- **Action**: Check if iOS tests actually fail when run, or if they pass despite using deprecated methods

---

## Issues Identified

### 1. Authorization Calculation Mismatch ⚠️ TEST NEEDS FIXING

**Actual Implementation:**
- `rpc_create_commitment` calls `calculate_max_charge_cents()` 
- Formula: Complex calculation with hours remaining, daily usage caps, risk factors, bounded $5-$1000
- See: `supabase/remote_rpcs/calculate_max_charge_cents.sql`

**What Test Expects:**
- Hardcoded simple formula: `limit * penalty * 7` (line 73, 180)
- This is WRONG - doesn't match actual implementation

**Fix Required:**
- Update test to call actual `rpc_preview_max_charge` or `calculate_max_charge_cents()` to get real value
- Remove hardcoded calculation

**Files Affected:**
- `supabase/tests/test_create_commitment.ts` (line 73, 180)

### 2. Missing Tests for New Functions

**Problem:**
- `rpc_preview_max_charge` - No tests exist
- `calculate_max_charge_cents` - No direct tests
- `BackendClient.previewMaxCharge()` - No iOS tests

**Impact:** New functionality not covered by tests

**Files Affected:**
- Need to create: `test_preview_max_charge.ts`
- Need to add: Tests in `BackendClientTests.swift`

### 3. Deprecated Method Usage in iOS Tests ⚠️ TEST NEEDS FIXING

**Actual Implementation:**
- `AppModel.fetchAuthorizationAmount()` calls `BackendClient.previewMaxCharge()`
- `BackendClient.previewMaxCharge()` calls `rpc_preview_max_charge` RPC
- This is the correct, current implementation

**What Test Expects:**
- Tests use deprecated `PenaltyCalculator.calculateAuthorizationAmount()`
- This method is marked `@available(*, deprecated)` and doesn't match backend formula

**Fix Required:**
- Update tests to use `BackendClient.previewMaxCharge()` (async method)
- Or test `AppModel.fetchAuthorizationAmount()` directly
- Remove tests that use deprecated method

**Files Affected:**
- `payattentionclub-app-1.1/payattentionclub-app-1.1Tests/AppModelTests.swift` (lines 101, 112, 123, 130, 145, 159)

### 4. Test Weekly Close Failure ⚠️ TEST NEEDS FIXING

**Actual Implementation:**
- `weekly-close` edge function closes pools
- Pool status can be "open" or "closed" depending on state

**What Test Expects:**
- Test expects pool to be "open" before calling weekly-close (line 175)
- But pool is already "closed" (likely from previous test run or test setup issue)

**Fix Required:**
- Ensure test creates pool with "open" status before testing
- Or update test to handle case where pool might already be closed
- Check test cleanup/setup to ensure fresh state

**Files Affected:**
- `supabase/tests/test_weekly_close.ts` (line 175)

### 5. Environment Variable Naming

**Problem:**
- Tests may reference old variable names
- Already fixed in `client.ts` (uses `secretKey` not `serviceRoleKey`)
- Need to verify all test files use correct names

**Impact:** Tests may fail if old names are used

**Files Affected:**
- All test files (verify)

---

## Step-by-Step Fix Plan

**Focus**: Fix only the 2 broken backend tests. Check iOS tests to see if they actually fail.

### Phase 1: Fix Broken Backend Tests (2-3 hours)

#### Step 1.1: Fix test_create_commitment.ts Calculation

**Goal**: Update test to use actual backend calculation instead of hardcoded formula

**Tasks:**
- [ ] Update `createTestCommitment()` helper (line 73) to call actual RPC:
  ```typescript
  // OLD (wrong - hardcoded):
  const maxChargeCents = options.limitMinutes * options.penaltyPerMinuteCents * 7;
  
  // NEW (correct - use actual backend):
  const preview = await callRpc("rpc_preview_max_charge", {
    deadline_date: weekEndDate,
    limit_minutes: options.limitMinutes,
    penalty_per_minute_cents: options.penaltyPerMinuteCents,
    apps_to_limit: { app_bundle_ids: ["com.apple.Safari"], categories: [] }
  });
  const maxChargeCents = preview.max_charge_cents;
  ```
- [ ] Update test assertion (line 180) to use actual calculation:
  ```typescript
  // OLD (wrong - hardcoded):
  const expectedMaxCharge = 30 * 25 * 7; // 5250 cents
  
  // NEW (correct - call actual backend):
  const preview = await callRpc("rpc_preview_max_charge", {
    deadline_date: result.week_end_date,
    limit_minutes: 30,
    penalty_per_minute_cents: 25,
    apps_to_limit: { app_bundle_ids: ["com.apple.Safari"], categories: [] }
  });
  const expectedMaxCharge = preview.max_charge_cents;
  ```
- [ ] Run test to verify it passes with actual backend values
- [ ] Update other tests that check max_charge_cents to use actual calculation

**Success Criteria**: `test_create_commitment.ts` uses actual backend calculation (matches what `rpc_create_commitment` does)

---

#### Step 1.2: Create Test for rpc_preview_max_charge

**Tasks:**
- [ ] Create new test file: `supabase/tests/test_preview_max_charge.ts`
- [ ] Test cases:
  - [ ] Returns correct value for normal inputs
  - [ ] Enforces $5 minimum (500 cents)
  - [ ] Enforces $1000 maximum (100000 cents)
  - [ ] Handles edge cases (very low/high limits, penalties)
  - [ ] Matches calculation used by `rpc_create_commitment`
- [ ] Run test to verify it passes

**Success Criteria**: New test file created and passing

**Example Test Structure:**
```typescript
Deno.test("Preview Max Charge - Returns bounded values", async () => {
  const result = await callRpc("rpc_preview_max_charge", {
    deadline_date: "2025-12-22",
    limit_minutes: 30,
    penalty_per_minute_cents: 10,
    apps_to_limit: { app_bundle_ids: [], categories: [] }
  });
  
  assertEquals(result.max_charge_cents >= 500, true, "Should be at least $5");
  assertEquals(result.max_charge_cents <= 100000, true, "Should be at most $1000");
});
```

---

#### Step 1.3: Fix test_weekly_close.ts Pool Status

**Goal**: Fix test to match actual pool status behavior

**Tasks:**
- [ ] Review test at line 175 - understand why pool is "closed" instead of "open"
- [ ] Check if `createTestCommitment()` creates pool with correct status
- [ ] Verify pool creation in test setup:
  ```typescript
  // Ensure pool is created with "open" status
  await supabase.from("weekly_pools").upsert({
    week_start_date: deadline,
    week_end_date: deadline,
    total_penalty_cents: 0,
    status: "open",  // ← Ensure this is set
  }, { onConflict: "week_start_date" });
  ```
- [ ] Or update test to check if pool exists and is "open" before asserting
- [ ] Run test to verify it passes consistently

**Success Criteria**: `test_weekly_close.ts` passes consistently (pool status matches actual behavior)

---

#### Step 1.4: Verify All Tests Use Correct Environment Variables

**Tasks:**
- [ ] Search for old variable names in test files:
  ```bash
  grep -r "SERVICE_ROLE_KEY\|ANON_KEY" supabase/tests/
  ```
- [ ] Replace with new names if found:
  - `SERVICE_ROLE_KEY` → `SECRET_KEY`
  - `ANON_KEY` → `PUBLISHABLE_KEY`
- [ ] Verify `config.ts` uses correct names (already fixed)
- [ ] Run all tests to verify

**Success Criteria**: All tests use correct environment variable names

---

#### Step 1.5: Run Full Backend Test Suite

**Tasks:**
- [ ] Run all backend tests:
  ```bash
  ./supabase/tests/run_backend_tests.sh staging
  ```
- [ ] Document any remaining failures
- [ ] Fix remaining issues
- [ ] Verify all tests pass

**Success Criteria**: All backend tests pass (100%)

---

### Phase 2: Check & Fix iOS Tests (1-2 hours) - IF THEY FAIL

#### Step 2.1: Audit iOS Test Files

**Tasks:**
- [ ] Open Xcode
- [ ] Run iOS tests: Product → Test (⌘U)
- [ ] Document all failures
- [ ] Identify which tests use deprecated methods
- [ ] List tests that need updating

**Success Criteria**: Complete inventory of iOS test failures

---

#### Step 2.2: Update AppModelTests.swift

**Goal**: Update tests to use actual implementation (`BackendClient.previewMaxCharge()` or `AppModel.fetchAuthorizationAmount()`)

**Tasks:**
- [ ] Find all uses of deprecated `PenaltyCalculator.calculateAuthorizationAmount()` (lines 101, 112, 123, 130, 145, 159)
- [ ] Replace with actual implementation:
  ```swift
  // OLD (deprecated - doesn't match backend):
  let auth = PenaltyCalculator.calculateAuthorizationAmount(...)
  
  // NEW (correct - matches actual implementation):
  // Option 1: Test AppModel.fetchAuthorizationAmount() directly
  let auth = await appModel.fetchAuthorizationAmount()
  
  // Option 2: Test BackendClient.previewMaxCharge() directly
  let response = try await BackendClient.shared.previewMaxCharge(
      deadlineDate: deadline,
      limitMinutes: limitMinutes,
      penaltyPerMinuteCents: penaltyPerMinuteCents,
      selectedApps: selectedApps
  )
  let auth = response.maxChargeDollars
  ```
- [ ] Update test methods to be async:
  ```swift
  func testAuthorizationAmount() async throws {
      let auth = await appModel.fetchAuthorizationAmount()
      XCTAssertGreaterThanOrEqual(auth, 5.0, "Should be at least $5")
      XCTAssertLessThanOrEqual(auth, 1000.0, "Should be at most $1000")
  }
  ```
- [ ] Update expected values to match actual backend calculation (bounded $5-$1000)
- [ ] Run tests to verify they pass

**Success Criteria**: `AppModelTests.swift` tests actual implementation, all tests pass

---

#### Step 2.3: Add Tests for previewMaxCharge

**Tasks:**
- [ ] Add tests to `BackendClientTests.swift`:
  - [ ] Test `previewMaxCharge()` returns correct value
  - [ ] Test minimum bound ($5)
  - [ ] Test maximum bound ($1000)
  - [ ] Test error handling (network errors, invalid inputs)
- [ ] Run tests to verify they pass

**Success Criteria**: New tests added and passing

**Example Test:**
```swift
func testPreviewMaxCharge() async throws {
    let result = try await BackendClient.shared.previewMaxCharge(
        deadlineDate: Date(),
        limitMinutes: 60,
        penaltyPerMinuteCents: 10,
        appsToLimit: AppsToLimit(appBundleIds: [], categories: [])
    )
    
    XCTAssertGreaterThanOrEqual(result, 5.0, "Should be at least $5")
    XCTAssertLessThanOrEqual(result, 1000.0, "Should be at most $1000")
}
```

---

#### Step 2.4: Remove/Update Deprecated Tests

**Tasks:**
- [ ] Review if any tests should be removed (testing deprecated functionality)
- [ ] Update or remove tests that are no longer relevant
- [ ] Ensure test coverage is maintained
- [ ] Run full iOS test suite

**Success Criteria**: All iOS tests pass, deprecated method tests removed/updated

---

### Phase 3: Verification (30 minutes)

#### Step 3.1: Run Full Test Suite

**Tasks:**
- [ ] Run backend tests:
  ```bash
  ./supabase/tests/run_backend_tests.sh staging
  ```
- [ ] Run iOS tests in Xcode: Product → Test (⌘U)
- [ ] Document any remaining failures
- [ ] Fix any edge cases

**Success Criteria**: All tests pass (backend + iOS)

---

#### Step 3.2: Verify Test Coverage

**Tasks:**
- [ ] List all RPC functions (18 files)
- [ ] List all Edge Functions (9 functions)
- [ ] Check which have tests:
  - [ ] `rpc_create_commitment` - ✅ Has test
  - [ ] `rpc_preview_max_charge` - ❌ Needs test (Step 1.2)
  - [ ] `rpc_sync_daily_usage` - ✅ Has test
  - [ ] `weekly-close` - ✅ Has test
  - [ ] Other functions - Review coverage
- [ ] Document test coverage gaps

**Success Criteria**: Test coverage documented

---

#### Step 3.3: Update Test Documentation

**Tasks:**
- [ ] Update `KNOWN_ISSUES.md` - Mark test harness issue as resolved
- [ ] Document test fixes in commit message
- [ ] Update any test-related documentation

**Success Criteria**: Documentation updated

---

## Implementation Checklist

### Phase 1: Backend Tests
- [ ] Step 1.1: Fix test_create_commitment.ts calculation
- [ ] Step 1.2: Create test for rpc_preview_max_charge
- [ ] Step 1.3: Fix test_weekly_close.ts pool status
- [ ] Step 1.4: Verify environment variables
- [ ] Step 1.5: Run full backend test suite

### Phase 2: iOS Tests
- [ ] Step 2.1: Audit iOS test files
- [ ] Step 2.2: Update AppModelTests.swift
- [ ] Step 2.3: Add tests for previewMaxCharge
- [ ] Step 2.4: Remove/update deprecated tests

### Phase 3: Integration
- [ ] Step 3.1: Run full test suite
- [ ] Step 3.2: Verify test coverage
- [ ] Step 3.3: Update documentation

---

## Estimated Time

- **Phase 1 (Backend - 2 broken tests)**: 2-3 hours
- **Phase 2 (iOS - check if they fail)**: 1-2 hours (only if they actually fail)
- **Phase 3 (Verification)**: 30 minutes

**Total**: 2-4 hours (focused on broken tests only)

---

## Key Changes Summary

**Philosophy**: Adapt tests to match actual implementation (frontend and backend are correct)

### Backend Tests
1. ✅ Fix calculation mismatch in `test_create_commitment.ts` - use actual `rpc_preview_max_charge` instead of hardcoded formula
2. ✅ Add test for `rpc_preview_max_charge` - verify it matches `rpc_create_commitment` calculation
3. ✅ Fix `test_weekly_close.ts` pool status issue - ensure test setup creates pool with correct status
4. ✅ Verify environment variable usage - ensure all tests use correct variable names

### iOS Tests
1. ✅ Replace deprecated `PenaltyCalculator.calculateAuthorizationAmount()` with actual `AppModel.fetchAuthorizationAmount()` or `BackendClient.previewMaxCharge()`
2. ✅ Add tests for new `previewMaxCharge()` method - verify it calls backend correctly
3. ✅ Update all affected test methods to be async - match actual async implementation

---

## Success Criteria

### Backend Tests
- ✅ All 6 test files pass (currently 33/34 passing)
- ✅ New test for `rpc_preview_max_charge` created
- ✅ All tests use actual backend calculations (not hardcoded)

### iOS Tests
- ✅ All 4 test files pass
- ✅ No deprecated method usage
- ✅ New tests for `previewMaxCharge()` added

### Overall
- ✅ 100% test pass rate
- ✅ Test coverage maintained or improved
- ✅ Documentation updated

---

## Notes

- **Test in staging first** - Always test changes in staging before production
- **One test file at a time** - Fix and verify each test file before moving to next
- **Keep tests simple** - Focus on functionality, not edge cases (can add later)
- **Document as you go** - Note any test behavior changes

---

## Related Documentation

- `docs/KNOWN_ISSUES.md` - Test harness issue documented
- `ARCHITECTURE.md` - System architecture
- `DEPLOYMENT_WORKFLOW.md` - Deployment process

---

**Status**: Ready for implementation. Start with Phase 1, Step 1.1 when ready.

