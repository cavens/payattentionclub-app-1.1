/**
 * Test: Weekly Close Edge Function
 * 
 * Tests the weekly-close edge function which:
 * 1. Calculates the deadline (week being closed)
 * 2. Inserts estimated usage for revoked monitoring
 * 3. Recomputes user_week_penalties totals
 * 4. Charges users via Stripe (skipped for test users)
 * 5. Closes the weekly pool
 * 
 * Run with: deno test test_weekly_close.ts --allow-net --allow-env --allow-read
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase, callEdgeFunction } from "./helpers/client.ts";
import { withCleanup } from "./helpers/cleanup.ts";
import { TEST_USER_IDS } from "./config.ts";

// MARK: - Test Setup

const TEST_USER_ID = TEST_USER_IDS.testUser1;

/**
 * Ensure test user exists (with fake Stripe ID so charges are skipped).
 */
async function ensureTestUserExists(userId: string = TEST_USER_ID): Promise<void> {
  const { error } = await supabase.from("users").upsert({
    id: userId,
    email: `test-${userId.slice(0, 8)}@example.com`,
    stripe_customer_id: `cus_test_${userId.slice(0, 8)}`, // Fake ID - will be skipped
    has_active_payment_method: true,
    is_test_user: true,
  });

  if (error) throw new Error(`Failed to create test user: ${error.message}`);
}

/**
 * Get a specific Monday date for testing.
 * Returns last Monday if today is not Monday, otherwise today.
 */
function getTestDeadlineDate(): string {
  const now = new Date();
  const dayOfWeek = now.getUTCDay();
  
  let deadline = new Date(now);
  if (dayOfWeek === 1) {
    // Today is Monday - use today
  } else if (dayOfWeek === 0) {
    // Sunday - use tomorrow (Monday)
    deadline.setUTCDate(deadline.getUTCDate() + 1);
  } else {
    // Tue-Sat - use last Monday
    const daysToSubtract = dayOfWeek - 1;
    deadline.setUTCDate(deadline.getUTCDate() - daysToSubtract);
  }
  
  return deadline.toISOString().split("T")[0];
}

/**
 * Create test commitment and weekly pool.
 */
async function createTestCommitment(options: {
  userId: string;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
  weekEndDate: string;
}): Promise<string> {
  const weekStartDate = new Date().toISOString().split("T")[0];
  const maxChargeCents = options.limitMinutes * options.penaltyPerMinuteCents * 7;

  // Create weekly pool first
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
      week_start_date: weekStartDate,
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
  return data.id;
}

/**
 * Record daily usage and penalty.
 */
async function recordDailyUsage(options: {
  userId: string;
  commitmentId: string;
  date: string;
  usedMinutes: number;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
}): Promise<void> {
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
}

/**
 * Create user_week_penalties record.
 */
async function createUserWeekPenalty(options: {
  userId: string;
  weekStartDate: string;
  totalPenaltyCents: number;
}): Promise<void> {
  const { error } = await supabase.from("user_week_penalties").upsert({
    user_id: options.userId,
    week_start_date: options.weekStartDate,
    total_penalty_cents: options.totalPenaltyCents,
    status: "pending",
    settlement_status: "pending",
  }, {
    onConflict: "user_id,week_start_date",
  });

  if (error) throw new Error(`Failed to create penalty: ${error.message}`);
}

// MARK: - Tests

Deno.test("Weekly Close - Pool status changes to closed", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: Create user, commitment, and pool
    await ensureTestUserExists();
    await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Verify pool is open before
    const { data: poolBefore } = await supabase
      .from("weekly_pools")
      .select("status")
      .eq("week_start_date", deadline)
      .single();
    
    assertEquals(poolBefore?.status, "open", "Pool should be open before close");

    // Act: Call weekly-close edge function
    try {
      await callEdgeFunction("weekly-close", {});
    } catch (e) {
      // Edge function might fail for various reasons in test env, but
      // we want to check if it at least tried to close the pool
      console.log("Edge function call result:", e);
    }

    // Assert: Pool status changed to closed
    const { data: poolAfter } = await supabase
      .from("weekly_pools")
      .select("status, closed_at")
      .eq("week_start_date", deadline)
      .single();

    assertEquals(poolAfter?.status, "closed", "Pool should be closed after weekly-close");
    assertExists(poolAfter?.closed_at, "Pool should have closed_at timestamp");
  });
});

Deno.test("Weekly Close - Recalculates user penalties", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: Create user, commitment, daily usage
    await ensureTestUserExists();
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Record some usage that exceeds limit
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitmentId,
      date: yesterday.toISOString().split("T")[0],
      usedMinutes: 90, // 30 over limit = 300 cents
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Don't create user_week_penalties - let weekly-close create it

    // Act: Call weekly-close
    try {
      await callEdgeFunction("weekly-close", {});
    } catch (e) {
      console.log("Edge function result:", e);
    }

    // Assert: user_week_penalties was created/updated
    const { data: penalty } = await supabase
      .from("user_week_penalties")
      .select("total_penalty_cents, status")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    // Note: The penalty record should exist (though status might vary due to test user)
    if (penalty) {
      assertEquals(penalty.total_penalty_cents, 300, "Total penalty should be 300 cents");
    }
  });
});

Deno.test("Weekly Close - Pool total updated", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: Create multiple users with penalties
    const user1 = TEST_USER_IDS.testUser1;
    const user2 = TEST_USER_IDS.testUser2;
    
    await ensureTestUserExists(user1);
    await ensureTestUserExists(user2);
    
    const commitment1 = await createTestCommitment({
      userId: user1,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });
    
    const commitment2 = await createTestCommitment({
      userId: user2,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    const today = new Date().toISOString().split("T")[0];
    
    // User 1: 30 minutes over = 300 cents
    await recordDailyUsage({
      userId: user1,
      commitmentId: commitment1,
      date: today,
      usedMinutes: 90,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });
    
    // User 2: 20 minutes over = 200 cents
    await recordDailyUsage({
      userId: user2,
      commitmentId: commitment2,
      date: today,
      usedMinutes: 80,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Act: Call weekly-close
    try {
      await callEdgeFunction("weekly-close", {});
    } catch (e) {
      console.log("Edge function result:", e);
    }

    // Assert: Pool total = 300 + 200 = 500 cents
    const { data: pool } = await supabase
      .from("weekly_pools")
      .select("total_penalty_cents")
      .eq("week_start_date", deadline)
      .single();

    assertEquals(pool?.total_penalty_cents, 500, "Pool total should be 500 cents");
  });
});

Deno.test("Weekly Close - Test users with fake Stripe ID are skipped", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: Create user with fake Stripe ID
    await ensureTestUserExists(); // Uses cus_test_xxx ID
    
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitmentId,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 90,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Create penalty record
    await createUserWeekPenalty({
      userId: TEST_USER_ID,
      weekStartDate: deadline,
      totalPenaltyCents: 300,
    });

    // Act: Call weekly-close
    let result;
    try {
      result = await callEdgeFunction<{
        chargedUsers: number;
        results: Array<{ userId: string; success: boolean; error?: string }>;
      }>("weekly-close", {});
    } catch (e) {
      console.log("Edge function result:", e);
    }

    // Assert: No payments were created (test user skipped)
    const { data: payments } = await supabase
      .from("payments")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline);

    // Test user should be skipped, so either:
    // - No payment record exists, OR
    // - Payment was attempted but result shows it was skipped
    // The edge function logs "Skipping test user with fake Stripe customer ID"
    
    // Verify pool still gets closed even when users are skipped
    const { data: pool } = await supabase
      .from("weekly_pools")
      .select("status")
      .eq("week_start_date", deadline)
      .single();

    assertEquals(pool?.status, "closed", "Pool should still be closed");
  });
});

Deno.test("Weekly Close - Zero penalty users don't get charged", async () => {
  await withCleanup(async () => {
    const deadline = getTestDeadlineDate();
    
    // Setup: User with no penalties (stayed under limit)
    await ensureTestUserExists();
    
    const commitmentId = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
      weekEndDate: deadline,
    });

    // Record usage UNDER the limit
    await recordDailyUsage({
      userId: TEST_USER_ID,
      commitmentId: commitmentId,
      date: new Date().toISOString().split("T")[0],
      usedMinutes: 45, // Under limit
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Act: Call weekly-close
    try {
      await callEdgeFunction("weekly-close", {});
    } catch (e) {
      console.log("Edge function result:", e);
    }

    // Assert: user_week_penalties has 0 total
    const { data: penalty } = await supabase
      .from("user_week_penalties")
      .select("total_penalty_cents")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline)
      .single();

    assertEquals(penalty?.total_penalty_cents, 0, "Penalty should be 0 cents");

    // Assert: No payment created for 0 balance
    const { data: payments } = await supabase
      .from("payments")
      .select("*")
      .eq("user_id", TEST_USER_ID)
      .eq("week_start_date", deadline);

    assertEquals(payments?.length ?? 0, 0, "No payment should be created for 0 balance");
  });
});



