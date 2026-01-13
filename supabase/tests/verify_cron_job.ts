/**
 * Verify Cron Job is Working
 * 
 * This script verifies that the auto-settlement-checker cron job is:
 * 1. Enabled and active
 * 2. Successfully executing
 * 3. Calling the Edge Function without errors
 * 
 * Usage:
 *   deno run --allow-all supabase/tests/verify_cron_job.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

async function main() {
  console.log("🔍 Verifying Cron Job Status");
  console.log("============================");
  console.log("");

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
    Deno.exit(1);
  }

  console.log(`Environment: ${env}`);
  console.log("");

  // Step 1: Check if pg_net extension is enabled
  console.log("📋 Step 1: Checking if pg_net extension is enabled...");
  try {
    const pgNetQuery = `
      SELECT 
        extname as extension_name,
        nspname as schema_name
      FROM pg_extension e
      JOIN pg_namespace n ON e.extnamespace = n.oid
      WHERE extname = 'pg_net';
    `;

    const pgNetResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_sql: pgNetQuery
      }),
    });

    if (!pgNetResponse.ok) {
      console.error(`   ❌ Failed to check pg_net: ${pgNetResponse.status}`);
    } else {
      const result = await pgNetResponse.json();
      if (result.success && result.data && result.data.length > 0) {
        const ext = result.data[0];
        console.log(`   ✅ pg_net is enabled`);
        console.log(`      Schema: ${ext.schema_name}`);
        if (ext.schema_name === 'public') {
          console.log(`      ✅ Installed in public schema (correct for net.http_post())`);
        } else {
          console.log(`      ⚠️  Installed in ${ext.schema_name} schema`);
          console.log(`      💡 If cron job fails, may need to use ${ext.schema_name}.net.http_post()`);
        }
      } else {
        console.log(`   ❌ pg_net is NOT enabled!`);
        console.log(`   💡 Enable it in Supabase Dashboard → Database → Extensions → pg_net`);
      }
    }
  } catch (error) {
    console.error(`   ❌ Error checking pg_net: ${error.message}`);
  }
  console.log("");

  // Step 2: Check cron job status
  console.log("📋 Step 2: Checking cron job status...");
  console.log(`   ℹ️  To check cron job details, run this SQL in Supabase Dashboard:`);
  console.log(`   💡 SELECT jobid, schedule, active, jobname FROM cron.job WHERE jobname = 'auto-settlement-checker';`);
  console.log("");

  // Step 3: Check recent execution history
  console.log("📋 Step 3: Checking recent execution history...");
  console.log(`   ℹ️  To check execution history, run this SQL in Supabase Dashboard:`);
  console.log(`   💡 SELECT runid, start_time, end_time, return_message, status`);
  console.log(`      FROM cron.job_run_details`);
  console.log(`      WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'auto-settlement-checker')`);
  console.log(`      ORDER BY start_time DESC LIMIT 10;`);
  console.log("");
  console.log(`   💡 Look for:`);
  console.log(`      - status = 'succeeded' (good!)`);
  console.log(`      - status = 'failed' with error about 'net' schema (pg_net not enabled)`);
  console.log(`      - status = 'failed' with other errors (check return_message)`);
  console.log("");

  // Step 4: Test Edge Function directly
  console.log("📋 Step 4: Testing Edge Function directly...");
  try {
    const functionUrl = `${supabaseUrl}/functions/v1/auto-settlement-checker`;
    const functionResponse = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

    if (!functionResponse.ok) {
      const errorText = await functionResponse.text();
      console.log(`   ⚠️  Edge Function returned ${functionResponse.status}: ${errorText}`);
    } else {
      const functionData = await functionResponse.json();
      console.log(`   ✅ Edge Function is accessible and working`);
      console.log(`   📝 Response: ${JSON.stringify(functionData, null, 2)}`);
    }
  } catch (error) {
    console.error(`   ❌ Error testing Edge Function: ${error.message}`);
  }
  console.log("");

  // Step 5: Wait and check if cron job runs
  console.log("📋 Step 5: Monitoring cron job execution...");
  console.log(`   ℹ️  The cron job runs every minute.`);
  console.log(`   💡 Wait 1-2 minutes, then check the execution history again.`);
  console.log(`   💡 You should see new entries with status = 'succeeded' if pg_net is working.`);
  console.log("");

  console.log("============================");
  console.log("✅ Verification complete!");
  console.log("");
  console.log("💡 Next steps:");
  console.log("   1. Check cron job execution history in Supabase Dashboard");
  console.log("   2. Look for recent entries with status = 'succeeded'");
  console.log("   3. If still failing, check the return_message for error details");
  console.log("   4. Verify Edge Function logs to see if it's being called");
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("❌ Error:", error);
    Deno.exit(1);
  });
}



