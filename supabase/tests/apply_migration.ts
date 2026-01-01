/**
 * Apply the strictness multiplier cap migration directly
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

// Split the SQL into individual statements and execute them
// Since Supabase REST API doesn't support multi-statement execution directly,
// we'll need to execute the CREATE OR REPLACE FUNCTION statement
// The function definition is the main part we need

// Extract just the function creation part (everything from CREATE to $$;)
const functionMatch = migrationSQL.match(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;/);
if (!functionMatch) {
  console.error("❌ Could not extract function definition from migration file");
  Deno.exit(1);
}

const functionSQL = functionMatch[0];

// Execute via Supabase REST API using the PostgREST endpoint
// We'll use the rpc endpoint or try to execute via a custom function
// Actually, the best way is to use the Supabase Management API or SQL Editor API
// But since we don't have direct SQL execution, let's try using psql via connection string

console.log("⚠️  Direct SQL execution via API is not available.");
console.log("Applying migration via Supabase Dashboard SQL Editor...");
console.log("");

// Actually, let's try using the Supabase CLI if available
console.log("Attempting to apply via Supabase CLI...");

// Try to get the database connection string from environment
const dbUrl = Deno.env.get("DATABASE_URL") || 
              Deno.env.get("STAGING_DATABASE_URL") || 
              Deno.env.get("PRODUCTION_DATABASE_URL");

if (dbUrl) {
  console.log("Found database URL, attempting direct connection...");
  // We would need psql for this, which might not be available
  console.log("Note: psql is required for direct database connection");
}

console.log("");
console.log("📋 To apply this migration manually:");
console.log("");
console.log("1. Go to Supabase Dashboard:");
console.log(`   https://supabase.com/dashboard/project/${supabaseUrl.split('//')[1].split('.')[0]}/sql/new`);
console.log("");
console.log("2. Copy and paste the following SQL:");
console.log("");
console.log("---");
console.log(migrationSQL);
console.log("---");
console.log("");
console.log("3. Click 'Run' to execute");
console.log("");
console.log("Or use Supabase CLI:");
console.log("  supabase db push");


