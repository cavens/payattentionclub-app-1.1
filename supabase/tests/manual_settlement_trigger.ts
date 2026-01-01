/**
 * Manual Settlement Trigger
 * 
 * Manually triggers the weekly settlement function with the required header
 * for testing mode.
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read supabase/tests/manual_settlement_trigger.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const SUPABASE_URL = Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");

if (!SUPABASE_URL) {
  console.error("❌ Missing SUPABASE_URL");
  console.error("   Set STAGING_SUPABASE_URL or SUPABASE_URL in .env");
  Deno.exit(1);
}

async function triggerSettlement() {
  console.log("🚀 Triggering manual settlement...");
  console.log(`   URL: ${SUPABASE_URL}`);
  console.log(`   Function: bright-service`);
  console.log(`   Header: x-manual-trigger: true`);
  console.log(`   Note: Function is public in testing mode (no auth required)`);
  console.log("");
  
  // In testing mode, function is public - no authentication needed
  // Just call it directly with the manual trigger header
  const url = `${SUPABASE_URL}/functions/v1/bright-service`;
  
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-manual-trigger": "true"  // Required for testing mode
      },
      body: JSON.stringify({})  // Empty body, or you can pass { targetWeek: "2025-12-31" } to target specific week
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("❌ Settlement trigger failed:");
      console.error(`   Status: ${response.status} ${response.statusText}`);
      console.error(`   Response: ${errorText}`);
      Deno.exit(1);
    }

    const data = await response.json();
    console.log("✅ Settlement triggered successfully!");
    console.log("");
    console.log("Response:", JSON.stringify(data, null, 2));
    return data;
  } catch (err) {
    console.error("❌ Unexpected error:");
    console.error(err);
    Deno.exit(1);
  }
}

await triggerSettlement();

