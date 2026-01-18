/**
 * Apply Minimum Authorization Migration
 * Changes minimum authorization from $15 to $5
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/apply_minimum_authorization_migration.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  console.error('   Required: SUPABASE_URL (or STAGING_SUPABASE_URL)');
  console.error('   Required: SUPABASE_SECRET_KEY (or STAGING_SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY)');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔄 Applying Minimum Authorization Migration');
console.log('=' .repeat(60));
console.log('Migration: Change minimum from $15.00 to $5.00');
console.log('');

// Read migration file
const migrationPath = new URL('../supabase/migrations/20260117150000_change_minimum_authorization_to_5_dollars.sql', import.meta.url).pathname;
let migrationSQL: string;

try {
  migrationSQL = await Deno.readTextFile(migrationPath);
} catch (error) {
  console.error(`❌ Failed to read migration file: ${migrationPath}`);
  console.error(`   Error: ${error.message}`);
  Deno.exit(1);
}

console.log('📄 Migration SQL loaded');
console.log('');

// Split into individual statements (PostgreSQL functions need to be executed separately)
// The migration file contains a single CREATE OR REPLACE FUNCTION statement
console.log('🚀 Executing migration...');
console.log('');

try {
  const { data, error } = await supabase.rpc('exec_sql', {
    sql: migrationSQL
  });

  if (error) {
    // If exec_sql doesn't exist, try direct query
    console.log('⚠️  exec_sql RPC not available, trying direct query...');
    
    // Execute the SQL directly using the REST API
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': supabaseKey,
        'Authorization': `Bearer ${supabaseKey}`
      },
      body: JSON.stringify({ sql: migrationSQL })
    });

    if (!response.ok) {
      // Try alternative: execute via PostgREST or direct SQL
      console.log('⚠️  RPC method not available, using alternative approach...');
      console.log('');
      console.log('📋 Please apply this migration manually:');
      console.log('');
      console.log('1. Go to Supabase Dashboard → SQL Editor');
      console.log('2. Copy and paste the SQL from:');
      console.log(`   ${migrationPath}`);
      console.log('3. Execute the SQL');
      console.log('');
      console.log('Or use Supabase CLI:');
      console.log(`   supabase db push`);
      console.log('');
      Deno.exit(0);
    }
  }

  console.log('✅ Migration applied successfully!');
  console.log('');
  console.log('📊 Verifying change...');
  console.log('');

  // Verify by checking the function
  const { data: testResult, error: testError } = await supabase
    .rpc('calculate_max_charge_cents', {
      p_deadline_ts: new Date(Date.now() + 1000).toISOString(), // 1 second from now (will hit minimum)
      p_limit_minutes: 60,
      p_penalty_per_minute_cents: 10,
      p_app_count: 1
    });

  if (testError) {
    console.log('⚠️  Could not verify (this is okay if function signature changed)');
    console.log(`   Error: ${testError.message}`);
  } else {
    if (testResult === 500) {
      console.log('✅ Verification successful! Minimum is now $5.00 (500 cents)');
    } else {
      console.log(`⚠️  Unexpected result: ${testResult} cents (expected 500)`);
    }
  }

} catch (error) {
  console.error('❌ Error applying migration:');
  console.error(`   ${error.message}`);
  console.log('');
  console.log('📋 Please apply this migration manually:');
  console.log('');
  console.log('1. Go to Supabase Dashboard → SQL Editor');
  console.log('2. Copy and paste the SQL from:');
  console.log(`   ${migrationPath}`);
  console.log('3. Execute the SQL');
  console.log('');
  Deno.exit(1);
}

console.log('');
console.log('✅ Done!');

