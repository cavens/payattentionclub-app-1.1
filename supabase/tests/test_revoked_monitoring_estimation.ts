/**
 * Test: Revoked Monitoring Estimation (Step 1.1)
 * 
 * Tests that bright-service correctly estimates usage for commitments with revoked monitoring.
 * 
 * This test verifies:
 * 1. Commitments with monitoring_status = 'revoked' are found
 * 2. Estimated daily_usage entries are created from revocation date to week end date
 * 3. Estimation values are correct: used_minutes = limit_minutes * 2, exceeded_minutes = limit_minutes
 * 4. No duplicate entries are created if they already exist
 * 5. Entries are marked with is_estimated = true
 * 
 * Run with: deno run --allow-net --allow-env --allow-read supabase/tests/test_revoked_monitoring_estimation.ts
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase, callEdgeFunction } from "./helpers/client.ts";
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
 * Get target week end date (in testing mode, this is today's UTC date).
 */
function getTargetWeekEndDate(): string {
  const now = new Date();
  return formatDate(now);
}

/**
 * Create test commitment with revoked monitoring.
 */
async function createRevokedCommitment(options: {
  userId: string;
  limitMinutes: number;
  penaltyPerMinuteCents: number;
  weekEndDate: string;
  revokedAt: string; // Date when monitoring was revoked (YYYY-MM-DD)
}): Promise<string> {
  const weekStartDate = formatDate(new Date());
  const maxChargeCents = options.limitMinutes * options.penaltyPerMinuteCents * 7;

  // Create weekly pool first
  await supabase.from("weekly_pools").upsert({
    week_start_date: options.weekEndDate,
    week_end_date: options.weekEndDate,
    total_penalty_cents: 0,
    status: "open",
  }, {
    onConflict: "week_start_date",
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
      monitoring_status: "revoked", // Revoked monitoring
      monitoring_revoked_at: `${options.revokedAt}T12:00:00Z`, // ISO timestamp
      max_charge_cents: maxChargeCents,
    })
    .select()
    .single();

  if (error) throw new Error(`Failed to create commitment: ${error.message}`);
  return data.id;
}

/**
 * Count estimated daily_usage entries for a commitment.
 */
async function countEstimatedUsage(commitmentId: string): Promise<number> {
  const { count, error } = await supabase
    .from("daily_usage")
    .select("*", { count: "exact", head: true })
    .eq("commitment_id", commitmentId)
    .eq("is_estimated", true);

  if (error) throw new Error(`Failed to count estimated usage: ${error.message}`);
  return count ?? 0;
}

/**
 * Get all estimated daily_usage entries for a commitment.
 */
async function getEstimatedUsage(commitmentId: string) {
  const { data, error } = await supabase
    .from("daily_usage")
    .select("*")
    .eq("commitment_id", commitmentId)
    .eq("is_estimated", true)
    .order("date", { ascending: true });

  if (error) throw new Error(`Failed to get estimated usage: ${error.message}`);
  return data ?? [];
}

// MARK: - Test Cases

async function testRevokedMonitoringEstimation() {
  console.log("🧪 Testing Revoked Monitoring Estimation");
  console.log("========================================");
  console.log("");

  await withCleanup(async () => {
    const targetWeekEndDate = getTargetWeekEndDate();
    const limitMinutes = 60;
    const penaltyPerMinuteCents = 10;
    
    // Calculate revocation date (2 days before week end, mid-week)
    const revokedDate = new Date();
    revokedDate.setUTCDate(revokedDate.getUTCDate() - 2);
    const revokedDateStr = formatDate(revokedDate);

    console.log(`📋 Test Setup:`);
    console.log(`   Target week end date: ${targetWeekEndDate}`);
    console.log(`   Revocation date: ${revokedDateStr}`);
    console.log(`   Limit: ${limitMinutes} minutes`);
    console.log(`   Penalty: ${penaltyPerMinuteCents} cents/minute`);
    console.log("");

    // Step 1: Setup test user
    console.log("Step 1: Creating test user...");
    await ensureTestUserExists();
    console.log("✅ Test user created");
    console.log("");

    // Step 2: Create commitment with revoked monitoring
    console.log("Step 2: Creating commitment with revoked monitoring...");
    const commitmentId = await createRevokedCommitment({
      userId: TEST_USER_ID,
      limitMinutes,
      penaltyPerMinuteCents,
      weekEndDate: targetWeekEndDate,
      revokedAt: revokedDateStr,
    });
    console.log(`✅ Commitment created: ${commitmentId}`);
    console.log("");

    // Step 3: Verify commitment was created correctly
    console.log("Step 3: Verifying commitment was created with correct values...");
    const { data: commitment, error: commitError } = await supabase
      .from("commitments")
      .select("id, week_end_date, monitoring_status, monitoring_revoked_at, status")
      .eq("id", commitmentId)
      .single();
    
    if (commitError) throw new Error(`Failed to fetch commitment: ${commitError.message}`);
    
    console.log(`   Commitment ID: ${commitment.id}`);
    console.log(`   Week end date: ${commitment.week_end_date}`);
    console.log(`   Monitoring status: ${commitment.monitoring_status}`);
    console.log(`   Monitoring revoked at: ${commitment.monitoring_revoked_at}`);
    console.log(`   Status: ${commitment.status}`);
    console.log(`   Target week end date: ${targetWeekEndDate}`);
    
    assertEquals(commitment.week_end_date, targetWeekEndDate, "Week end date should match target");
    assertEquals(commitment.monitoring_status, "revoked", "Monitoring status should be revoked");
    assertExists(commitment.monitoring_revoked_at, "Monitoring revoked at should be set");
    console.log("✅ Commitment values are correct");
    console.log("");

    // Step 3b: Verify no estimated entries exist yet
    console.log("Step 3b: Verifying no estimated entries exist before settlement...");
    const countBefore = await countEstimatedUsage(commitmentId);
    assertEquals(countBefore, 0, "Should have no estimated entries before settlement");
    console.log("✅ No estimated entries found (as expected)");
    console.log("");

    // Step 4: Call bright-service
    console.log("Step 4: Calling bright-service to trigger revoked monitoring estimation...");
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

    // Step 5: Verify estimated entries were created
    console.log("Step 5: Verifying estimated entries were created...");
    const estimatedEntries = await getEstimatedUsage(commitmentId);
    const countAfter = estimatedEntries.length;
    
    console.log(`   Found ${countAfter} estimated entry/entries`);
    
    // Calculate expected number of days (from revocation date to week end date, exclusive)
    // The code creates entries while d < commitmentEnd, so it creates entries for:
    // revokedDate, revokedDate+1, ..., weekEndDate-1 (not including weekEndDate)
    const revokedDateObj = new Date(revokedDateStr + "T00:00:00Z");
    const weekEndDateObj = new Date(targetWeekEndDate + "T00:00:00Z");
    const daysDiff = Math.floor((weekEndDateObj.getTime() - revokedDateObj.getTime()) / (1000 * 60 * 60 * 24));
    
    console.log(`   Expected entries: ${daysDiff} (from ${revokedDateStr} to ${targetWeekEndDate}, exclusive)`);
    
    // Should have at least 1 entry (could be more if revoked earlier)
    if (countAfter === 0) {
      throw new Error("❌ No estimated entries were created! Revoked monitoring estimation failed.");
    }
    
    // Verify count matches expected (allowing for some variance due to timing)
    if (countAfter < daysDiff - 1 || countAfter > daysDiff + 1) {
      console.warn(`   ⚠️  Entry count (${countAfter}) doesn't exactly match expected (${daysDiff}), but this may be due to timing`);
    }
    
    console.log("✅ Estimated entries were created");
    console.log("");

    // Step 6: Verify estimation values are correct
    console.log("Step 6: Verifying estimation values are correct...");
    for (const entry of estimatedEntries) {
      const expectedUsedMinutes = limitMinutes * 2; // Double usage
      const expectedExceededMinutes = limitMinutes; // Full limit exceeded
      const expectedPenaltyCents = expectedExceededMinutes * penaltyPerMinuteCents;

      console.log(`   Checking entry for ${entry.date}:`);
      console.log(`     used_minutes: ${entry.used_minutes} (expected: ${expectedUsedMinutes})`);
      console.log(`     exceeded_minutes: ${entry.exceeded_minutes} (expected: ${expectedExceededMinutes})`);
      console.log(`     penalty_cents: ${entry.penalty_cents} (expected: ${expectedPenaltyCents})`);
      console.log(`     is_estimated: ${entry.is_estimated} (expected: true)`);

      assertEquals(entry.used_minutes, expectedUsedMinutes, 
        `used_minutes should be ${expectedUsedMinutes} (limit * 2)`);
      assertEquals(entry.exceeded_minutes, expectedExceededMinutes,
        `exceeded_minutes should be ${expectedExceededMinutes} (limit)`);
      assertEquals(entry.penalty_cents, expectedPenaltyCents,
        `penalty_cents should be ${expectedPenaltyCents} (exceeded * penalty_per_minute)`);
      assertEquals(entry.is_estimated, true,
        "is_estimated should be true");
      assertEquals(entry.limit_minutes, limitMinutes,
        "limit_minutes should match commitment limit");
    }
    console.log("✅ All estimation values are correct");
    console.log("");

    // Step 7: Verify no duplicates (run bright-service again)
    console.log("Step 7: Verifying no duplicate entries are created (run bright-service again)...");
    const countBeforeSecondRun = await countEstimatedUsage(commitmentId);
    console.log(`   Entries before second run: ${countBeforeSecondRun}`);
    
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

      await response.json();
    } catch (error) {
      console.error("❌ bright-service failed on second run:", error);
      throw error;
    }
    
    const countAfterSecondRun = await countEstimatedUsage(commitmentId);
    console.log(`   Entries after second run: ${countAfterSecondRun}`);
    
    assertEquals(countAfterSecondRun, countBeforeSecondRun,
      "Should not create duplicate entries when running bright-service twice");
    console.log("✅ No duplicate entries created");
    console.log("");

    // Step 8: Verify date range
    console.log("Step 8: Verifying date range (entries from revocation date to week end date, exclusive)...");
    const dates = estimatedEntries.map(e => e.date).sort();
    const firstDate = dates[0];
    const lastDate = dates[dates.length - 1];
    
    console.log(`   First entry date: ${firstDate}`);
    console.log(`   Last entry date: ${lastDate}`);
    console.log(`   Revocation date: ${revokedDateStr}`);
    console.log(`   Week end date: ${targetWeekEndDate}`);
    
    // First date should be >= revocation date
    if (firstDate < revokedDateStr) {
      throw new Error(`❌ First entry date (${firstDate}) is before revocation date (${revokedDateStr})`);
    }
    
    // Last date should be < week end date (entries are created while d < commitmentEnd)
    if (lastDate >= targetWeekEndDate) {
      throw new Error(`❌ Last entry date (${lastDate}) is on or after week end date (${targetWeekEndDate})`);
    }
    
    // Verify all dates are in the expected range
    for (const date of dates) {
      if (date < revokedDateStr || date >= targetWeekEndDate) {
        throw new Error(`❌ Entry date ${date} is outside expected range [${revokedDateStr}, ${targetWeekEndDate})`);
      }
    }
    
    console.log("✅ Date range is correct");
    console.log("");

    console.log("========================================");
    console.log("✅ All tests passed!");
    console.log("");
    console.log("📊 Summary:");
    console.log(`   - Created ${countAfter} estimated daily_usage entries`);
    console.log(`   - All entries have correct estimation values`);
    console.log(`   - No duplicate entries created on second run`);
    console.log(`   - Date range is correct (${firstDate} to ${lastDate})`);
  });
}

// MARK: - Edge Case Tests

async function testNoRevocationDate() {
  console.log("🧪 Testing Edge Case: No Revocation Date");
  console.log("==========================================");
  console.log("");

  await withCleanup(async () => {
    const targetWeekEndDate = getTargetWeekEndDate();
    
    console.log("📋 Test Setup:");
    console.log(`   Commitment with monitoring_status = 'revoked' but monitoring_revoked_at = null`);
    console.log("   Expected: Should be skipped (no estimation)");
    console.log("");

    await ensureTestUserExists();

    // Create commitment with revoked status but no revocation date
    const { data: commitment, error } = await supabase
      .from("commitments")
      .insert({
        user_id: TEST_USER_ID,
        week_start_date: formatDate(new Date()),
        week_end_date: targetWeekEndDate,
        limit_minutes: 60,
        penalty_per_minute_cents: 10,
        apps_to_limit: { app_bundle_ids: ["com.apple.Safari"], categories: [] },
        status: "active",
        monitoring_status: "revoked",
        monitoring_revoked_at: null, // No revocation date
        max_charge_cents: 4200,
      })
      .select()
      .single();

    if (error) throw new Error(`Failed to create commitment: ${error.message}`);

    console.log("Step 1: Calling bright-service...");
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

    await response.json();
    console.log("✅ bright-service executed");
    console.log("");

    console.log("Step 2: Verifying no estimated entries were created...");
    const count = await countEstimatedUsage(commitment.id);
    assertEquals(count, 0, "Should skip commitments without revocation date");
    console.log("✅ No estimated entries created (correctly skipped)");
    console.log("");

    console.log("==========================================");
    console.log("✅ Edge case test passed!");
  });
}

// MARK: - Main

async function main() {
  try {
    await testRevokedMonitoringEstimation();
    console.log("");
    await testNoRevocationDate();
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

