/**
 * Delete Test Users
 * 
 * This script deletes all test users from the database.
 * Test users are identified by is_test_user = true
 * 
 * Usage:
 *   deno run --allow-all delete_test_users.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

async function main() {
  console.log("🗑️  Delete Test Users");
  console.log("======================");
  console.log("");

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

  console.log(`Environment: ${env}`);
  console.log(`Supabase URL: ${supabaseUrl}`);
  console.log("");

  // Call cleanup function with deleteTestUsers = true
  console.log("Deleting all test users...");
  
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_cleanup_test_data`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
    body: JSON.stringify({
      p_delete_test_users: true,
      p_real_user_email: "",
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`❌ HTTP Error ${response.status}: ${errorText}`);
    Deno.exit(1);
  }

  const result = await response.json();
  
  if (result.success) {
    console.log("✅ Test users deleted successfully!");
    console.log("");
    console.log("Deleted:");
    console.log(`   - Payments: ${result.deleted.payments}`);
    console.log(`   - Daily usage: ${result.deleted.daily_usage}`);
    console.log(`   - Week penalties: ${result.deleted.user_week_penalties}`);
    console.log(`   - Commitments: ${result.deleted.commitments}`);
    console.log(`   - Weekly pools: ${result.deleted.weekly_pools}`);
    console.log(`   - Users: ${result.deleted.users}`);
    if (result.test_user_ids_cleaned && result.test_user_ids_cleaned.length > 0) {
      console.log(`   - Test user IDs cleaned: ${result.test_user_ids_cleaned.join(", ")}`);
    }
  } else {
    console.error(`❌ Failed to delete test users: ${result.message || "Unknown error"}`);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("❌ Error:", error);
    Deno.exit(1);
  });
}

