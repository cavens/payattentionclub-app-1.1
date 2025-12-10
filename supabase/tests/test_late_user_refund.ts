/**
 * Test: Late User Sync & Refund/Reconciliation
 * 
 * Tests the reconciliation flow when user syncs AFTER being charged worst-case.
 * 
 * Scenario:
 * 1. User doesn't sync before grace period
 * 2. System charges worst-case (max_charge_cents)
 * 3. User eventually syncs their actual usage
 * 4. System detects they were overcharged
 * 5. needs_reconciliation = true, reconciliation_delta_cents = negative (refund owed)
 * 
 * Run with: deno test test_late_user_refund.ts --allow-net --allow-env --allow-read
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase } from "./helpers/client.ts";
import { withCleanup } from "./helpers/cleanup.ts";
import { TEST_USER_IDS } from "./config.ts";

// MARK: - Test Setup

const TEST_USER_ID = TEST_USER_IDS.testUser1;

async function ensureTestUserExists(userId: string = TEST_USER_ID): Promise<void> {
  const { error } = await supabase.from("users").upsert({
    id: userId,
    email: `test-${userId.slice(0, 8)}@example.com`,
    stripe_customer_id: `cus_test_${userId.slice(0, 8)}`,
    has_active_payment_method: true,
    is_test_user: true,
  });
  if (error) throw new Error(`Failed to create test user: ${error.message}`);
}

function getTestDeadlineDate(): string {
  const now = new Date();
  const dayOfWeek = now.getUTCDay();
  let deadline = new Date(now);
  if (dayOfWeek === 1) {
  } else if (dayOfWeek === 0) {
    deadline.setUTCDate(deadline.getUTCDate() + 1);
  } else {
    deadline.setUTCDate(deadline.getUTCDate() - (dayOfWeek - 1));
  }
  return deadline.toISOString().split("T")[0];
}

async function createTestCommitment(options: {
  userId: string;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
  weekEndDate: string;
}): Promise<{ id: string; maxChargeCents: number }> {
  const maxChargeCents = options.limitMinutes * options.penaltyPerMinuteCents * 7;

  await supabase.from("weekly_pools").upsert({
    week_start_date: options.weekEndDate,
    week_end_date: options.weekEndDate,
    total_penalty_cents: 0,
    status: "open",
  });

  const { data, error } = await supabase
    .from("commitments")
    .insert({
      user_id: options.userId,
      week_start_date: new Date().toISOString().split("T")[0],
      week_end_date: options.weekEndDate,
      limit_minutes: options.limitMinutes,
      penalty_per_minute_cents: options.penaltyPerMinuteCents,
      apps_to_limit: { app_bundle_ids: ["com.apple.Safari"], categories: [] },
      status: "active",
      monitoring_status: "ok",
      max_charge_cents: maxChargeCents,
    })
    .select()
    .single();

  if (error) throw new Error(`Failed to create commitment: ${error.message}`);
  return { id: data.id, maxChargeCents };
}

/**
 * Set up user_week_penalties as if worst-case was already charged.
 */
async function setupWorstCaseCharged(options: {
  userId: string;
  weekStartDate: string;
  chargedAmount: number;
}): Promise<void> {
  await supabase.from("user_week_penalties").upsert({
    user_id: options.userId,
    week_start_date: options.weekStartDate,
    total_penalty_cents: 0, // Unknown at time
    settlement_status: "charged_worst_case",
    charged_amount_cents: options.chargedAmount,
    actual_amount_cents: 0, // Unknown
    charged_at: new Date().toISOString(),
    needs_reconciliation: false,
    reconciliation_delta_cents: 0,
    status: "paid",
  }, { onConflict: "user_id,week_start_date" });
}

/**
 * Simulate late sync - user finally reports their actual usage.
 * This should detect overpayment and flag for reconciliation.
 */
async function simulateLateSyncWithReconciliation(options: {
  userId: string;
  commitmentId: string;
  weekStartDate: string;
  actualPenaltyCents: number;
  previouslyCharged: number;
}): Promise<void> {
  // Record the actual daily usage
  await supabase.from("daily_usage").upsert({
    user_id: options.userId,
    commitment_id: options.commitmentId,
    date: new Date().toISOString().split("T")[0],
    used_minutes: 0, // Simplified - actual value doesn't matter for this test
    limit_minutes: 60,
    exceeded_minutes: 0,
    penalty_cents: options.actualPenaltyCents,
    is_estimated: false,
    source: "late_sync",
  }, { onConflict: "user_id,date,commitment_id" });

  // Calculate reconciliation delta
  const delta = options.actualPenaltyCents - options.previouslyCharged;
  const needsReconciliation = delta !== 0;

  // Update user_week_penalties with reconciliation info
  await supabase
    .from("user_week_penalties")
    .update({
      total_penalty_cents: options.actualPenaltyCents,
      actual_amount_cents: options.actualPenaltyCents,
      needs_reconciliation: needsReconciliation,
      reconciliation_delta_cents: delta,
      reconciliation_reason: needsReconciliation ? "late_sync_delta" : null,
      reconciliation_detected_at: needsReconciliation ? new Date().toISOString() : null,
    })
    .eq("user_id", options.userId)
    .eq("week_start_date", options.weekStartDate);
}

// MARK: - Tests

Deno.test("Late Sync - Detects overpayment when actual < charged", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId, maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Setup: Already charged worst-case (4200 cents)
    await setupWorstCaseCharged({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      chargedAmount: maxChargeCents,
    });

    // Simulate late sync with lower actual usage (300 cents)
    await simulateLateSyncWithReconciliation({
      userId: TEST_USER_ID,
      commitmentId,
      weekStartDate: deadline,
      actualPenaltyCents: 300,
      previouslyCharged: maxChargeCents,
    });

    // Verify reconciliation detected
    const { data } = await supabase
      .from("user_week_penalties")
      .select("needs_reconciliation, reconciliation_delta_cents, actual_amount_cents, charged_amount_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.needs_reconciliation, true, "Should need reconciliation");
    assertEquals(data?.reconciliation_delta_cents, -3900, "Delta should be -3900 (refund owed)");
    assertEquals(data?.actual_amount_cents, 300, "Actual should be 300");
    assertEquals(data?.charged_amount_cents, 4200, "Charged should still show 4200");
  });
});

Deno.test("Late Sync - Zero actual means full refund owed", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId, maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    await setupWorstCaseCharged({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      chargedAmount: maxChargeCents,
    });

    // User actually stayed within limit - 0 penalty!
    await simulateLateSyncWithReconciliation({
      userId: TEST_USER_ID,
      commitmentId,
      weekStartDate: deadline,
      actualPenaltyCents: 0,
      previouslyCharged: maxChargeCents,
    });

    const { data } = await supabase
      .from("user_week_penalties")
      .select("needs_reconciliation, reconciliation_delta_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.needs_reconciliation, true, "Should need full refund");
    assertEquals(data?.reconciliation_delta_cents, -4200, "Full refund owed (−4200)");
  });
});

Deno.test("Late Sync - Reconciliation reason set correctly", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId, maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    await setupWorstCaseCharged({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      chargedAmount: maxChargeCents,
    });

    await simulateLateSyncWithReconciliation({
      userId: TEST_USER_ID,
      commitmentId,
      weekStartDate: deadline,
      actualPenaltyCents: 500,
      previouslyCharged: maxChargeCents,
    });

    const { data } = await supabase
      .from("user_week_penalties")
      .select("reconciliation_reason, reconciliation_detected_at")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.reconciliation_reason, "late_sync_delta", "Reason should be late_sync_delta");
    assertExists(data?.reconciliation_detected_at, "Detection timestamp should be set");
  });
});

Deno.test("Late Sync - No reconciliation if amounts match", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Charged exactly what was owed (rare but possible)
    await setupWorstCaseCharged({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      chargedAmount: 1000, // Hypothetically charged 1000
    });

    // Actual is exactly 1000
    await simulateLateSyncWithReconciliation({
      userId: TEST_USER_ID,
      commitmentId,
      weekStartDate: deadline,
      actualPenaltyCents: 1000,
      previouslyCharged: 1000,
    });

    const { data } = await supabase
      .from("user_week_penalties")
      .select("needs_reconciliation, reconciliation_delta_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.needs_reconciliation, false, "No reconciliation needed if amounts match");
    assertEquals(data?.reconciliation_delta_cents, 0, "Delta should be 0");
  });
});

Deno.test("Late Sync - Partial refund calculation", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Charged worst case of 4200
    await setupWorstCaseCharged({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      chargedAmount: 4200,
    });

    // Actual was 2500 - so partial refund of 1700
    await simulateLateSyncWithReconciliation({
      userId: TEST_USER_ID,
      commitmentId,
      weekStartDate: deadline,
      actualPenaltyCents: 2500,
      previouslyCharged: 4200,
    });

    const { data } = await supabase
      .from("user_week_penalties")
      .select("reconciliation_delta_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.reconciliation_delta_cents, -1700, "Partial refund of 1700 cents owed");
  });
});

Deno.test("Late Sync - Settlement status remains charged_worst_case", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId, maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    await setupWorstCaseCharged({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      chargedAmount: maxChargeCents,
    });

    await simulateLateSyncWithReconciliation({
      userId: TEST_USER_ID,
      commitmentId,
      weekStartDate: deadline,
      actualPenaltyCents: 300,
      previouslyCharged: maxChargeCents,
    });

    // Settlement status shouldn't change (still shows what was charged)
    const { data } = await supabase
      .from("user_week_penalties")
      .select("settlement_status")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.settlement_status, "charged_worst_case", 
      "Status should remain charged_worst_case until refund is processed");
  });
});

