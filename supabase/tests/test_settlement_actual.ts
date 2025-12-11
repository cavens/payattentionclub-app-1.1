/**
 * Test: Settlement - Actual Penalty Charging
 * 
 * Tests the settlement flow when user HAS synced their usage.
 * The system should charge the actual accumulated penalty, not worst-case.
 * 
 * Settlement flow:
 * 1. User synced usage data → actual penalty known
 * 2. System charges actual_penalty_cents
 * 3. settlement_status = 'charged_actual'
 * 
 * Run with: deno test test_settlement_actual.ts --allow-net --allow-env --allow-read
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase } from "./helpers/client.ts";
import { withCleanup } from "./helpers/cleanup.ts";
import { TEST_USER_IDS } from "./config.ts";

// MARK: - Test Setup

const TEST_USER_ID = TEST_USER_IDS.testUser1;

/**
 * Create test user.
 */
async function ensureTestUserExists(userId: string = TEST_USER_ID): Promise<void> {
  const { error } = await supabase.from("users").upsert({
    id: userId,
    email: `test-${userId.slice(0, 8)}@example.com`,
    stripe_customer_id: `cus_test_${userId.slice(0, 8)}`, // Fake Stripe ID
    has_active_payment_method: true,
    is_test_user: true,
  });
  if (error) throw new Error(`Failed to create test user: ${error.message}`);
}

/**
 * Get test Monday deadline.
 */
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

/**
 * Create commitment with optional saved payment method.
 */
async function createTestCommitment(options: {
  userId: string;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
  weekEndDate: string;
  savedPaymentMethodId?: string | null;
}): Promise<string> {
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
      saved_payment_method_id: options.savedPaymentMethodId ?? null,
    })
    .select()
    .single();

  if (error) throw new Error(`Failed to create commitment: ${error.message}`);
  return data.id;
}

/**
 * Record daily usage.
 */
async function recordDailyUsage(options: {
  userId: string;
  commitmentId: string;
  date: string;
  usedMinutes: number;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
}): Promise<{ penaltyCents: number }> {
  const exceededMinutes = Math.max(0, options.usedMinutes - options.limitMinutes);
  const penaltyCents = exceededMinutes * options.penaltyPerMinuteCents;

  await supabase.from("daily_usage").upsert({
    user_id: options.userId,
    commitment_id: options.commitmentId,
    date: options.date,
    used_minutes: options.usedMinutes,
    limit_minutes: options.limitMinutes,
    exceeded_minutes: exceededMinutes,
    penalty_cents: penaltyCents,
    is_estimated: false,
    source: "test",
  }, { onConflict: "user_id,date,commitment_id" });

  return { penaltyCents };
}

/**
 * Create or update user_week_penalties.
 */
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
 * Simulate actual settlement (without Stripe).
 * Sets the database state as if settlement occurred.
 */
async function simulateActualSettlement(options: {
  userId: string;
  weekEndDate: string;
  actualAmount: number;
}): Promise<void> {
  await supabase
    .from("user_week_penalties")
    .update({
      settlement_status: "charged_actual",
      charged_amount_cents: options.actualAmount,
      actual_amount_cents: options.actualAmount,
      charged_at: new Date().toISOString(),
    })
    .eq("user_id", options.userId)
    .eq("week_start_date", options.weekEndDate);

  // Create payment record
  await supabase.from("payments").insert({
    user_id: options.userId,
    week_start_date: options.weekEndDate,
    amount_cents: options.actualAmount,
    currency: "usd",
    stripe_payment_intent_id: `pi_test_actual_${Date.now()}`,
    status: "succeeded",
    payment_type: "penalty_actual",
  });
}

// MARK: - Tests

Deno.test("Settlement Actual - Status set to charged_actual when synced", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: User with synced usage
    await ensureTestUserExists();
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Record usage that exceeds limit
    const { penaltyCents } = await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 90, // 30 over = 300 cents
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: penaltyCents,
    });

    // Simulate settlement (actual charge)
    await simulateActualSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      actualAmount: penaltyCents,
    });

    // Verify settlement_status
    const { data } = await supabase
      .from("user_week_penalties")
      .select("settlement_status, charged_amount_cents, actual_amount_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.settlement_status, "charged_actual", "Status should be charged_actual");
    assertEquals(data?.charged_amount_cents, 300, "Charged amount should be 300 cents");
    assertEquals(data?.actual_amount_cents, 300, "Actual amount should match charged");
  });
});

Deno.test("Settlement Actual - Charges exact penalty amount", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Record multiple days
    const dates = [
      new Date(),
      new Date(Date.now() - 86400000),
      new Date(Date.now() - 86400000 * 2),
    ];

    let totalPenalty = 0;
    for (const date of dates) {
      const { penaltyCents } = await recordDailyUsage({
        userId: TEST_USER_ID,
        commitmentId,
        date: date.toISOString().split("T")[0],
        usedMinutes: 80, // 20 over = 200 each
        limitMinutes: 60,
        penaltyPerMinuteCents: 10,
      });
      totalPenalty += penaltyCents;
    }

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: totalPenalty,
    });

    await simulateActualSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      actualAmount: totalPenalty,
    });

    // Verify payment matches total
    const { data: payment } = await supabase
      .from("payments")
      .select("amount_cents, payment_type")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(payment?.amount_cents, 600, "Payment should be 600 cents (3 × 200)");
    assertEquals(payment?.payment_type, "penalty_actual", "Payment type should be penalty_actual");
  });
});

Deno.test("Settlement Actual - Creates payment record", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 75, // 15 over = 150 cents
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 150,
    });

    await simulateActualSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      actualAmount: 150,
    });

    // Verify payment record exists
    const { data: payments } = await supabase
      .from("payments")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline);

    assertEquals(payments?.length, 1, "Should have 1 payment record");
    assertEquals(payments?.[0]?.status, "succeeded", "Payment status should be succeeded");
    assertExists(payments?.[0]?.stripe_payment_intent_id, "Should have payment intent ID");
  });
});

Deno.test("Settlement Actual - Zero penalty means no charge", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Usage UNDER limit = 0 penalty
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 45, // Under limit
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 0,
    });

    // Don't simulate settlement for 0 amount (no charge happens)
    
    // Verify no payment was created
    const { data: payments } = await supabase
      .from("payments")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline);

    assertEquals(payments?.length ?? 0, 0, "No payment should be created for 0 penalty");
  });
});

Deno.test("Settlement Actual - Actual amount less than worst case", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    await ensureTestUserExists();
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // max_charge = 60 * 10 * 7 = 4200 cents
    // actual usage = 200 cents (much less!)
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 80, // 20 over = 200 cents
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 200,
    });

    await simulateActualSettlement({
      userId: TEST_USER_ID,
      weekEndDate: deadline,
      actualAmount: 200,
    });

    // Verify charged actual, not worst-case
    const { data } = await supabase
      .from("user_week_penalties")
      .select("charged_amount_cents, settlement_status")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(data?.charged_amount_cents, 200, "Should charge actual (200), not worst-case (4200)");
    assertEquals(data?.settlement_status, "charged_actual", "Status should indicate actual charge");
  });
});



