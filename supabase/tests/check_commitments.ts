/**
 * Check commitments in the database
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const supabaseUrl = Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Missing environment variables!");
  Deno.exit(1);
}

const email = "jef@cavens.io";

console.log("🔍 Checking commitments for:", email);
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
const commitmentsResponse = await fetch(`${supabaseUrl}/rest/v1/commitments?user_id=eq.${userId}&select=id,week_end_date,status,created_at,max_charge_cents&order=created_at.desc`, {
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
  console.log(`  ID: ${commitment.id}`);
  console.log(`  Week End Date: ${commitment.week_end_date}`);
  console.log(`  Status: ${commitment.status || 'null'}`);
  console.log(`  Max Charge: $${((commitment.max_charge_cents || 0) / 100).toFixed(2)}`);
  console.log(`  Created At: ${commitment.created_at}`);
  console.log("");
}

// Calculate what week the settlement function is looking for
const now = new Date();
const reference = new Date(now.toLocaleString("en-US", { timeZone: "America/New_York" }));
const monday = new Date(reference);
const dayOfWeek = reference.getDay();
const daysSinceMonday = (dayOfWeek + 6) % 7;
monday.setDate(monday.getDate() - daysSinceMonday);
monday.setHours(12, 0, 0, 0);
const weekEndDate = `${monday.getFullYear()}-${String(monday.getMonth() + 1).padStart(2, "0")}-${String(monday.getDate()).padStart(2, "0")}`;

console.log(`🎯 Settlement function is looking for week_end_date: ${weekEndDate}`);
console.log("");


