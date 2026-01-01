/**
 * Check if usage data exists for a commitment
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const supabaseUrl = Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Missing environment variables!");
  Deno.exit(1);
}

const email = "jef@cavens.io";
const weekEndDate = "2026-01-01";

console.log("🔍 Checking usage data for:", email);
console.log("Week End Date:", weekEndDate);
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
console.log(`✅ Found user ID: ${userId}`);
console.log("");

// Get commitments
const commitmentsResponse = await fetch(`${supabaseUrl}/rest/v1/commitments?user_id=eq.${userId}&week_end_date=eq.${weekEndDate}&select=id,week_end_date,created_at&order=created_at.desc`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (!commitmentsResponse.ok) {
  console.error("❌ Failed to fetch commitments");
  Deno.exit(1);
}

const commitments = await commitmentsResponse.json();
console.log(`📋 Found ${commitments.length} commitment(s):`);
console.log("");

for (const commitment of commitments) {
  console.log(`  Commitment ID: ${commitment.id}`);
  console.log(`  Week End Date: ${commitment.week_end_date}`);
  console.log(`  Created At: ${commitment.created_at}`);
  console.log("");
  
  // Check daily_usage for this commitment
  const usageResponse = await fetch(`${supabaseUrl}/rest/v1/daily_usage?commitment_id=eq.${commitment.id}&select=date,used_minutes,penalty_cents,commitment_id&order=date.asc`, {
    method: "GET",
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
  });
  
  if (usageResponse.ok) {
    const usage = await usageResponse.json();
    console.log(`  📊 Daily Usage Records: ${usage.length}`);
    if (usage.length > 0) {
      let totalPenalty = 0;
      for (const entry of usage) {
        console.log(`    - Date: ${entry.date}, Used: ${entry.used_minutes} min, Penalty: $${((entry.penalty_cents || 0) / 100).toFixed(2)}`);
        totalPenalty += entry.penalty_cents || 0;
      }
      console.log(`    Total Penalty: $${(totalPenalty / 100).toFixed(2)}`);
    } else {
      console.log(`    ⚠️  No usage records found for this commitment`);
    }
  } else {
    console.log(`    ❌ Failed to fetch usage data`);
  }
  console.log("");
}

// Also check user_week_penalties
const penaltiesResponse = await fetch(`${supabaseUrl}/rest/v1/user_week_penalties?user_id=eq.${userId}&week_start_date=eq.${weekEndDate}&select=*`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (penaltiesResponse.ok) {
  const penalties = await penaltiesResponse.json();
  console.log(`📊 User Week Penalties: ${penalties.length}`);
  for (const penalty of penalties) {
    console.log(`  Total Penalty: $${((penalty.total_penalty_cents || 0) / 100).toFixed(2)}`);
    console.log(`  Actual Amount: $${((penalty.actual_amount_cents || 0) / 100).toFixed(2)}`);
    console.log(`  Settlement Status: ${penalty.settlement_status || 'null'}`);
  }
}


