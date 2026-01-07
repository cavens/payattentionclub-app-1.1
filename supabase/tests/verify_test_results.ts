/**
 * Verify Test Results
 * 
 * Command-line script to verify settlement test results.
 * Calls rpc_verify_test_settlement to get all test data for a user.
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read supabase/tests/verify_test_results.ts <user-id>
 * 
 * Example:
 *   deno run --allow-net --allow-env --allow-read supabase/tests/verify_test_results.ts 11111111-1111-1111-1111-111111111111
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Load environment variables
const env = Deno.env.get("TEST_ENVIRONMENT") || "staging";
const isStaging = env === "staging";

const supabaseUrl = isStaging
  ? Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL")
  : Deno.env.get("PRODUCTION_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");

const serviceRoleKey = isStaging
  ? Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  : Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Missing environment variables!");
  console.error("   Make sure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set in .env");
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey);

async function verifyTestResults(userId: string) {
  console.log("📊 Verifying test results...");
  console.log(`   User ID: ${userId}`);
  console.log(`   Environment: ${env}`);
  console.log("");

  const { data, error } = await supabase.rpc('rpc_verify_test_settlement', {
    p_user_id: userId
  });

  if (error) {
    console.error("❌ Verification failed:", error);
    Deno.exit(1);
  }

  console.log("📊 TEST RESULTS VERIFICATION");
  console.log("============================\n");

  // Commitment
  if (data.commitment && data.commitment !== null) {
    console.log("✅ Commitment:");
    console.log(`   ID: ${data.commitment.id}`);
    console.log(`   Deadline: ${data.commitment.week_end_date}`);
    console.log(`   Grace Expires: ${data.commitment.week_grace_expires_at || 'Not set'}`);
    console.log(`   Max Charge: ${data.commitment.max_charge_cents} cents ($${(data.commitment.max_charge_cents / 100).toFixed(2)})`);
    console.log(`   Status: ${data.commitment.status || 'N/A'}`);
    console.log(`   Created: ${data.commitment.created_at}`);
  } else {
    console.log("⚠️  No commitment found");
  }

  // Penalty
  if (data.penalty && data.penalty !== null) {
    console.log("\n✅ Penalty Record:");
    console.log(`   Settlement Status: ${data.penalty.settlement_status || 'N/A'}`);
    console.log(`   Total Penalty: ${data.penalty.total_penalty_cents || 0} cents ($${((data.penalty.total_penalty_cents || 0) / 100).toFixed(2)})`);
    console.log(`   Charged Amount: ${data.penalty.charged_amount_cents || 0} cents ($${((data.penalty.charged_amount_cents || 0) / 100).toFixed(2)})`);
    console.log(`   Actual Amount: ${data.penalty.actual_amount_cents || 0} cents ($${((data.penalty.actual_amount_cents || 0) / 100).toFixed(2)})`);
    console.log(`   Refund Amount: ${data.penalty.refund_amount_cents || 0} cents ($${((data.penalty.refund_amount_cents || 0) / 100).toFixed(2)})`);
    console.log(`   Needs Reconciliation: ${data.penalty.needs_reconciliation ? 'Yes' : 'No'}`);
    if (data.penalty.needs_reconciliation) {
      console.log(`   Reconciliation Delta: ${data.penalty.reconciliation_delta_cents || 0} cents`);
      console.log(`   Reconciliation Reason: ${data.penalty.reconciliation_reason || 'N/A'}`);
    }
    console.log(`   Week Start: ${data.penalty.week_start_date || 'N/A'}`);
  } else {
    console.log("\n⚠️  No penalty record found");
  }

  // Payments
  const payments = data.payments || [];
  console.log(`\n✅ Payments: ${payments.length}`);
  if (payments.length > 0) {
    payments.forEach((p: any, i: number) => {
      console.log(`   ${i + 1}. ${p.type || 'N/A'}: ${p.amount_cents || 0} cents ($${((p.amount_cents || 0) / 100).toFixed(2)}) - Status: ${p.status || 'N/A'}`);
      if (p.payment_intent_id) {
        console.log(`      Payment Intent: ${p.payment_intent_id}`);
      }
      if (p.created_at) {
        console.log(`      Created: ${p.created_at}`);
      }
    });
  } else {
    console.log("   No payments found");
  }

  // Usage
  console.log(`\n✅ Usage Entries: ${data.usage_count || 0}`);
  
  // Verification time
  console.log(`\n⏰ Verification Time: ${data.verification_time}`);
  console.log("\n============================\n");
}

// Get user ID from command line arguments
const userId = Deno.args[0];
if (!userId) {
  console.error("❌ Missing user ID argument");
  console.error("");
  console.error("Usage: deno run --allow-net --allow-env --allow-read supabase/tests/verify_test_results.ts <user-id>");
  console.error("");
  console.error("Example:");
  console.error("  deno run --allow-net --allow-env --allow-read supabase/tests/verify_test_results.ts 11111111-1111-1111-1111-111111111111");
  Deno.exit(1);
}

// Validate UUID format
const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!uuidRegex.test(userId)) {
  console.error("❌ Invalid user ID format. Expected UUID.");
  console.error(`   Got: ${userId}`);
  Deno.exit(1);
}

await verifyTestResults(userId);

