# Automated Testing Strategy for All 24 Settlement Cases

**Date**: 2026-01-20  
**Purpose**: Design comprehensive automated testing framework to catch logic errors before manual testing

---

## Executive Summary

Yes, we can and should programmatically test all 24 cases. This document outlines:
1. **Automated test framework** that covers all 24 cases
2. **Code analysis approach** to predict outcomes statically
3. **Test data generation** for each case
4. **Assertion framework** to verify expected vs actual results

---

## Current State Analysis

### Existing Tests
- ✅ `test_settlement_actual.ts` - Tests Case 1 (sync before grace)
- ✅ `test_settlement_worst_case.ts` - Tests Case 2 (no sync)
- ✅ `test_late_user_refund.ts` - Tests Case 3 (late sync)
- ❌ **Missing**: Tests for all 24 combinations
- ❌ **Missing**: Tests for zero penalty cases
- ❌ **Missing**: Tests for below-minimum penalty cases
- ❌ **Missing**: Tests for sync-before-grace vs no-sync-before-grace

### Test Infrastructure
- ✅ Deno test framework
- ✅ Test helpers (`withCleanup`, `ensureTestUserExists`)
- ✅ Mock Stripe (test mode)
- ⚠️ **Limited**: Time mocking (relies on real time or manual overrides)
- ⚠️ **Missing**: Systematic test case generation

---

## Proposed Solution: Comprehensive Test Matrix Framework

### Architecture

```
test_settlement_matrix.ts
├── Test Case Generator (24 cases)
├── Test Data Builder (usage patterns)
├── Settlement Simulator (mock settlement execution)
├── Result Verifier (assertions)
└── Test Runner (executes all cases)
```

---

## Implementation Plan

### Phase 1: Test Case Definition

**File**: `supabase/tests/helpers/settlement_test_cases.ts`

```typescript
export type TestCase = {
  id: string; // e.g., "1_A_A", "1_A_B", etc.
  mainCase: 1 | 2 | 3;
  subCondition: "A" | "B"; // A = sync before grace, B = no sync before grace
  usagePattern: "A" | "B" | "C" | "D";
  description: string;
  
  // Test setup
  setup: {
    syncBeforeGrace: boolean;
    syncWithinGrace: boolean; // Only for Case 1
    syncAfterGrace: boolean; // Only for Case 3
    usageMinutes: number;
    limitMinutes: number;
    penaltyPerMinuteCents: number;
  };
  
  // Expected results
  expected: {
    settlementStatus: string;
    chargedAmountCents: number;
    actualAmountCents: number;
    paymentCount: number;
    paymentType?: string;
    needsReconciliation?: boolean;
    reconciliationDeltaCents?: number;
  };
};

export const ALL_TEST_CASES: TestCase[] = [
  // Case 1_A_A: Sync before grace + within grace + 0 usage + 0 penalty
  {
    id: "1_A_A",
    mainCase: 1,
    subCondition: "A",
    usagePattern: "A",
    description: "Sync before grace + within grace + 0 usage + 0 penalty",
    setup: {
      syncBeforeGrace: true,
      syncWithinGrace: true,
      syncAfterGrace: false,
      usageMinutes: 0,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    },
    expected: {
      settlementStatus: "pending", // or unchanged
      chargedAmountCents: 0,
      actualAmountCents: 0,
      paymentCount: 0,
    },
  },
  
  // Case 1_A_B: Sync before grace + within grace + >0 usage + <60 cent penalty
  {
    id: "1_A_B",
    mainCase: 1,
    subCondition: "A",
    usagePattern: "B",
    description: "Sync before grace + within grace + >0 usage + <60 cent penalty",
    setup: {
      syncBeforeGrace: true,
      syncWithinGrace: true,
      syncAfterGrace: false,
      usageMinutes: 65, // 5 over limit = 50 cents
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    },
    expected: {
      settlementStatus: "pending", // Below Stripe minimum
      chargedAmountCents: 0,
      actualAmountCents: 50,
      paymentCount: 0,
    },
  },
  
  // ... (all 24 cases)
];
```

### Phase 2: Test Data Builder

**File**: `supabase/tests/helpers/settlement_test_builder.ts`

```typescript
export class SettlementTestBuilder {
  private userId: string;
  private commitmentId: string;
  private weekEndDate: string;
  private graceExpiresAt: Date;
  private now: Date;
  
  constructor(options: {
    userId: string;
    weekEndDate: string;
    graceExpiresAt: Date;
    now: Date; // Mock current time
  }) {
    this.userId = options.userId;
    this.weekEndDate = options.weekEndDate;
    this.graceExpiresAt = options.graceExpiresAt;
    this.now = options.now;
  }
  
  /**
   * Create commitment with specific settings
   */
  async createCommitment(options: {
    limitMinutes: number;
    penaltyPerMinuteCents: number;
    maxChargeCents: number;
  }): Promise<string> {
    // Implementation
  }
  
  /**
   * Sync usage at specific time
   */
  async syncUsage(options: {
    atTime: Date; // When to sync
    usageMinutes: number;
    limitMinutes: number;
    penaltyPerMinuteCents: number;
  }): Promise<void> {
    // Only sync if atTime <= now
    if (options.atTime.getTime() > this.now.getTime()) {
      throw new Error(`Cannot sync at future time: ${options.atTime}`);
    }
    
    // Create daily_usage entry with correct commitment_id
    // Update user_week_penalties with last_updated timestamp
  }
  
  /**
   * Run settlement at specific time
   */
  async runSettlement(atTime: Date): Promise<SettlementResult> {
    // Only run if atTime <= now
    if (atTime.getTime() > this.now.getTime()) {
      throw new Error(`Cannot run settlement at future time: ${atTime}`);
    }
    
    // Call settlement function with targetWeek
    // Return result
  }
  
  /**
   * Advance time (for testing)
   */
  advanceTime(ms: number): void {
    this.now = new Date(this.now.getTime() + ms);
  }
}
```

### Phase 3: Settlement Simulator

**File**: `supabase/tests/helpers/settlement_simulator.ts`

```typescript
/**
 * Simulates settlement logic without actually calling Stripe
 * This allows us to test the logic deterministically
 */
export class SettlementSimulator {
  /**
   * Simulate hasSyncedUsage() logic
   */
  static hasSyncedUsage(
    candidate: {
      reportedDays: number;
      penalty?: {
        last_updated?: string;
        actual_amount_cents?: number;
      };
    },
    graceDeadline: Date,
    isTestingMode: boolean
  ): boolean {
    // Replicate exact logic from run-weekly-settlement.ts
    // This allows us to test the logic independently
    
    // Method 1: Check reportedDays
    if (candidate.reportedDays > 0) {
      // Check if synced before grace expired
      if (candidate.penalty?.last_updated) {
        const lastUpdated = new Date(candidate.penalty.last_updated);
        return lastUpdated.getTime() <= graceDeadline.getTime();
      }
      return true; // Backward compatibility
    }
    
    // Method 2: Check actual_amount_cents (like index.ts)
    if (candidate.penalty && (candidate.penalty.actual_amount_cents ?? 0) > 0) {
      if (candidate.penalty.last_updated) {
        const lastUpdated = new Date(candidate.penalty.last_updated);
        return lastUpdated.getTime() <= graceDeadline.getTime();
      }
      return true;
    }
    
    return false;
  }
  
  /**
   * Simulate isGracePeriodExpired() logic
   */
  static isGracePeriodExpired(
    graceDeadline: Date,
    now: Date
  ): boolean {
    return graceDeadline.getTime() <= now.getTime();
  }
  
  /**
   * Simulate getChargeAmount() logic
   */
  static getChargeAmount(
    chargeType: "actual" | "worst_case",
    actualPenaltyCents: number,
    maxChargeCents: number
  ): number {
    if (chargeType === "actual") {
      return Math.min(actualPenaltyCents, maxChargeCents);
    }
    return maxChargeCents;
  }
  
  /**
   * Predict settlement outcome without running it
   */
  static predictSettlement(
    testCase: TestCase,
    state: {
      reportedDays: number;
      totalPenaltyCents: number;
      lastUpdated?: string;
      graceDeadline: Date;
      now: Date;
      maxChargeCents: number;
    }
  ): {
    willCharge: boolean;
    chargeType: "actual" | "worst_case" | "none";
    amountCents: number;
    status: string;
  } {
    // Check if already settled
    // Check if grace expired
    const graceExpired = this.isGracePeriodExpired(state.graceDeadline, state.now);
    if (!graceExpired) {
      return {
        willCharge: false,
        chargeType: "none",
        amountCents: 0,
        status: "pending",
      };
    }
    
    // Check if usage was synced
    const hasUsage = this.hasSyncedUsage(
      {
        reportedDays: state.reportedDays,
        penalty: {
          last_updated: state.lastUpdated,
          actual_amount_cents: state.totalPenaltyCents,
        },
      },
      state.graceDeadline,
      true // isTestingMode
    );
    
    const chargeType: "actual" | "worst_case" = hasUsage ? "actual" : "worst_case";
    const amountCents = this.getChargeAmount(
      chargeType,
      state.totalPenaltyCents,
      state.maxChargeCents
    );
    
    // Check if amount is zero (skip charge)
    if (amountCents <= 0) {
      return {
        willCharge: false,
        chargeType: "none",
        amountCents: 0,
        status: "pending",
      };
    }
    
    return {
      willCharge: true,
      chargeType,
      amountCents,
      status: chargeType === "actual" ? "charged_actual" : "charged_worst_case",
    };
  }
}
```

### Phase 4: Comprehensive Test Suite

**File**: `supabase/tests/test_settlement_matrix.ts`

```typescript
import { ALL_TEST_CASES, TestCase } from "./helpers/settlement_test_cases.ts";
import { SettlementTestBuilder } from "./helpers/settlement_test_builder.ts";
import { SettlementSimulator } from "./helpers/settlement_simulator.ts";
import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";

/**
 * Test all 24 settlement cases programmatically
 */
Deno.test("Settlement Matrix - All 24 Cases", async (t) => {
  for (const testCase of ALL_TEST_CASES) {
    await t.step(`Case ${testCase.id}: ${testCase.description}`, async () => {
      await testSettlementCase(testCase);
    });
  }
});

async function testSettlementCase(testCase: TestCase): Promise<void> {
  // Setup: Create test environment
  const userId = await createTestUser();
  const weekEndDate = getTestDeadlineDate();
  const commitmentCreatedAt = new Date();
  const graceExpiresAt = new Date(commitmentCreatedAt.getTime() + 60 * 1000); // 1 min grace
  
  // Mock time progression
  let now = new Date(commitmentCreatedAt);
  const builder = new SettlementTestBuilder({
    userId,
    weekEndDate,
    graceExpiresAt,
    now,
  });
  
  // Step 1: Create commitment
  const commitmentId = await builder.createCommitment({
    limitMinutes: testCase.setup.limitMinutes,
    penaltyPerMinuteCents: testCase.setup.penaltyPerMinuteCents,
    maxChargeCents: calculateMaxCharge(testCase.setup),
  });
  
  // Step 2: Sync before grace (if needed)
  if (testCase.setup.syncBeforeGrace) {
    now = new Date(commitmentCreatedAt.getTime() + 30 * 1000); // 30 seconds after
    builder.advanceTime(30 * 1000);
    await builder.syncUsage({
      atTime: now,
      usageMinutes: testCase.setup.usageMinutes,
      limitMinutes: testCase.setup.limitMinutes,
      penaltyPerMinuteCents: testCase.setup.penaltyPerMinuteCents,
    });
  }
  
  // Step 3: Sync within grace (Case 1 only)
  if (testCase.mainCase === 1 && testCase.setup.syncWithinGrace) {
    now = new Date(graceExpiresAt.getTime() - 30 * 1000); // 30 seconds before grace expires
    builder.advanceTime(graceExpiresAt.getTime() - now.getTime());
    await builder.syncUsage({
      atTime: now,
      usageMinutes: testCase.setup.usageMinutes,
      limitMinutes: testCase.setup.limitMinutes,
      penaltyPerMinuteCents: testCase.setup.penaltyPerMinuteCents,
    });
  }
  
  // Step 4: Wait for grace to expire
  now = new Date(graceExpiresAt.getTime() + 10 * 1000); // 10 seconds after grace expires
  builder.advanceTime(10 * 1000);
  
  // Step 5: Run settlement
  const settlementResult = await builder.runSettlement(now);
  
  // Step 6: Verify results
  assertEquals(
    settlementResult.status,
    testCase.expected.settlementStatus,
    `Status mismatch for ${testCase.id}`
  );
  assertEquals(
    settlementResult.chargedAmountCents,
    testCase.expected.chargedAmountCents,
    `Charged amount mismatch for ${testCase.id}`
  );
  assertEquals(
    settlementResult.paymentCount,
    testCase.expected.paymentCount,
    `Payment count mismatch for ${testCase.id}`
  );
  
  // Step 7: Handle Case 3 (late sync)
  if (testCase.mainCase === 3 && testCase.setup.syncAfterGrace) {
    now = new Date(now.getTime() + 60 * 1000); // 1 minute after settlement
    builder.advanceTime(60 * 1000);
    
    await builder.syncUsage({
      atTime: now,
      usageMinutes: testCase.setup.usageMinutes,
      limitMinutes: testCase.setup.limitMinutes,
      penaltyPerMinuteCents: testCase.setup.penaltyPerMinuteCents,
    });
    
    // Run reconciliation
    const reconciliationResult = await builder.runReconciliation(now);
    
    // Verify reconciliation
    assertEquals(
      reconciliationResult.needsReconciliation,
      testCase.expected.needsReconciliation,
      `Reconciliation flag mismatch for ${testCase.id}`
    );
  }
}
```

---

## Code Analysis Approach

### Static Analysis: Predict Outcomes Without Running Tests

**File**: `supabase/tests/analyze_settlement_logic.ts`

```typescript
/**
 * Analyze settlement code to predict outcomes
 * This catches logic errors before running tests
 */
export class SettlementLogicAnalyzer {
  /**
   * Analyze hasSyncedUsage() implementation
   */
  static analyzeHasSyncedUsage(): {
    issues: string[];
    recommendations: string[];
  } {
    const issues: string[] = [];
    const recommendations: string[] = [];
    
    // Check if both implementations exist
    const hasIndexImpl = checkFileExists("bright-service/index.ts", "hasSyncedUsage");
    const hasRunWeeklyImpl = checkFileExists("bright-service/run-weekly-settlement.ts", "hasSyncedUsage");
    
    if (hasIndexImpl && hasRunWeeklyImpl) {
      // Compare implementations
      const indexLogic = extractFunctionLogic("bright-service/index.ts", "hasSyncedUsage");
      const runWeeklyLogic = extractFunctionLogic("bright-service/run-weekly-settlement.ts", "hasSyncedUsage");
      
      if (indexLogic !== runWeeklyLogic) {
        issues.push("hasSyncedUsage() has different implementations in index.ts vs run-weekly-settlement.ts");
        recommendations.push("Unify implementations or document why they differ");
      }
    }
    
    // Check if timing is considered
    if (!runWeeklyLogic.includes("last_updated") && !runWeeklyLogic.includes("grace")) {
      issues.push("hasSyncedUsage() in run-weekly-settlement.ts doesn't check when usage was synced");
      recommendations.push("Add grace period timing check to hasSyncedUsage()");
    }
    
    return { issues, recommendations };
  }
  
  /**
   * Predict outcome for a test case without running it
   */
  static predictOutcome(testCase: TestCase): {
    predicted: SettlementOutcome;
    confidence: "high" | "medium" | "low";
    warnings: string[];
  } {
    // Analyze code paths
    // Predict based on logic flow
    // Return predicted outcome with confidence level
  }
}
```

---

## Benefits of Automated Testing

### 1. **Catch Logic Errors Early**
- Would have caught the `hasSyncedUsage()` mismatch
- Would have identified timing issues
- Would have verified zero-penalty handling

### 2. **Regression Prevention**
- All 24 cases run on every code change
- Prevents breaking existing functionality
- Ensures consistency across cases

### 3. **Documentation**
- Test cases serve as executable documentation
- Shows expected behavior for each scenario
- Makes edge cases explicit

### 4. **Faster Development**
- No need to manually test all 24 cases
- Instant feedback on logic changes
- Can test in CI/CD pipeline

---

## Implementation Priority

### Phase 1: Core Framework (High Priority)
1. ✅ Define all 24 test cases
2. ✅ Create test data builder
3. ✅ Create settlement simulator
4. ✅ Implement basic test runner

### Phase 2: Enhanced Testing (Medium Priority)
1. ⏳ Add time mocking
2. ⏳ Add Stripe mocking
3. ⏳ Add reconciliation testing
4. ⏳ Add edge case testing

### Phase 3: Code Analysis (Low Priority)
1. ⏳ Static code analysis
2. ⏳ Logic flow prediction
3. ⏳ Automated issue detection

---

## Example: How This Would Have Caught Case 1_A_A Failure

```typescript
// Test Case 1_A_A
{
  id: "1_A_A",
  setup: {
    syncBeforeGrace: true,
    syncWithinGrace: true, // ← Key difference
    usageMinutes: 0,
  },
  expected: {
    settlementStatus: "pending",
    chargedAmountCents: 0,
    paymentCount: 0,
  },
}

// When test runs:
// 1. Creates commitment
// 2. Syncs usage before grace (30s after creation)
// 3. Syncs usage within grace (30s before grace expires)
// 4. Waits for grace to expire
// 5. Runs settlement
// 6. Checks: hasSyncedUsage() should return true
// 7. Checks: chargeType should be "actual"
// 8. Checks: amountCents should be 0 (zero penalty)
// 9. Checks: Should skip charge (zeroAmount counter)
// 10. ❌ FAIL: Settlement charged worst case instead

// The test would immediately show:
// ❌ FAIL: Case 1_A_A
//   Expected: settlementStatus = "pending"
//   Actual: settlementStatus = "charged_worst_case"
//   Expected: chargedAmountCents = 0
//   Actual: chargedAmountCents = 500
//   Issue: hasSyncedUsage() returned false when it should return true
```

---

## Next Steps

1. **Create test case definitions** (all 24 cases)
2. **Build test framework** (builder, simulator, runner)
3. **Run all tests** to identify current failures
4. **Fix issues** found by tests
5. **Add to CI/CD** for continuous validation

---

## Conclusion

Yes, we can and should programmatically test all 24 cases. This would have:
- ✅ Caught the `hasSyncedUsage()` logic issue immediately
- ✅ Verified all edge cases (zero penalty, below minimum, etc.)
- ✅ Prevented regression when fixing issues
- ✅ Provided confidence in settlement logic

The investment in automated testing will pay off by catching issues early and preventing manual testing overhead.

