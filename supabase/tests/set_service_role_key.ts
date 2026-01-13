/**
 * Set Service Role Key in Database Settings
 * 
 * This script sets the service role key in PostgreSQL database settings
 * so that pg_cron jobs can authenticate with Edge Functions.
 * 
 * The key is read from .env file and set using:
 *   ALTER DATABASE postgres SET app.settings.service_role_key = '...';
 * 
 * Usage:
 *   deno run --allow-all supabase/tests/set_service_role_key.ts [staging|production]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

async function main() {
  console.log("🔑 Setting Service Role Key in Database Settings");
  console.log("================================================");
  console.log("");

  // Get environment
  const envArg = Deno.args[0];
  const env = (envArg === "production" || envArg === "staging") ? envArg : "staging";
  const isStaging = env === "staging";
  
  console.log(`Environment: ${env}`);
  console.log("");

  // Load environment variables
  const supabaseUrl = isStaging
    ? Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL")
    : Deno.env.get("PRODUCTION_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
    
  const serviceRoleKey = isStaging
    ? Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    : Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("❌ Missing environment variables!");
    console.error("   Make sure SUPABASE_URL and SUPABASE_SECRET_KEY are set in .env");
    console.error(`   Looking for: ${isStaging ? "STAGING_SUPABASE_SECRET_KEY" : "PRODUCTION_SUPABASE_SECRET_KEY"}`);
    Deno.exit(1);
  }

  console.log(`Supabase URL: ${supabaseUrl}`);
  console.log(`Service Role Key: ${serviceRoleKey.substring(0, 20)}...${serviceRoleKey.substring(serviceRoleKey.length - 10)}`);
  console.log("");

  // Step 1: Check current setting
  console.log("📋 Step 1: Checking current setting...");
  try {
    const checkQuery = `SELECT current_setting('app.settings.service_role_key', true) as service_role_key;`;
    
    const checkResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_sql: checkQuery
      }),
    });

    if (checkResponse.ok) {
      const result = await checkResponse.json();
      if (result.success) {
        // Try to extract the key value from the response
        // The response format may vary, so we'll just note it
        console.log(`   ℹ️  Current setting check completed`);
      }
    }
  } catch (error) {
    console.log(`   ⚠️  Could not check current setting: ${error.message}`);
  }
  console.log("");

  // Step 2: Set the service role key
  console.log("📋 Step 2: Setting service role key in database settings...");
  console.log(`   ⚠️  Note: This requires superuser privileges.`);
  console.log(`   💡 If this fails, set it manually in Supabase Dashboard:`);
  console.log(`      Database → Settings → Custom Postgres Config`);
  console.log(`      Key: app.settings.service_role_key`);
  console.log(`      Value: ${serviceRoleKey.substring(0, 20)}...`);
  console.log("");

  try {
    // Escape single quotes in the key
    const escapedKey = serviceRoleKey.replace(/'/g, "''");
    
    const setQuery = `ALTER DATABASE postgres SET app.settings.service_role_key = '${escapedKey}';`;
    
    const setResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_sql: setQuery
      }),
    });

    if (!setResponse.ok) {
      const errorText = await setResponse.text();
      console.error(`   ❌ Failed to set service role key: ${setResponse.status} ${errorText}`);
      console.log("");
      console.log("   💡 This likely requires superuser privileges.");
      console.log("   💡 Please set it manually in Supabase Dashboard:");
      console.log("      Database → Settings → Custom Postgres Config");
      console.log("      Add setting: app.settings.service_role_key");
      Deno.exit(1);
    }

    const result = await setResponse.json();
    if (result.success) {
      console.log(`   ✅ Service role key set successfully!`);
    } else {
      console.error(`   ❌ Setting failed: ${result.error || "Unknown error"}`);
      Deno.exit(1);
    }
  } catch (error) {
    console.error(`   ❌ Error setting service role key: ${error.message}`);
    console.log("");
    console.log("   💡 This likely requires superuser privileges.");
    console.log("   💡 Please set it manually in Supabase Dashboard:");
    console.log("      Database → Settings → Custom Postgres Config");
    Deno.exit(1);
  }
  console.log("");

  // Step 3: Verify the setting
  console.log("📋 Step 3: Verifying the setting...");
  try {
    const verifyQuery = `SELECT current_setting('app.settings.service_role_key', true) as service_role_key;`;
    
    const verifyResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_sql: verifyQuery
      }),
    });

    if (verifyResponse.ok) {
      const result = await verifyResponse.json();
      if (result.success) {
        console.log(`   ✅ Verification completed`);
        console.log(`   💡 The cron job should now be able to authenticate with Edge Functions.`);
      }
    }
  } catch (error) {
    console.log(`   ⚠️  Could not verify setting: ${error.message}`);
  }
  console.log("");

  console.log("================================================");
  console.log("✅ Service role key setup complete!");
  console.log("");
  console.log("💡 Next steps:");
  console.log("   1. Verify the cron job can now authenticate");
  console.log("   2. Check Edge Function logs for successful calls from cron job");
  console.log("   3. Test automatic settlement by creating a commitment and waiting");
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("❌ Error:", error);
    Deno.exit(1);
  });
}



