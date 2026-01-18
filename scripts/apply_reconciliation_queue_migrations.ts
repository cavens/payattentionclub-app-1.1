/**
 * Apply reconciliation queue migrations
 * Attempts to apply via Supabase CLI, falls back to manual instructions
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const migrations = [
  "supabase/migrations/20260111220000_create_reconciliation_queue.sql",
  "supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql",
];

console.log("🔄 Applying Reconciliation Queue Migrations");
console.log("=" .repeat(60));
console.log("");

// Check if Supabase CLI is available
const cliCheck = new Deno.Command("which", {
  args: ["supabase"],
  stdout: "piped",
  stderr: "piped",
});

const cliResult = await cliCheck.output();
const hasCli = cliResult.code === 0;

if (hasCli) {
  console.log("✅ Supabase CLI found");
  console.log("");
  
  // Try to check if project is linked
  const statusCheck = new Deno.Command("supabase", {
    args: ["status"],
    stdout: "piped",
    stderr: "piped",
  });
  
  const statusResult = await statusCheck.output();
  const statusOutput = new TextDecoder().decode(statusResult.stdout);
  const statusError = new TextDecoder().decode(statusResult.stderr);
  
  // Check if linked to remote project
  if (statusOutput.includes("Linked Project") || statusOutput.includes("Project URL")) {
    console.log("✅ Project appears to be linked");
    console.log("");
    console.log("Attempting to apply migrations via 'supabase db push'...");
    console.log("");
    
    // Try to push migrations
    const pushCmd = new Deno.Command("supabase", {
      args: ["db", "push"],
      stdout: "piped",
      stderr: "piped",
    });
    
    const pushResult = await pushCmd.output();
    const pushOutput = new TextDecoder().decode(pushResult.stdout);
    const pushError = new TextDecoder().decode(pushResult.stderr);
    
    if (pushResult.code === 0) {
      console.log("✅ Migrations applied successfully!");
      console.log(pushOutput);
      Deno.exit(0);
    } else {
      console.log("⚠️  'supabase db push' failed or no changes detected");
      console.log(pushError);
      console.log("");
      console.log("This might mean:");
      console.log("  - Migrations were already applied");
      console.log("  - Project is not properly linked");
      console.log("  - Need to apply manually");
      console.log("");
    }
  } else {
    console.log("⚠️  Project not linked to remote");
    console.log("");
    console.log("To link your project:");
    console.log("  1. Get your project ref from Supabase Dashboard");
    console.log("  2. Run: supabase link --project-ref YOUR_PROJECT_REF");
    console.log("");
  }
} else {
  console.log("⚠️  Supabase CLI not found");
  console.log("");
}

// Fallback: Provide manual instructions
console.log("📋 Manual Application Instructions");
console.log("=" .repeat(60));
console.log("");
console.log("Since automatic application isn't available, apply migrations manually:");
console.log("");
console.log("Option 1: Via Supabase Dashboard (Recommended)");
console.log("  1. Go to: https://supabase.com/dashboard");
console.log("  2. Select your project");
console.log("  3. Go to: SQL Editor → New Query");
console.log("  4. Copy and paste each migration SQL below");
console.log("  5. Click 'Run' for each migration");
console.log("");
console.log("Option 2: Via Supabase CLI (if linked)");
console.log("  supabase db push");
console.log("");
console.log("=" .repeat(60));
console.log("");

// Read and display each migration
for (const migrationPath of migrations) {
  try {
    const migrationSQL = await Deno.readTextFile(migrationPath);
    const migrationName = migrationPath.split("/").pop();
    
    console.log(`📄 Migration: ${migrationName}`);
    console.log("-" .repeat(60));
    console.log(migrationSQL);
    console.log("-" .repeat(60));
    console.log("");
  } catch (error) {
    console.error(`❌ Error reading ${migrationPath}:`, error);
  }
}

console.log("=" .repeat(60));
console.log("");
console.log("✅ Migration files are ready to apply");
console.log("");
console.log("After applying migrations:");
console.log("  1. Verify table exists: SELECT * FROM reconciliation_queue LIMIT 1;");
console.log("  2. Verify RPC function exists: SELECT pg_get_functiondef('public.process_reconciliation_queue'::regproc);");
console.log("  3. Verify cron jobs: SELECT * FROM cron.job WHERE jobname LIKE '%reconcile%';");
console.log("");


