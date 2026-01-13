/**
 * Apply the reconciliation below-minimum fix migration
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const supabaseUrl = Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Missing environment variables!");
  console.error("   Make sure STAGING_SUPABASE_URL and STAGING_SUPABASE_SECRET_KEY are set in .env");
  Deno.exit(1);
}

// Read the migration file
const migrationPath = "supabase/migrations/20260111184413_fix_reconciliation_below_minimum.sql";
const migrationSQL = await Deno.readTextFile(migrationPath);

console.log("🔄 Applying reconciliation below-minimum fix...");
console.log("");

// Apply via Supabase REST API using rpc_execute_sql
const response = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_execute_sql`, {
  method: "POST",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    p_sql: migrationSQL
  })
});

if (!response.ok) {
  const errorText = await response.text();
  console.error(`❌ Failed to apply migration: ${response.status} ${errorText}`);
  Deno.exit(1);
}

const result = await response.json();
if (result.success) {
  console.log("✅ Migration applied successfully!");
  console.log("");
} else {
  console.error(`❌ Migration failed: ${result.error || "Unknown error"}`);
  Deno.exit(1);
}



