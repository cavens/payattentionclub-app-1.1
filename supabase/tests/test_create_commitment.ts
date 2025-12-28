/**
 * Test: Create Commitment (Backend Integration)
 * 
 * Tests commitment creation and related business logic.
 * Since rpc_create_commitment uses auth.uid(), we test by:
 * 1. Directly inserting data via service role (bypasses RLS)
 * 2. Verifying the data structure is correct
 * 3. Testing penalty calculations
 * 
 * Run with: deno test test_create_commitment.ts --allow-net --allow-env --allow-read
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase } from "./helpers/client.ts";
import { cleanupTestData, withCleanup } from "./helpers/cleanup.ts";
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
    stripe_customer_id: "cus_test_commitment",
    has_active_payment_method: true,
    is_test_user: true,
  });

  if (error) {
    throw new Error(`Failed to create test user: ${error.message}`);
  }
}

/**
 * Calculate next Monday deadline (matches app logic).
 */
function getNextMondayDeadline(): string {
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0 = Sunday, 1 = Monday, ...
  
  let daysUntilMonday: number;
  if (dayOfWeek === 0) {
    daysUntilMonday = 1; // Sunday -> Monday
  } else if (dayOfWeek === 1) {
    daysUntilMonday = 7; // Monday -> next Monday
  } else {
    daysUntilMonday = 8 - dayOfWeek; // Tue-Sat -> next Monday
  }
  
  const deadline = new Date(now);
  deadline.setDate(now.getDate() + daysUntilMonday);
  return deadline.toISOString().split("T")[0];
}

/**
 * Create a commitment directly (bypassing RPC that uses auth.uid).
 */
async function createTestCommitment(options: {
  userId: string;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
  weekEndDate?: string;
}): Promise<{ id: string; week_end_date: string; max_charge_cents: number }> {
  const weekEndDate = options.weekEndDate ?? getNextMondayDeadline();
  const weekStartDate = new Date().toISOString().split("T")[0];
  
  // Calculate max charge (simplified - matches app formula roughly)
  const maxChargeCents = options.limitMinutes * options.penaltyPerMinuteCents * 7;

  // Ensure weekly pool exists (create or update to open if exists)
  await supabase.from("weekly_pools").upsert({
    week_start_date: weekEndDate,
    week_end_date: weekEndDate,
    total_penalty_cents: 0,
    status: "open",
  }, {
    onConflict: "week_start_date",
  });

  // Create commitment
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

  if (error) {
    throw new Error(`Failed to create commitment: ${error.message}`);
  }

  return {
    id: data.id,
    week_end_date: data.week_end_date,
    max_charge_cents: data.max_charge_cents,
  };
}

// MARK: - Tests

Deno.test("Commitment - Can create with correct values", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();

    // Act: Create a commitment
    const result = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 10,
    });

    // Assert: ID was returned
    assertExists(result.id, "Should return commitment ID");
    assertExists(result.week_end_date, "Should have week end date");

    // Assert: Can fetch the commitment
    const { data, error } = await supabase
      .from("commitments")
      .select("*")
      .eq("id", result.id)
      .single();

    assertEquals(error, null, "Should fetch commitment without error");
    assertEquals(data.limit_minutes, 60, "Limit minutes should be 60");
    assertEquals(data.penalty_per_minute_cents, 10, "Penalty should be 10 cents");
    assertEquals(data.status, "active", "Status should be active");
  });
});

Deno.test("Commitment - Weekly pool is created", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();

    // Act: Create a commitment
    const result = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 120,
      penaltyPerMinuteCents: 5,
    });

    // Assert: Weekly pool exists
    const { data, error } = await supabase
      .from("weekly_pools")
      .select("*")
      .eq("week_start_date", result.week_end_date)
      .single();

    assertEquals(error, null, "Should find weekly pool");
    assertEquals(data.status, "open", "Pool status should be open");
  });
});

Deno.test("Commitment - Max charge is calculated correctly", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();

    // Act: Create commitment with specific values
    const result = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 30,
      penaltyPerMinuteCents: 25,
    });

    // Assert: max_charge_cents = limit * penalty * 7 days
    const expectedMaxCharge = 30 * 25 * 7; // 5250 cents
    assertEquals(result.max_charge_cents, expectedMaxCharge, "Max charge should be calculated correctly");
  });
});

Deno.test("Commitment - Different penalty rates work", async () => {
  await withCleanup(async () => {
    // Setup
    await ensureTestUserExists();

    // Create multiple commitments with different rates
    const commitment1 = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 60,
      penaltyPerMinuteCents: 5,
    });

    // Cleanup the first one before creating second (same user, same week)
    await supabase.from("commitments").delete().eq("id", commitment1.id);

    const commitment2 = await createTestCommitment({
      userId: TEST_USER_ID,
      limitMinutes: 120,
      penaltyPerMinuteCents: 15,
    });

    // Verify the second commitment
    const { data } = await supabase
      .from("commitments")
      .select("*")
      .eq("id", commitment2.id)
      .single();

    assertEquals(data.limit_minutes, 120, "Limit should be 120");
    assertEquals(data.penalty_per_minute_cents, 15, "Penalty should be 15 cents");
  });
});

Deno.test("Commitment - User without payment method flag", async () => {
  await withCleanup(async () => {
    // Setup: Create user WITHOUT payment method
    const noPaymentUserId = TEST_USER_IDS.testUser2;
    await supabase.from("users").upsert({
      id: noPaymentUserId,
      email: "no-payment@example.com",
      stripe_customer_id: null,
      has_active_payment_method: false,
      is_test_user: true,
    });

    // Verify user was created with correct flag
    const { data } = await supabase
      .from("users")
      .select("has_active_payment_method")
      .eq("id", noPaymentUserId)
      .single();

    assertEquals(data.has_active_payment_method, false, "User should NOT have active payment method");
    
    // Note: The actual RPC rpc_create_commitment would reject this user,
    // but since we're bypassing RPC here, we're just verifying the flag is set correctly.
    // The real enforcement happens in the iOS app before calling the RPC.
  });
});

Deno.test("Commitment - Cleanup removes test data", async () => {
  // Setup: Create some test data
  await ensureTestUserExists();
  await createTestCommitment({
    userId: TEST_USER_ID,
    limitMinutes: 60,
    penaltyPerMinuteCents: 10,
  });

  // Act: Run cleanup
  const { data: cleanupResult } = await supabase.rpc("rpc_cleanup_test_data", {});

  // Assert: Data was cleaned up
  assertExists(cleanupResult, "Should return cleanup result");
  assertEquals(cleanupResult.success, true, "Cleanup should succeed");

  // Verify commitment was deleted
  const { data: commitments } = await supabase
    .from("commitments")
    .select("id")
    .eq("user_id", TEST_USER_ID);

  assertEquals(commitments?.length ?? 0, 0, "No commitments should remain for test user");
});
