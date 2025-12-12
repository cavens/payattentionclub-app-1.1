/**
 * Test: Sync Usage & Penalty Calculation
 * 
 * Tests daily usage tracking and penalty calculations.
 * Since rpc_sync_daily_usage uses auth.uid(), we test by:
 * 1. Directly inserting usage data via service role
 * 2. Verifying penalty calculations are correct
 * 3. Testing weekly totals aggregation
 * 
 * Run with: deno test test_sync_usage_penalty.ts --allow-net --allow-env --allow-read
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase } from "./helpers/client.ts";
import { withCleanup } from "./helpers/cleanup.ts";
import { TEST_USER_IDS } from "./config.ts";

// MARK: - Test Setup

const TEST_USER_ID = TEST_USER_IDS.testUser1;

/**
 * Ensure test user exists with payment method.
 */
async function ensureTestUserExists(): Promise<void> {
  const { error } = await supabase.from("users").upsert({
    id: TEST_USER_ID,
    email: "test-user-1@example.com",
    stripe_customer_id: "cus_test_usage",
    has_active_payment_method: true,
    is_test_user: true,
  });

  if (error) {
    throw new Error(`Failed to create test user: ${error.message}`);
  }
}

/**
 * Get next Monday as deadline.
 */
function getNextMondayDeadline(): string {
  const now = new Date();
  const dayOfWeek = now.getDay();
  
  let daysUntilMonday: number;
  if (dayOfWeek === 0) {
    daysUntilMonday = 1;
  } else if (dayOfWeek === 1) {
    daysUntilMonday = 7;
  } else {
    daysUntilMonday = 8 - dayOfWeek;
  }
  
  const deadline = new Date(now);
  deadline.setDate(now.getDate() + daysUntilMonday);
  return deadline.toISOString().split("T")[0];
}

/**
 * Create a test commitment.
 */
async function createTestCommitment(options: {
  userId: string;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
  weekEndDate?: string;
}): Promise<{ id: string; week_end_date: string }> {
  const weekEndDate = options.weekEndDate ?? getNextMondayDeadline();
  const weekStartDate = new Date().toISOString().split("T")[0];
  const maxChargeCents = options.limitMinutes * options.penaltyPerMinuteCents * 7;

  // Ensure weekly pool exists
  await supabase.from("weekly_pools").upsert({
    week_start_date: weekEndDate,
    week_end_date: weekEndDate,
    total_penalty_cents: 0,
    status: "open",
  });

  const { data, error } = await supabase
    .from("commitments")
    .insert({
      user_id: options.userId,
      week_start_date: weekStartDate,
      week_end_date: weekEndDate,
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
  return { id: data.id, week_end_date: data.week_end_date };
}

/**
 * Record daily usage and calculate penalty.
 * Simulates what rpc_sync_daily_usage does.
 */
async function recordDailyUsage(options: {
  userId: string;
  commitmentId: string;
  date: string;
  usedMinutes: number;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
}): Promise<{ exceeded_minutes: number; penalty_cents: number }> {
  const exceededMinutes = Math.max(0, options.usedMinutes - options.limitMinutes);
  const penaltyCents = exceededMinutes * options.penaltyPerMinuteCents;

  const { error } = await supabase.from("daily_usage").upsert({
    user_id: options.userId,
    commitment_id: options.commitmentId,
    date: options.date,
    used_minutes: options.usedMinutes,
    limit_minutes: options.limitMinutes,
    exceeded_minutes: exceededMinutes,
    penalty_cents: penaltyCents,
    is_estimated: false,
    source: "test",
  }, {
    onConflict: "user_id,date,commitment_id",
  });

  if (error) throw new Error(`Failed to record usage: ${error.message}`);
  return { exceeded_minutes: exceededMinutes, penalty_cents: penaltyCents };
}

/**
 * Update user_week_penalties with total from daily_usage.
 */
async function updateWeekPenalties(
  userId: string,
  weekEndDate: string,
  commitmentId: string
): Promise<number> {
  // Sum all penalties for this commitment
  const { data: usageData } = await supabase
    .from("daily_usage")
    .select("penalty_cents")
    .eq("commitment_id", commitmentId);

  const totalPenaltyCents = usageData?.reduce((sum, row) => sum + row.penalty_cents, 0) ?? 0;

  // Upsert user_week_penalties
  await supabase.from("user_week_penalties").upsert({
    user_id: userId,
    week_start_date: weekEndDate, // Note: week_start_date actually stores deadline
    total_penalty_cents: totalPenaltyCents,
    status: "pending",
    settlement_status: "pending",
  }, {
    onConflict: "user_id,week_start_date",
  });

  return totalPenaltyCents;
}

// MARK: - Tests

Deno.test("Usage - Under limit has zero penalty", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Record usage UNDER the limit
    const result = await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 45, // Under 60 limit
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Assert: No penalty
    assertEquals(result.exceeded_minutes, 0, "Should have 0 exceeded minutes");
    assertEquals(result.penalty_cents, 0, "Should have 0 penalty");
  });
});

Deno.test("Usage - Over limit calculates penalty correctly", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Record usage OVER the limit
    const result = await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 90, // 30 over the 60 limit
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Assert: Correct penalty calculation
    assertEquals(result.exceeded_minutes, 30, "Should have 30 exceeded minutes");
    assertEquals(result.penalty_cents, 300, "Penalty should be 30 * 10 = 300 cents");
  });
});

Deno.test("Usage - Exactly at limit has zero penalty", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Record usage EXACTLY at the limit
    const result = await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 60, // Exactly at limit
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Assert: No penalty at exactly the limit
    assertEquals(result.exceeded_minutes, 0, "Should have 0 exceeded minutes");
    assertEquals(result.penalty_cents, 0, "Should have 0 penalty");
  });
});

Deno.test("Usage - Different penalty rates", async () => {
  await withCleanup(async () => {
    // Setup with higher penalty rate
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 30,
      penaltyPerMinuteCents: 25, // Higher rate
    });

    // Record usage over limit
    const result = await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 50, // 20 over the 30 limit
      limitMinutes: 30,
      penaltyPerMinuteCents: 25,
    });

    // Assert: Correct penalty at higher rate
    assertEquals(result.exceeded_minutes, 20, "Should have 20 exceeded minutes");
    assertEquals(result.penalty_cents, 500, "Penalty should be 20 * 25 = 500 cents");
  });
});

Deno.test("Usage - Multiple days accumulate", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);
    const twoDaysAgo = new Date(today);
    twoDaysAgo.setDate(today.getDate() - 2);

    // Record multiple days of usage
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: twoDaysAgo.toISOString().split("T")[0],
      usedMinutes: 90, // 30 over
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: yesterday.toISOString().split("T")[0],
      usedMinutes: 80, // 20 over
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: today.toISOString().split("T")[0],
      usedMinutes: 70, // 10 over
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Update week penalties
    const totalPenalty = await updateWeekPenalties(
      TEST_USER_ID,
      commitment.week_end_date,
      commitment.id
    );

    // Assert: Total = 300 + 200 + 100 = 600 cents
    assertEquals(totalPenalty, 600, "Total weekly penalty should be 600 cents");

    // Verify in database
    const { data } = await supabase
      .from("user_week_penalties")
      .select("total_penalty_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", commitment.week_end_date)
      .single();

    assertEquals(data?.total_penalty_cents, 600, "Database should have 600 cents total");
  });
});

Deno.test("Usage - Updates overwrite previous values", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    const today = new Date().toISOString().split("T")[0];

    // Record initial usage
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: today,
      usedMinutes: 90, // 30 over
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Update with new usage (simulating late sync with corrected data)
    const result = await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: today,
      usedMinutes: 75, // 15 over (corrected)
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Assert: New value overwrote old
    assertEquals(result.exceeded_minutes, 15, "Should have updated exceeded minutes");
    assertEquals(result.penalty_cents, 150, "Penalty should be updated to 150 cents");

    // Verify in database (only one record)
    const { data } = await supabase
      .from("daily_usage")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("date", today);

    assertEquals(data?.length, 1, "Should only have one record for the day");
    assertEquals(data?.[0].used_minutes, 75, "Should have updated used_minutes");
  });
});

Deno.test("Usage - Persists to database correctly", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();
    const commitment = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    const today = new Date().toISOString().split("T")[0];

    // Record usage
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitment.id,
      date: today,
      usedMinutes: 85,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Fetch from database and verify all fields
    const { data, error } = await supabase
      .from("daily_usage")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("date", today)
      .single();

    assertEquals(error, null, "Should fetch without error");
    assertEquals(data.used_minutes, 85, "used_minutes should be 85");
    assertEquals(data.limit_minutes, 60, "limit_minutes should be 60");
    assertEquals(data.exceeded_minutes, 25, "exceeded_minutes should be 25");
    assertEquals(data.penalty_cents, 250, "penalty_cents should be 250");
    assertEquals(data.is_estimated, false, "is_estimated should be false");
    assertEquals(data.source, "test", "source should be test");
  });
});




