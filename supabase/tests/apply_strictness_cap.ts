/**
 * Apply the strictness multiplier cap migration
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const supabaseUrl = Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  console.error("❌ Missing environment variables!");
  Deno.exit(1);
}

// Read the migration file
const migrationPath = "supabase/migrations/20260101000000_cap_strictness_multiplier.sql";
const migrationSQL = await Deno.readTextFile(migrationPath);

console.log("🔄 Applying strictness multiplier cap migration...");
console.log("");

// Apply the migration via Supabase REST API (using rpc or direct SQL)
// Note: We'll use the Supabase REST API to execute the SQL
const response = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql`, {
  method: "POST",
  headers: {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    sql: migrationSQL
  })
});

// Actually, Supabase doesn't have an exec_sql RPC by default
// We need to apply this via the Supabase dashboard SQL editor or use psql
console.log("⚠️  This migration needs to be applied manually.");
console.log("");
console.log("Option 1: Apply via Supabase Dashboard");
console.log("  1. Go to: https://supabase.com/dashboard/project/YOUR_PROJECT/sql/new");
console.log("  2. Copy and paste the SQL from: supabase/migrations/20260101000000_cap_strictness_multiplier.sql");
console.log("  3. Click 'Run'");
console.log("");
console.log("Option 2: Apply via Supabase CLI (if migration history is fixed)");
console.log("  supabase db push");
console.log("");
console.log("The migration file is ready at:");
console.log(`  ${migrationPath}`);


