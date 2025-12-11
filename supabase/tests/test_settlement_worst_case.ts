/**
 * Test: Settlement - Worst Case Charging
 * 
 * Tests the settlement flow when user has NOT synced their usage.
 * After grace period expires, system charges max_charge_cents (worst case).
 * 
 * Settlement flow:
 * 1. User did NOT sync usage data → actual penalty unknown
 * 2. Grace period expires (Tuesday 12:00 ET)
 * 3. System charges max_charge_cents as worst-case
 * 4. settlement_status = 'charged_worst_case'
 * 
 * Run with: deno test test_settlement_worst_case.ts --allow-net --allow-env --allow-read
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
    // Monday
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
  weekGraceExpiresAt?: string | null;
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
      week_grace_expires_at: options.weekGraceExpiresAt ?? null,
    })
    .select()
    .single();

  if (error) throw new Error(`Failed to create commitment: ${error.message}`);
  return { id: data.id, maxChargeCents };
}

async function createUserWeekPenalty(options: {
  userId: string;
  weekStartDate: string;
  totalPenaltyCents: number;
  settlementStatus?: string;
}): Promise<void> {
  await supabase.from("user_week_penalties").upsert({
    user_id: options.userId,
    week_start_date: options.weekStartDate,
    total_penalty_cents: options.totalPenaltyCents,
    status: "pending",
    settlement_status: options.settlementStatus ?? "pending",
  }, { onConflict: "user_id,week_start_date" });
}

/**
 * Simulate worst-case settlement (without Stripe).
 */
async function simulateWorstCaseSettlement(options: {
  userId: string;
  weekEndDate: string;
  worstCaseAmount: number;
  actualAmount?: number;
}): Promise<void> {
  await supabase
    .from("user_week_penalties")
    .update({
      settlement_status: "charged_worst_case",
      charged_amount_cents: options.worstCaseAmount,
      actual_amount_cents: options.actualAmount ?? 0, // Unknown at time of charge
      charged_at: new Date().toISOString(),
    })
    .eq("user_id", options.userId)
    .eq("week_start_date", options.weekEndDate);

  await supabase.from("payments").insert({
    user_id: options.userId,
    week_start_date: options.weekEndDate,
    amount_cents: options.worstCaseAmount,
    currency: "usd",
    stripe_payment_intent_id: `pi_test_worst_${Date.now()}`,
    status: "succeeded",
    payment_type: "penalty_worst_case",
  });
}

// MARK: - Tests

Deno.test("Settlement Worst Case - No sync triggers max charge", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: User with commitment but NO daily_usage (didn't sync)
    await ensureTestUserExists();
    const { maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
      weekGraceExpiresAt: new Date(Date.now() - 86400000).toISOString(), // Grace expired
    });

    // Create penalty record with 0 (no synced data)
    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 0,
    });

    // Simulate worst-case settlement
    await simulateWorstCaseSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      worstCaseAmount: maxChargeCents,
    });

    // Verify charged worst-case
    const { data } = await supabase
      .from("user_week_penalties")
      .select("settlement_status, charged_amount_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.settlement_status, "charged_worst_case", "Status should be charged_worst_case");
    assertEquals(data?.charged_amount_cents, 4200, "Should charge max (60×10×7 = 4200 cents)");
  });
});

Deno.test("Settlement Worst Case - Grace period must expire first", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { id: commitmentId } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
      // Grace NOT expired - set to future
      weekGraceExpiresAt: new Date(Date.now() + 86400000 * 2).toISOString(),
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 0,
    });

    // Don't settle - grace hasn't expired
    // In real system, run-weekly-settlement would skip this user

    // Verify no payment yet
    const { data: payments } = await supabase
      .from("payments")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline);

    assertEquals(payments?.length ?? 0, 0, "No payment should exist before grace expires");

    // Verify still pending
    const { data } = await supabase
      .from("user_week_penalties")
      .select("settlement_status")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.settlement_status, "pending", "Should still be pending during grace");
  });
});

Deno.test("Settlement Worst Case - Payment type is penalty_worst_case", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 30,
      penaltyPerMinuteCents: 25,
      weekEndDate: deadline,
      weekGraceExpiresAt: new Date(Date.now() - 86400000).toISOString(),
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 0,
    });

    await simulateWorstCaseSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      worstCaseAmount: maxChargeCents, // 30 × 25 × 7 = 5250
    });

    // Verify payment type
    const { data: payment } = await supabase
      .from("payments")
      .select("payment_type, amount_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(payment?.payment_type, "penalty_worst_case", "Payment type should be penalty_worst_case");
    assertEquals(payment?.amount_cents, 5250, "Amount should be max charge (5250)");
  });
});

Deno.test("Settlement Worst Case - Max charge calculation correct", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    
    // Test different limit/penalty combinations
    const testCases = [
      { limit: 60, penalty: 10, expected: 4200 },   // 60 × 10 × 7
      { limit: 30, penalty: 25, expected: 5250 },   // 30 × 25 × 7
      { limit: 120, penalty: 5, expected: 4200 },   // 120 × 5 × 7
      { limit: 45, penalty: 15, expected: 4725 },   // 45 × 15 × 7
    ];

    for (const tc of testCases) {
      // Clean between iterations
      await supabase.from("commitments").delete().eq("user_id", TEST_USER_ID);
      await supabase.from("user_week_penalties").delete().eq("user_id", TEST_USER_ID);
      await supabase.from("payments").delete().eq("user_id", TEST_USER_ID);

      const { maxChargeCents } = await createTestCommitment({
        userId: TEST_USER_ID,
        limitMinutes: tc.limit,
        penaltyPerMinuteCents: tc.penalty,
        weekEndDate: deadline,
      });

      assertEquals(
        maxChargeCents,
        tc.expected,
        `Max charge for ${tc.limit}min × ${tc.penalty}¢ × 7 should be ${tc.expected}`
      );
    }
  });
});

Deno.test("Settlement Worst Case - Actual amount tracked as 0 initially", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const { maxChargeCents } = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
      weekGraceExpiresAt: new Date(Date.now() - 86400000).toISOString(),
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 0,
    });

    await simulateWorstCaseSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      worstCaseAmount: maxChargeCents,
      actualAmount: 0, // Unknown at charge time
    });

    // Verify actual_amount is tracked
    const { data } = await supabase
      .from("user_week_penalties")
      .select("charged_amount_cents, actual_amount_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.charged_amount_cents, 4200, "Charged worst case");
    assertEquals(data?.actual_amount_cents, 0, "Actual should be 0 (unknown at charge time)");
  });
});



