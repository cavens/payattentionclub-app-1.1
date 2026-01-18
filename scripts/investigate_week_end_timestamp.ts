/**
 * Investigate week_end_timestamp Issue
 * Checks why week_end_timestamp is not being set in testing mode
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/investigate_week_end_timestamp.ts [commitment_id]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const commitmentId = Deno.args[0] || '7aaba52d-14ef-4ea2-b784-56cba49c919f';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Investigating week_end_timestamp Issue');
console.log('=' .repeat(60));
console.log(`Commitment ID: ${commitmentId}`);
console.log('');

// Get commitment
const { data: commitment, error: commitError } = await supabase
  .from('commitments')
  .select('*')
  .eq('id', commitmentId)
  .single();

if (!commitment) {
  console.error(`❌ Commitment not found: ${commitError?.message}`);
  Deno.exit(1);
}

console.log('1. Commitment Analysis:');
console.log(`   Created: ${commitment.created_at}`);
console.log(`   Week End Date: ${commitment.week_end_date}`);
console.log(`   Week End Timestamp: ${commitment.week_end_timestamp || '❌ NULL'}`);
console.log('');

// Calculate what it should be
const created = new Date(commitment.created_at);
const expectedDeadline = new Date(created.getTime() + (3 * 60 * 1000)); // 3 minutes
console.log('2. Expected Values (Testing Mode):');
console.log(`   Created At: ${created.toISOString()}`);
console.log(`   Expected Deadline: ${expectedDeadline.toISOString()}`);
console.log(`   Expected Week End Date: ${expectedDeadline.toISOString().split('T')[0]}`);
console.log('');

// Check if TESTING_MODE is set in super-service
console.log('3. Testing Mode Check:');
console.log('   ⚠️  Cannot check Edge Function secrets via API');
console.log('   Manual check required:');
console.log('   1. Go to Supabase Dashboard');
console.log('   2. Project Settings → Edge Functions → super-service → Settings → Secrets');
console.log('   3. Look for: TESTING_MODE (should be "true")');
console.log('');

// Check database config
const { data: config } = await supabase
  .from('app_config')
  .select('*')
  .eq('key', 'testing_mode')
  .single();

if (config && config.value === 'true') {
  console.log('   ✅ Database config: testing_mode = true');
} else {
  console.log('   ❌ Database config: testing_mode = false or not set');
}

console.log('');

// Check RPC function signature
console.log('4. RPC Function Check:');
console.log('   Checking if rpc_create_commitment accepts p_deadline_timestamp...');
const { data: rpcInfo, error: rpcError } = await supabase.rpc('rpc_create_commitment', {
  p_deadline_date: '2026-01-17',
  p_limit_minutes: 1,
  p_penalty_per_minute_cents: 100,
  p_app_count: 1,
  p_apps_to_limit: { app_bundle_ids: [] },
  p_deadline_timestamp: null
});

if (rpcError) {
  if (rpcError.message.includes('p_deadline_timestamp')) {
    console.log('   ✅ RPC function accepts p_deadline_timestamp parameter');
  } else {
    console.log(`   ⚠️  RPC error: ${rpcError.message}`);
  }
} else {
  console.log('   ✅ RPC function call succeeded (test call)');
}

console.log('');

// Summary
console.log('📊 Root Cause Analysis');
console.log('=' .repeat(60));
console.log('Possible causes for NULL week_end_timestamp:');
console.log('');
console.log('1. TESTING_MODE not set in super-service Edge Function secrets');
console.log('   → Check Supabase Dashboard → Edge Functions → super-service → Settings → Secrets');
console.log('');
console.log('2. super-service not passing p_deadline_timestamp to RPC');
console.log('   → Check super-service/index.ts line 103');
console.log('   → Should set: deadlineTimestampForRPC = formatDeadlineDate(deadline)');
console.log('');
console.log('3. RPC function not storing the timestamp');
console.log('   → Check rpc_create_commitment.sql');
console.log('   → Should set: week_end_timestamp = p_deadline_timestamp');
console.log('');
console.log('4. Migration not applied');
console.log('   → Check if migration 20260115220000_add_week_end_timestamp_to_commitments.sql was applied');
console.log('');


