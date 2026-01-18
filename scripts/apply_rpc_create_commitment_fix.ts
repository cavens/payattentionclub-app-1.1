#!/usr/bin/env -S deno run --allow-net --allow-read --allow-env

/**
 * Script to apply rpc_create_commitment function fix
 * This updates the function signature to match what the Edge Function expects
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = 
  Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || 
  Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY");

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("❌ Missing required environment variables:");
  console.error("   SUPABASE_URL:", SUPABASE_URL ? "✅" : "❌");
  console.error("   STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY:", SUPABASE_SERVICE_ROLE_KEY ? "✅" : "❌");
  Deno.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// Read the RPC function SQL
const rpcFunctionSql = await Deno.readTextFile(
  "./supabase/remote_rpcs/rpc_create_commitment.sql"
);

console.log("📝 Applying rpc_create_commitment function update...");
console.log("   This will update the function signature to include all required parameters");

try {
  // Execute the SQL
  const { error } = await supabase.rpc("exec_sql", {
    sql: rpcFunctionSql
  });

  if (error) {
    // Try direct SQL execution via REST API
    console.log("⚠️  RPC exec_sql not available, trying direct SQL execution...");
    
    // Use the REST API to execute SQL
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/exec_sql`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`
      },
      body: JSON.stringify({ sql: rpcFunctionSql })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("❌ Failed to apply function:", errorText);
      console.log("\n📋 Manual Application Required:");
      console.log("   1. Go to Supabase Dashboard → SQL Editor");
      console.log("   2. Copy the contents of: supabase/remote_rpcs/rpc_create_commitment.sql");
      console.log("   3. Paste and execute in the SQL Editor");
      Deno.exit(1);
    }
  }

  console.log("✅ rpc_create_commitment function updated successfully!");
  console.log("\n📋 Function signature:");
  console.log("   - p_deadline_date (date)");
  console.log("   - p_limit_minutes (integer)");
  console.log("   - p_penalty_per_minute_cents (integer)");
  console.log("   - p_app_count (integer)");
  console.log("   - p_apps_to_limit (jsonb)");
  console.log("   - p_saved_payment_method_id (text, optional)");
  console.log("   - p_deadline_timestamp (timestamptz, optional)");
} catch (error) {
  console.error("❌ Error applying function:", error);
  console.log("\n📋 Manual Application Required:");
  console.log("   1. Go to Supabase Dashboard → SQL Editor");
  console.log("   2. Copy the contents of: supabase/remote_rpcs/rpc_create_commitment.sql");
  console.log("   3. Paste and execute in the SQL Editor");
  Deno.exit(1);
}



