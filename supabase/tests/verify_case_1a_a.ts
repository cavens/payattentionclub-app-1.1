/**
 * Verification Script for Case 1_A_A
 * Sync Before Grace Begins + 0 Usage + 0 Penalty
 * 
 * Expected Results:
 * - Settlement status: pending (unchanged)
 * - Charged amount: 0 cents
 * - No Stripe PaymentIntent created
 * - No payment record created
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const userId = Deno.args[0];
if (!userId) {
  console.error("Usage: deno run --allow-net --allow-env verify_case_1a_a.ts <user-id>");
  Deno.exit(1);
}

console.log("\n🔍 Verifying Case 1_A_A Results");
console.log("================================\n");
console.log(`User ID: ${userId}\n`);

// Get latest commitment
const { data: commitment, error: commitmentError } = await supabase
  .from("commitments")
  .select("*")
  .eq("user_id", userId)
  .order("created_at", { ascending: false })
  .limit(1)
  .single();

if (commitmentError) {
  console.error("❌ Error fetching commitment:", commitmentError.message);
  Deno.exit(1);
}

// Get latest penalty record
const { data: penalty, error: penaltyError } = await supabase
  .from("user_week_penalties")
  .select("*")
  .eq("user_id", userId)
  .order("week_start_date", { ascending: false })
  .limit(1)
  .single();

// Get payments created after commitment
const { data: payments, error: paymentsError } = await supabase
  .from("payments")
  .select("*")
  .eq("user_id", userId)
  .gte("created_at", commitment.created_at)
  .order("created_at", { ascending: false });

if (paymentsError) {
  console.error("❌ Error fetching payments:", paymentsError.message);
}

// Get usage entries
const { data: usage, error: usageError } = await supabase
  .from("daily_usage")
  .select("date, used_minutes, penalty_cents")
  .eq("user_id", userId)
  .order("date", { ascending: false });

if (usageError) {
  console.error("❌ Error fetching usage:", usageError.message);
}

// Verification checks
console.log("📋 VERIFICATION CHECKS\n");

let allPassed = true;

// Check 1: Settlement Status
console.log("1. Settlement Status:");
const status = penalty?.settlement_status || null;
const expectedStatus = "pending";
const statusPass = status === expectedStatus || status === null;
console.log(`   Expected: ${expectedStatus} (or null)`);
console.log(`   Actual: ${status || "null"}`);
console.log(`   ${statusPass ? "✅ PASS" : "❌ FAIL"}\n`);
if (!statusPass) allPassed = false;

// Check 2: Charged Amount
console.log("2. Charged Amount:");
const chargedAmount = penalty?.charged_amount_cents || 0;
const expectedCharged = 0;
const chargedPass = chargedAmount === expectedCharged;
console.log(`   Expected: ${expectedCharged} cents`);
console.log(`   Actual: ${chargedAmount} cents`);
console.log(`   ${chargedPass ? "✅ PASS" : "❌ FAIL"}\n`);
if (!chargedPass) allPassed = false;

// Check 3: Total Penalty
console.log("3. Total Penalty:");
const totalPenalty = penalty?.total_penalty_cents || 0;
const expectedPenalty = 0;
const penaltyPass = totalPenalty === expectedPenalty;
console.log(`   Expected: ${expectedPenalty} cents`);
console.log(`   Actual: ${totalPenalty} cents`);
console.log(`   ${penaltyPass ? "✅ PASS" : "❌ FAIL"}\n`);
if (!penaltyPass) allPassed = false;

// Check 4: No Payments
console.log("4. Payment Records:");
const paymentCount = payments?.length || 0;
const expectedPayments = 0;
const paymentsPass = paymentCount === expectedPayments;
console.log(`   Expected: ${expectedPayments} payments`);
console.log(`   Actual: ${paymentCount} payments`);
if (paymentCount > 0) {
  console.log(`   Payments found:`);
  payments?.forEach((p, i) => {
    console.log(`     ${i + 1}. ${p.payment_type}: ${p.amount_cents} cents (${p.status})`);
  });
}
console.log(`   ${paymentsPass ? "✅ PASS" : "❌ FAIL"}\n`);
if (!paymentsPass) allPassed = false;

// Check 5: Usage Entries (should exist but with 0 penalty)
console.log("5. Usage Entries:");
const usageCount = usage?.length || 0;
const usageTotalPenalty = usage?.reduce((sum, u) => sum + (u.penalty_cents || 0), 0) || 0;
console.log(`   Entry count: ${usageCount}`);
console.log(`   Total penalty from usage: ${usageTotalPenalty} cents`);
console.log(`   ${usageTotalPenalty === 0 ? "✅ PASS" : "⚠️  WARNING: Usage entries have non-zero penalty"}\n`);

// Summary
console.log("================================\n");
console.log(`Overall Result: ${allPassed ? "✅ ALL CHECKS PASSED" : "❌ SOME CHECKS FAILED"}\n`);

// Detailed data dump
console.log("📊 DETAILED DATA\n");
console.log("Commitment:", JSON.stringify({
  id: commitment.id,
  week_end_date: commitment.week_end_date,
  week_grace_expires_at: commitment.week_grace_expires_at,
  max_charge_cents: commitment.max_charge_cents,
  status: commitment.status
}, null, 2));

if (penalty) {
  console.log("\nPenalty Record:", JSON.stringify({
    settlement_status: penalty.settlement_status,
    total_penalty_cents: penalty.total_penalty_cents,
    charged_amount_cents: penalty.charged_amount_cents,
    actual_amount_cents: penalty.actual_amount_cents,
    needs_reconciliation: penalty.needs_reconciliation,
    week_start_date: penalty.week_start_date
  }, null, 2));
} else {
  console.log("\nPenalty Record: None found");
}

console.log(`\nPayments: ${paymentCount}`);
console.log(`Usage Entries: ${usageCount}`);

Deno.exit(allPassed ? 0 : 1);

