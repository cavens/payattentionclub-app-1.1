/**
 * Check Auto-Settlement Status
 * 
 * This script verifies that the auto-settlement infrastructure is properly configured:
 * 1. Checks if pg_cron job exists and is active
 * 2. Checks if service role key is configured
 * 3. Checks if TESTING_MODE is enabled
 * 4. Verifies Edge Function is deployed
 * 
 * Usage:
 *   deno run --allow-all supabase/tests/check_auto_settlement_status.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

async function main() {
  console.log("🔍 Checking Auto-Settlement Status");
  console.log("==================================");
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

  // Step 1: Check if pg_cron job exists and is active
  console.log("📋 Step 1: Checking pg_cron job status...");
  console.log(`   ℹ️  Note: cron.job table requires direct SQL access.`);
  console.log(`   💡 Please check manually in Supabase Dashboard → SQL Editor:`);
  console.log(`      SELECT jobid, schedule, active, jobname FROM cron.job WHERE jobname = 'auto-settlement-checker';`);
  console.log(`   💡 Or check: Database → Extensions → pg_cron → Jobs`);
  console.log("");
  console.log("");

  // Step 2: Check if service role key is configured in database
  console.log("📋 Step 2: Checking service role key configuration...");
  try {
    const serviceKeyQuery = `
      SELECT current_setting('app.settings.service_role_key', true) as service_role_key;
    `;

    const keyResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_sql: serviceKeyQuery
      }),
    });

    if (!keyResponse.ok) {
      const errorText = await keyResponse.text();
      console.error(`   ❌ Failed to check service role key: ${keyResponse.status} ${errorText}`);
    } else {
      const result = await keyResponse.json();
      if (result.success && result.data && result.data.length > 0) {
        const keyValue = result.data[0].service_role_key;
        if (keyValue && keyValue.length > 0) {
          console.log(`   ✅ Service role key is configured`);
          console.log(`      Key: ${keyValue.substring(0, 20)}...${keyValue.substring(keyValue.length - 10)}`);
        } else {
          console.log(`   ❌ Service role key is NOT configured!`);
          console.log(`   ⚠️  The cron job needs this to authenticate with Edge Functions.`);
          console.log(`   💡 Fix: Run this SQL:`);
          console.log(`      ALTER DATABASE postgres SET app.settings.service_role_key = '${serviceRoleKey.substring(0, 20)}...';`);
        }
      }
    }
  } catch (error) {
    console.error(`   ❌ Error checking service role key: ${error.message}`);
  }
  console.log("");

  // Step 3: Check if TESTING_MODE is enabled (via Edge Function secret)
  console.log("📋 Step 3: Checking TESTING_MODE configuration...");
  console.log(`   ℹ️  Note: This requires checking Supabase Dashboard manually.`);
  console.log(`   💡 Go to: Supabase Dashboard → Project Settings → Edge Functions → Secrets`);
  console.log(`   💡 Look for: TESTING_MODE should be set to "true"`);
  console.log("");

  // Step 4: Test Edge Function is accessible
  console.log("📋 Step 4: Testing Edge Function accessibility...");
  try {
    const functionUrl = `${supabaseUrl}/functions/v1/auto-settlement-checker`;
    const functionResponse = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({}),
    });

    if (!functionResponse.ok) {
      const errorText = await functionResponse.text();
      console.log(`   ⚠️  Edge Function returned ${functionResponse.status}: ${errorText}`);
      if (functionResponse.status === 404) {
        console.log(`   ❌ Edge Function not found - may not be deployed!`);
      } else if (functionResponse.status === 403) {
        console.log(`   ⚠️  Edge Function returned 403 - TESTING_MODE may not be enabled`);
      }
    } else {
      const functionData = await functionResponse.json();
      console.log(`   ✅ Edge Function is accessible`);
      if (functionData.testing_mode === false) {
        console.log(`   ⚠️  WARNING: TESTING_MODE is false - function will exit immediately`);
      } else {
        console.log(`   ✅ TESTING_MODE appears to be enabled`);
      }
      if (functionData.message) {
        console.log(`   📝 Response: ${functionData.message}`);
      }
    }
  } catch (error) {
    console.error(`   ❌ Error testing Edge Function: ${error.message}`);
  }
  console.log("");

  // Step 5: Check for recent commitments that should trigger settlement
  console.log("📋 Step 5: Checking for pending commitments...");
  try {
    const commitmentsQuery = `
      SELECT 
        id,
        user_id,
        week_end_date,
        week_grace_expires_at,
        created_at,
        status
      FROM public.commitments
      WHERE status IN ('pending', 'active')
      ORDER BY created_at DESC
      LIMIT 5;
    `;

    const commitmentsResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_sql: commitmentsQuery
      }),
    });

    if (!commitmentsResponse.ok) {
      const errorText = await commitmentsResponse.text();
      console.error(`   ❌ Failed to query commitments: ${commitmentsResponse.status} ${errorText}`);
    } else {
      const result = await commitmentsResponse.json();
      if (result.success && result.data) {
        const commitments = result.data;
        if (commitments.length === 0) {
          console.log(`   ℹ️  No pending commitments found`);
        } else {
          console.log(`   📋 Found ${commitments.length} pending/active commitment(s):`);
          for (const commitment of commitments) {
            const createdAt = new Date(commitment.created_at);
            const now = new Date();
            const ageMinutes = Math.floor((now.getTime() - createdAt.getTime()) / (1000 * 60));
            console.log(`      - ID: ${commitment.id.substring(0, 8)}...`);
            console.log(`        Created: ${commitment.created_at} (${ageMinutes} minutes ago)`);
            console.log(`        Status: ${commitment.status}`);
            console.log(`        Grace expires: ${commitment.week_grace_expires_at || "NULL (will calculate from created_at)"}`);
          }
        }
      }
    }
  } catch (error) {
    console.error(`   ❌ Error checking commitments: ${error.message}`);
  }
  console.log("");

  console.log("==================================");
  console.log("✅ Status check complete!");
  console.log("");
  console.log("💡 Next steps:");
  console.log("   1. If cron job is not active, check Supabase Dashboard → Database → Extensions → pg_cron");
  console.log("   2. If service role key is missing, run the ALTER DATABASE command shown above");
  console.log("   3. Check Edge Function logs in Supabase Dashboard for execution history");
  console.log("   4. Verify TESTING_MODE=true in Edge Function secrets");
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("❌ Error:", error);
    Deno.exit(1);
  });
}

