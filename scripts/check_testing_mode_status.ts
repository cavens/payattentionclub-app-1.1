/**
 * Check Testing Mode Status
 * Verifies if TESTING_MODE is set in Supabase secrets and database config
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/check_testing_mode_status.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  console.error('Need: STAGING_SUPABASE_URL (or SUPABASE_URL) and STAGING_SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEY)');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Checking Testing Mode Status');
console.log('=' .repeat(60));
console.log('');

// Check database app_config
console.log('1. Database app_config table:');
const { data: config, error: configError } = await supabase
  .from('app_config')
  .select('*')
  .eq('key', 'testing_mode')
  .single();

if (config) {
  console.log(`   ✅ Found: testing_mode = ${config.value}`);
  console.log(`   Description: ${config.description || 'N/A'}`);
  console.log(`   Updated: ${config.updated_at}`);
} else if (configError?.code === 'PGRST116') {
  console.log('   ❌ Not found in app_config table');
} else {
  console.log(`   ⚠️  Error: ${configError?.message}`);
}

console.log('');

// Note: We can't directly check Edge Function secrets via API
// They need to be checked in Supabase Dashboard
console.log('2. Edge Function Environment Variables:');
console.log('   ⚠️  Cannot check via API - must check in Supabase Dashboard');
console.log('   Go to: Project Settings → Edge Functions → testing-command-runner → Settings → Secrets');
console.log('   Look for: TESTING_MODE (should be "true")');
console.log('');

// Check a recent commitment to see if week_end_timestamp is being set
console.log('3. Recent Commitment Check:');
const { data: commitments, error: commitError } = await supabase
  .from('commitments')
  .select('id, created_at, week_end_date, week_end_timestamp, status')
  .order('created_at', { ascending: false })
  .limit(3);

if (commitments && commitments.length > 0) {
  console.log(`   Found ${commitments.length} recent commitment(s):`);
  commitments.forEach((c, i) => {
    console.log(`   ${i + 1}. ID: ${c.id.substring(0, 8)}...`);
    console.log(`      Created: ${c.created_at}`);
    console.log(`      Week End Date: ${c.week_end_date}`);
    console.log(`      Week End Timestamp: ${c.week_end_timestamp || '❌ NULL'}`);
    console.log(`      Status: ${c.status}`);
    if (!c.week_end_timestamp && c.status === 'pending') {
      console.log(`      ⚠️  WARNING: week_end_timestamp is NULL in pending commitment!`);
    }
  });
} else {
  console.log('   ℹ️  No commitments found');
}

console.log('');
console.log('📊 Summary');
console.log('=' .repeat(60));
if (config && config.value === 'true') {
  console.log('✅ Testing mode is enabled in database (app_config)');
} else {
  console.log('❌ Testing mode is NOT enabled in database');
}

console.log('⚠️  Edge Function secrets must be checked manually in Supabase Dashboard');
console.log('');


