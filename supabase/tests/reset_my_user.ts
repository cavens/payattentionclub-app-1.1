/**
 * Reset My User - Completely delete a user from Supabase
 * 
 * This script deletes a user and ALL their data, allowing you to 
 * start fresh with Apple Sign-In on your device.
 * 
 * Usage:
 *   deno run --allow-all reset_my_user.ts                    # Interactive
 *   deno run --allow-all reset_my_user.ts --force            # Skip confirmation
 *   deno run --allow-all reset_my_user.ts other@email.com    # Different email
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

// Default email - your Apple Sign-In relay email
const DEFAULT_EMAIL = "pythwk8m57@privaterelay.appleid.com";

async function main() {
  // Check for --force flag
  const forceMode = Deno.args.includes("--force");
  
  // Get email from command line (ignore --force flag) or use default
  const emailArg = Deno.args.find(arg => !arg.startsWith("--"));
  const email = emailArg || DEFAULT_EMAIL;
  
  console.log("🗑️  Reset My User");
  console.log("================");
  console.log(`Email: ${email}`);
  console.log("");

  // Load environment variables
  // Support environment-specific variables with fallback
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

  // Confirm before proceeding (skip if --force)
  console.log("⚠️  WARNING: This will PERMANENTLY delete:");
  console.log("   - User from auth.users (Apple Sign-In will create new user)");
  console.log("   - User from public.users");
  console.log("   - All commitments");
  console.log("   - All daily_usage records");
  console.log("   - All user_week_penalties");
  console.log("   - All payments");
  console.log("");
  
  if (!forceMode) {
    const confirm = prompt("Type 'DELETE' to confirm: ");
    if (confirm !== "DELETE") {
      console.log("❌ Cancelled");
      Deno.exit(0);
    }
  } else {
    console.log("🔓 Force mode - skipping confirmation");
  }

  console.log("");
  console.log("🔄 Deleting user...");

  try {
    // Call the RPC function
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_delete_user_completely`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_email: email,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ HTTP Error ${response.status}: ${errorText}`);
      Deno.exit(1);
    }

    const result = await response.json();
    
    if (result.success) {
      console.log("✅ User deleted successfully!");
      console.log("");
      console.log("Deleted:");
      console.log(`   - Payments: ${result.deleted.payments}`);
      console.log(`   - Daily usage: ${result.deleted.daily_usage}`);
      console.log(`   - Week penalties: ${result.deleted.user_week_penalties}`);
      console.log(`   - Commitments: ${result.deleted.commitments}`);
      console.log(`   - Public user: ${result.deleted.public_users}`);
      console.log(`   - Auth user: ${result.deleted.auth_users}`);
      console.log("");
      console.log("🎉 You can now sign in fresh with Apple Sign-In!");
    } else {
      console.error(`❌ Error: ${result.error}`);
      Deno.exit(1);
    }
  } catch (error) {
    console.error(`❌ Error: ${error.message}`);
    Deno.exit(1);
  }
}

main();

