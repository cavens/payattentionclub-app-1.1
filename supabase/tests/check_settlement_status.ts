/**
 * Check settlement status for a user
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

console.log("🔍 Checking settlement status for:", email);
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

// Get user_week_penalties
const penaltiesResponse = await fetch(`${supabaseUrl}/rest/v1/user_week_penalties?user_id=eq.${userId}&week_start_date=eq.${weekEndDate}&select=*`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (!penaltiesResponse.ok) {
  console.error("❌ Failed to fetch user_week_penalties");
  Deno.exit(1);
}

const penalties = await penaltiesResponse.json();
console.log(`📋 Found ${penalties.length} user_week_penalties record(s):`);
console.log("");

if (penalties.length === 0) {
  console.log("  ⚠️  No settlement record found - this explains why it keeps trying to charge");
} else {
  for (const penalty of penalties) {
    console.log(`  Settlement Status: ${penalty.settlement_status || 'null'}`);
    console.log(`  Charged Amount: $${((penalty.charged_amount_cents || 0) / 100).toFixed(2)}`);
    console.log(`  Actual Amount: $${((penalty.actual_amount_cents || 0) / 100).toFixed(2)}`);
    console.log(`  Charge Payment Intent ID: ${penalty.charge_payment_intent_id || 'null'}`);
    console.log(`  Charged At: ${penalty.charged_at || 'null'}`);
    console.log("");
  }
}

// Also check payments
const paymentsResponse = await fetch(`${supabaseUrl}/rest/v1/payments?user_id=eq.${userId}&week_start_date=eq.${weekEndDate}&select=*&order=created_at.desc`, {
  method: "GET",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
});

if (paymentsResponse.ok) {
  const payments = await paymentsResponse.json();
  console.log(`💳 Found ${payments.length} payment record(s):`);
  console.log("");
  for (const payment of payments) {
    console.log(`  Amount: $${((payment.amount_cents || 0) / 100).toFixed(2)}`);
    console.log(`  Status: ${payment.status}`);
    console.log(`  Payment Intent ID: ${payment.stripe_payment_intent_id || 'null'}`);
    console.log(`  Created At: ${payment.created_at}`);
    console.log("");
  }
}


