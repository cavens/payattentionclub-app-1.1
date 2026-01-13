/**
 * Investigate Auto-Settlement Issue
 * 
 * This script investigates why automatic settlement didn't trigger:
 * 1. Checks if cron job is running
 * 2. Tests auto-settlement-checker function directly
 * 3. Analyzes commitment timing to see if grace period should have expired
 * 4. Checks Edge Function logs
 * 
 * Usage:
 *   deno run --allow-all supabase/tests/investigate_auto_settlement.ts [user_id]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

async function main() {
  console.log("🔍 Investigating Auto-Settlement Issue");
  console.log("======================================");
  console.log("");

  const userId = Deno.args[0];
  if (!userId) {
    console.error("❌ Please provide a user_id as argument");
    console.error("   Usage: deno run --allow-all supabase/tests/investigate_auto_settlement.ts <user_id>");
    Deno.exit(1);
  }

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

  console.log(`User ID: ${userId}`);
  console.log(`Environment: ${env}`);
  console.log("");

  // Step 1: Get commitment details
  console.log("📋 Step 1: Fetching commitment details...");
  const commitmentResponse = await fetch(
    `${supabaseUrl}/rest/v1/commitments?user_id=eq.${userId}&order=created_at.desc&limit=1`,
    {
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
    }
  );

  if (!commitmentResponse.ok) {
    console.error(`❌ Failed to fetch commitment: ${commitmentResponse.status}`);
    Deno.exit(1);
  }

  const commitments = await commitmentResponse.json();
  if (!commitments || commitments.length === 0) {
    console.error("❌ No commitment found for this user");
    Deno.exit(1);
  }

  const commitment = commitments[0];
  console.log(`✅ Found commitment:`);
  console.log(`   ID: ${commitment.id}`);
  console.log(`   Created: ${commitment.created_at}`);
  console.log(`   Status: ${commitment.status}`);
  console.log(`   Week end date: ${commitment.week_end_date}`);
  console.log(`   Grace expires at: ${commitment.week_grace_expires_at || "NULL"}`);
  console.log("");

  // Step 2: Calculate grace period expiration
  console.log("📋 Step 2: Calculating grace period expiration...");
  const createdAt = new Date(commitment.created_at);
  const now = new Date();
  const ageMs = now.getTime() - createdAt.getTime();
  const ageMinutes = Math.floor(ageMs / (1000 * 60));
  
  // In testing mode: 3 min week + 1 min grace = 4 min total
  const WEEK_DURATION_MS = 3 * 60 * 1000; // 3 minutes
  const GRACE_PERIOD_MS = 1 * 60 * 1000; // 1 minute
  const deadline = new Date(createdAt.getTime() + WEEK_DURATION_MS);
  const graceDeadline = new Date(deadline.getTime() + GRACE_PERIOD_MS);
  const graceExpired = graceDeadline.getTime() <= now.getTime();
  const timeSinceGraceExpired = now.getTime() - graceDeadline.getTime();
  const minutesSinceGraceExpired = Math.floor(timeSinceGraceExpired / (1000 * 60));

  console.log(`   Created at: ${createdAt.toISOString()}`);
  console.log(`   Week deadline: ${deadline.toISOString()} (3 minutes after creation)`);
  console.log(`   Grace deadline: ${graceDeadline.toISOString()} (1 minute after week deadline)`);
  console.log(`   Current time: ${now.toISOString()}`);
  console.log(`   Age: ${ageMinutes} minutes`);
  console.log(`   Grace expired: ${graceExpired ? "✅ YES" : "❌ NO"}`);
  if (graceExpired) {
    console.log(`   Time since grace expired: ${minutesSinceGraceExpired} minutes`);
  } else {
    const timeUntilGrace = graceDeadline.getTime() - now.getTime();
    const minutesUntilGrace = Math.ceil(timeUntilGrace / (1000 * 60));
    console.log(`   Time until grace expires: ${minutesUntilGrace} minutes`);
  }
  console.log("");

  // Step 3: Test auto-settlement-checker function
  console.log("📋 Step 3: Testing auto-settlement-checker function...");
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
      console.error(`   ❌ Function returned ${functionResponse.status}: ${errorText}`);
    } else {
      const functionData = await functionResponse.json();
      console.log(`   ✅ Function executed successfully`);
      console.log(`   📝 Response: ${JSON.stringify(functionData, null, 2)}`);
      
      if (functionData.checked !== undefined) {
        console.log(`   📊 Checked ${functionData.checked} commitment(s)`);
      }
      if (functionData.expired !== undefined) {
        console.log(`   📊 Found ${functionData.expired} expired commitment(s)`);
      }
      if (functionData.results) {
        console.log(`   📊 Settlement results: ${functionData.results.length} result(s)`);
        for (const result of functionData.results) {
          console.log(`      - User ${result.userId}: ${result.status}`);
          if (result.details) {
            console.log(`        Details: ${JSON.stringify(result.details)}`);
          }
        }
      }
    }
  } catch (error) {
    console.error(`   ❌ Error testing function: ${error.message}`);
  }
  console.log("");

  // Step 4: Check if commitment would be found by auto-settlement-checker
  console.log("📋 Step 4: Checking if commitment would be found...");
  const statusMatches = commitment.status === 'pending' || commitment.status === 'active';
  console.log(`   Status check: ${statusMatches ? "✅" : "❌"} (status: ${commitment.status})`);
  console.log(`   Grace expired check: ${graceExpired ? "✅" : "❌"}`);
  console.log(`   Would be found: ${statusMatches && graceExpired ? "✅ YES" : "❌ NO"}`);
  if (!statusMatches) {
    console.log(`   ⚠️  Commitment status is "${commitment.status}", but auto-settlement-checker looks for "pending" or "active"`);
  }
  if (!graceExpired) {
    console.log(`   ⚠️  Grace period has not expired yet`);
  }
  console.log("");

  // Step 5: Check cron job (manual instructions)
  console.log("📋 Step 5: Cron Job Status");
  console.log(`   ℹ️  To check if cron job is running, go to Supabase Dashboard:`);
  console.log(`   💡 Database → Extensions → pg_cron → Jobs`);
  console.log(`   💡 Or run SQL: SELECT * FROM cron.job WHERE jobname = 'auto-settlement-checker';`);
  console.log(`   💡 Check cron.job_run_details for recent executions:`);
  console.log(`      SELECT * FROM cron.job_run_details WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'auto-settlement-checker') ORDER BY start_time DESC LIMIT 10;`);
  console.log("");

  // Summary
  console.log("======================================");
  console.log("📊 SUMMARY");
  console.log("======================================");
  console.log(`Grace period expired: ${graceExpired ? "✅ YES" : "❌ NO"}`);
  if (graceExpired) {
    console.log(`Time since grace expired: ${minutesSinceGraceExpired} minutes`);
  }
  console.log(`Commitment status: ${commitment.status} ${statusMatches ? "✅" : "❌"}`);
  console.log(`Would be found by auto-settlement-checker: ${statusMatches && graceExpired ? "✅ YES" : "❌ NO"}`);
  console.log("");
  
  if (graceExpired && statusMatches) {
    console.log("💡 The commitment SHOULD have been found and settled automatically.");
    console.log("💡 Possible reasons it wasn't:");
    console.log("   1. Cron job is not running");
    console.log("   2. Cron job ran before grace period expired");
    console.log("   3. Cron job ran but function had an error");
    console.log("   4. Timing issue - cron runs every minute, might have missed the window");
    console.log("");
    console.log("💡 Check Edge Function logs in Supabase Dashboard:");
    console.log("   Edge Functions → auto-settlement-checker → Logs");
    console.log("   Look for entries around the time grace period expired");
  } else if (!graceExpired) {
    console.log("💡 Grace period has not expired yet - automatic settlement will trigger when it does.");
  } else if (!statusMatches) {
    console.log("💡 Commitment status is not 'pending' or 'active' - auto-settlement-checker won't find it.");
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error("❌ Error:", error);
    Deno.exit(1);
  });
}



