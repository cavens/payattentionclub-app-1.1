/**
 * Test: Weekly Pools Closing (Step 1.2)
 * 
 * Tests that bright-service correctly closes weekly_pools after settlement.
 * 
 * This test verifies:
 * 1. weekly_pools with status 'open' exists before settlement
 * 2. After running bright-service, the pool status is 'closed'
 * 3. closed_at timestamp is set
 * 4. Only the target week's pool is closed (not others)
 * 
 * Run with: deno run --allow-net --allow-env --allow-read supabase/tests/test_weekly_pools_closing.ts
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase } from "./helpers/client.ts";
import { withCleanup } from "./helpers/cleanup.ts";
import { TEST_USER_IDS, config } from "./config.ts";

// MARK: - Test Setup

const TEST_USER_ID = TEST_USER_IDS.testUser1;

/**
 * Format date as YYYY-MM-DD (matches formatDate in bright-service)
 */
function formatDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
    date.getDate()
  ).padStart(2, "0")}`;
}

/**
 * Get target week end date (in testing mode, this is today's UTC date).
 */
function getTargetWeekEndDate(): string {
  const now = new Date();
  return formatDate(now);
}

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
 * Create a weekly_pool with open status.
 */
async function createWeeklyPool(weekStartDate: string, status: string = "open"): Promise<void> {
  const { error } = await supabase
    .from("weekly_pools")
    .upsert({
      week_start_date: weekStartDate, // In weekly_pools, week_start_date stores the deadline
      week_end_date: weekStartDate,   // Same as start (deadline is the pool identifier)
      total_penalty_cents: 1000,
      status: status,
    }, {
      onConflict: "week_start_date",
    });

  if (error) throw new Error(`Failed to create weekly_pool: ${error.message}`);
}

/**
 * Get weekly_pool by week_start_date.
 */
async function getWeeklyPool(weekStartDate: string) {
  const { data, error } = await supabase
    .from("weekly_pools")
    .select("*")
    .eq("week_start_date", weekStartDate)
    .single();

  if (error && error.code !== "PGRST116") { // PGRST116 = not found
    throw new Error(`Failed to get weekly_pool: ${error.message}`);
  }
  return data;
}

// MARK: - Test Cases

async function testWeeklyPoolsClosing() {
  console.log("🧪 Testing Weekly Pools Closing");
  console.log("=================================");
  console.log("");

  await withCleanup(async () => {
    const targetWeekEndDate = getTargetWeekEndDate();
    
    // Create a different week's pool to ensure we only close the target week
    const otherWeekDate = new Date();
    otherWeekDate.setUTCDate(otherWeekDate.getUTCDate() - 7);
    const otherWeekDateStr = formatDate(otherWeekDate);

    console.log(`📋 Test Setup:`);
    console.log(`   Target week end date: ${targetWeekEndDate}`);
    console.log(`   Other week date (should remain open): ${otherWeekDateStr}`);
    console.log("");

    // Step 1: Setup test user
    console.log("Step 1: Creating test user...");
    await ensureTestUserExists();
    console.log("✅ Test user created");
    console.log("");

    // Step 2: Create weekly_pools
    console.log("Step 2: Creating weekly_pools...");
    await createWeeklyPool(targetWeekEndDate, "open");
    await createWeeklyPool(otherWeekDateStr, "open");
    console.log("✅ Created 2 weekly_pools (target week and other week)");
    console.log("");

    // Step 3: Verify pools are open
    console.log("Step 3: Verifying pools are open before settlement...");
    const targetPoolBefore = await getWeeklyPool(targetWeekEndDate);
    const otherPoolBefore = await getWeeklyPool(otherWeekDateStr);
    
    assertExists(targetPoolBefore, "Target week pool should exist");
    assertExists(otherPoolBefore, "Other week pool should exist");
    assertEquals(targetPoolBefore.status, "open", "Target week pool should be open");
    assertEquals(otherPoolBefore.status, "open", "Other week pool should be open");
    console.log("✅ Both pools are open (as expected)");
    console.log("");

    // Step 4: Call bright-service
    console.log("Step 4: Calling bright-service to trigger pool closing...");
    try {
      // In testing mode, bright-service requires x-manual-trigger header
      const url = `${config.supabase.url}/functions/v1/bright-service`;
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-manual-trigger": "true", // Required for testing mode
        },
        body: JSON.stringify({
          targetWeek: targetWeekEndDate,
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`bright-service failed (${response.status}): ${errorText}`);
      }

      const result = await response.json();
      console.log("✅ bright-service executed successfully");
      console.log(`   Response: ${JSON.stringify(result, null, 2)}`);
    } catch (error) {
      console.error("❌ bright-service failed:", error);
      throw error;
    }
    console.log("");

    // Step 5: Verify target week pool is closed
    console.log("Step 5: Verifying target week pool is closed...");
    const targetPoolAfter = await getWeeklyPool(targetWeekEndDate);
    
    assertExists(targetPoolAfter, "Target week pool should still exist");
    assertEquals(targetPoolAfter.status, "closed", "Target week pool should be closed");
    assertExists(targetPoolAfter.closed_at, "Target week pool should have closed_at timestamp");
    
    const closedAt = new Date(targetPoolAfter.closed_at);
    const now = new Date();
    const timeDiff = now.getTime() - closedAt.getTime();
    
    // closed_at should be recent (within last 5 minutes)
    if (timeDiff > 5 * 60 * 1000) {
      throw new Error(`closed_at timestamp is too old: ${targetPoolAfter.closed_at}`);
    }
    
    console.log(`   Status: ${targetPoolAfter.status}`);
    console.log(`   Closed at: ${targetPoolAfter.closed_at}`);
    console.log("✅ Target week pool is closed correctly");
    console.log("");

    // Step 6: Verify other week pool is still open
    console.log("Step 6: Verifying other week pool is still open...");
    const otherPoolAfter = await getWeeklyPool(otherWeekDateStr);
    
    assertExists(otherPoolAfter, "Other week pool should still exist");
    assertEquals(otherPoolAfter.status, "open", "Other week pool should still be open");
    assertEquals(otherPoolAfter.closed_at, null, "Other week pool should not have closed_at");
    console.log(`   Status: ${otherPoolAfter.status}`);
    console.log(`   Closed at: ${otherPoolAfter.closed_at || "null"}`);
    console.log("✅ Other week pool is still open (correctly not closed)");
    console.log("");

    console.log("=================================");
    console.log("✅ All tests passed!");
    console.log("");
    console.log("📊 Summary:");
    console.log(`   - Target week pool (${targetWeekEndDate}): closed ✅`);
    console.log(`   - Other week pool (${otherWeekDateStr}): still open ✅`);
    console.log(`   - Only target week pool was closed (correct behavior) ✅`);
  });
}

// MARK: - Main

async function main() {
  try {
    await testWeeklyPoolsClosing();
    console.log("");
    console.log("🎉 All tests completed successfully!");
  } catch (error) {
    console.error("❌ Test failed:", error);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}



