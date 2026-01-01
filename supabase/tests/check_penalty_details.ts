/**
 * Check detailed penalty calculation
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const supabaseUrl = Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Missing environment variables!");
  Deno.exit(1);
}

const email = "jef@cavens.io";

console.log("🔍 Checking penalty details for:", email);
console.log("");

// Get user ID
const userResponse = await fetch(`${supabaseUrl}/rest/v1/users?email=eq.${encodeURIComponent(email)}&select=id`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (!userResponse.ok) {
  console.error("❌ Failed to fetch user");
  Deno.exit(1);
}

const users = await userResponse.json();
if (!users || users.length === 0) {
  console.log("❌ User not found");
  Deno.exit(0);
}

const userId = users[0].id;

// Get commitment
const commitmentResponse = await fetch(`${supabaseUrl}/rest/v1/commitments?user_id=eq.${userId}&select=id,limit_minutes,penalty_per_minute_cents,week_end_date&order=created_at.desc&limit=1`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (!commitmentResponse.ok) {
  console.error("❌ Failed to fetch commitment");
  Deno.exit(1);
}

const commitments = await commitmentResponse.json();
if (commitments.length === 0) {
  console.log("❌ No commitment found");
  Deno.exit(0);
}

const commitment = commitments[0];
console.log("📋 Commitment:");
console.log(`  Limit: ${commitment.limit_minutes} minutes`);
console.log(`  Penalty Rate: $${(commitment.penalty_per_minute_cents / 100).toFixed(2)} per minute`);
console.log(`  Week End Date: ${commitment.week_end_date}`);
console.log("");

// Get daily usage
const usageResponse = await fetch(`${supabaseUrl}/rest/v1/daily_usage?commitment_id=eq.${commitment.id}&select=date,used_minutes,limit_minutes,exceeded_minutes,penalty_cents&order=date.asc`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (usageResponse.ok) {
  const usage = await usageResponse.json();
  console.log("📊 Daily Usage:");
  let totalPenalty = 0;
  for (const entry of usage) {
    const exceeded = entry.exceeded_minutes || 0;
    const penalty = entry.penalty_cents || 0;
    const calculatedPenalty = exceeded * commitment.penalty_per_minute_cents;
    totalPenalty += penalty;
    console.log(`  Date: ${entry.date}`);
    console.log(`    Used: ${entry.used_minutes} min`);
    console.log(`    Limit: ${entry.limit_minutes} min`);
    console.log(`    Exceeded: ${exceeded} min`);
    console.log(`    Penalty (stored): $${(penalty / 100).toFixed(2)} (${penalty} cents)`);
    console.log(`    Penalty (calculated): $${(calculatedPenalty / 100).toFixed(2)} (${calculatedPenalty} cents)`);
    if (penalty !== calculatedPenalty) {
      console.log(`    ⚠️  MISMATCH! Stored: ${penalty} cents, Calculated: ${calculatedPenalty} cents`);
    }
    console.log("");
  }
  console.log(`  Total Penalty: $${(totalPenalty / 100).toFixed(2)} (${totalPenalty} cents)`);
}

// Get user week penalty
const penaltyResponse = await fetch(`${supabaseUrl}/rest/v1/user_week_penalties?user_id=eq.${userId}&week_start_date=eq.${commitment.week_end_date}&select=*`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (penaltyResponse.ok) {
  const penalties = await penaltyResponse.json();
  if (penalties.length > 0) {
    const penalty = penalties[0];
    console.log("📊 User Week Penalty:");
    console.log(`  Total Penalty: $${((penalty.total_penalty_cents || 0) / 100).toFixed(2)} (${penalty.total_penalty_cents || 0} cents)`);
    console.log(`  Actual Amount: $${((penalty.actual_amount_cents || 0) / 100).toFixed(2)} (${penalty.actual_amount_cents || 0} cents)`);
    console.log(`  Charged Amount: $${((penalty.charged_amount_cents || 0) / 100).toFixed(2)} (${penalty.charged_amount_cents || 0} cents)`);
    console.log(`  Settlement Status: ${penalty.settlement_status || 'null'}`);
  }
}


