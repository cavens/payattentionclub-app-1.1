# iOS Test Audit - Step 2.1

**Date**: 2025-12-15  
**Status**: Analysis Complete

---

## Test Files Inventory

### 1. AppModelTests.swift
- **Total Tests**: 12 tests
- **Issues Found**: 6 tests use deprecated `PenaltyCalculator.calculateAuthorizationAmount()`
  - `testAuthorizationAmount_MinimumFiveDollars()` (line 101)
  - `testAuthorizationAmount_ZeroWhenNoTimeRemaining()` (line 112)
  - `testAuthorizationAmount_IncreasesWithAppCount()` (line 123)
  - `testAuthorizationAmount_RiskFactorCalculation()` (line 145)
  - `testAuthorizationAmount_HigherPenaltyRate()` (line 159)
- **Other Tests**: 6 tests for penalty calculation (these are fine - testing local calculation)

### 2. BackendClientTests.swift
- **Total Tests**: 12 tests
- **Issues Found**: None - all tests are for response decoding (JSON parsing)
- **Status**: ✅ No issues

### 3. DateUtilsTests.swift
- **Total Tests**: Unknown (need to check)
- **Issues Found**: Unknown (need to check)
- **Status**: ⏳ Needs review

### 4. payattentionclub_app_1_1Tests.swift
- **Total Tests**: Unknown (need to check)
- **Issues Found**: Unknown (need to check)
- **Status**: ⏳ Needs review

---

## Deprecated Method Analysis

### Method: `PenaltyCalculator.calculateAuthorizationAmount()`
- **Status**: `@available(*, deprecated)`
- **Reason**: Authorization calculation moved to backend
- **Replacement**: `BackendClient.previewMaxCharge()` or `AppModel.fetchAuthorizationAmount()`
- **Impact**: 6 tests in `AppModelTests.swift` use this deprecated method

### What the Deprecated Method Does
- Returns a simplified estimate (doesn't match backend formula)
- Formula: `5.0 + Double(appCount) * 2.0 + (penaltyPerMinute * 10.0)`
- Bounded: `min(100.0, max(5.0, estimate))`
- **Note**: This does NOT match the actual backend calculation

### What the Actual Implementation Does
- `AppModel.fetchAuthorizationAmount()` → calls `BackendClient.previewMaxCharge()`
- `BackendClient.previewMaxCharge()` → calls `rpc_preview_max_charge` RPC
- RPC uses `calculate_max_charge_cents()` function (complex formula with $5-$1000 bounds)

---

## Tests That Need Updating

### High Priority (Use Deprecated Method)

1. **AppModelTests.swift** - 6 tests:
   - `testAuthorizationAmount_MinimumFiveDollars()`
   - `testAuthorizationAmount_ZeroWhenNoTimeRemaining()`
   - `testAuthorizationAmount_IncreasesWithAppCount()`
   - `testAuthorizationAmount_RiskFactorCalculation()`
   - `testAuthorizationAmount_HigherPenaltyRate()`

### Medium Priority (Need Review)

- `DateUtilsTests.swift` - Need to check if any issues
- `payattentionclub_app_1_1Tests.swift` - Need to check if any issues

---

## Action Required

### Step 1: Run Tests in Xcode
1. Open Xcode
2. Run tests: Product → Test (⌘U)
3. Document any failures
4. Check if deprecated method tests pass or fail

### Step 2: Update Tests (If They Fail or Need Updating)
- Replace deprecated method calls with actual implementation
- Update tests to be async (since `previewMaxCharge()` is async)
- Update expected values to match actual backend calculation

---

## Notes

- **Cannot run Xcode tests from command line** - Need user to run in Xcode
- **Deprecated method still exists** - So tests might still pass (but test wrong thing)
- **Tests may pass but verify wrong calculation** - Similar to backend test issue we fixed

---

**Next Step**: User needs to run tests in Xcode to see if they actually fail, or if they pass but test the wrong thing.


