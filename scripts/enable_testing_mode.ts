/**
 * Enable Testing Mode
 * Sets testing_mode in app_config table
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

console.log('🔄 Enabling Testing Mode...');
console.log('');

// Check if app_config table exists
const { data: tableCheck, error: tableError } = await supabase
  .from('app_config')
  .select('key')
  .limit(1);

if (tableError && tableError.code === '42P01') {
  console.error('❌ app_config table does not exist!');
  console.error('You may need to create it first or run the migration.');
  console.error('');
  console.error('SQL to create table:');
  console.log(`
CREATE TABLE IF NOT EXISTS public.app_config (
  key text PRIMARY KEY,
  value text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
  `);
  Deno.exit(1);
}

// Insert or update testing_mode
const { data, error } = await supabase
  .from('app_config')
  .upsert({
    key: 'testing_mode',
    value: 'true',
    description: 'Enable compressed timeline testing (3 min week, 1 min grace)',
    updated_at: new Date().toISOString()
  }, {
    onConflict: 'key'
  })
  .select();

if (error) {
  console.error('❌ Error enabling testing mode:', error.message);
  Deno.exit(1);
}

console.log('✅ Testing mode enabled successfully!');
console.log('');

// Verify it's set
const { data: verify, error: verifyError } = await supabase
  .from('app_config')
  .select('key, value, description')
  .eq('key', 'testing_mode')
  .single();

if (verifyError) {
  console.error('⚠️  Warning: Could not verify setting:', verifyError.message);
} else {
  console.log('📋 Current setting:');
  console.log(`   Key: ${verify.key}`);
  console.log(`   Value: ${verify.value}`);
  console.log(`   Description: ${verify.description}`);
  console.log('');
}

console.log('✅ Testing mode is now active!');
console.log('');
console.log('Effects:');
console.log('  - Week duration: 3 minutes (instead of 7 days)');
console.log('  - Grace period: 1 minute (instead of 24 hours)');
console.log('  - Reconciliation queue: Processes every 1 minute (instead of 10 minutes)');
console.log('');
console.log('Note: You also need to set TESTING_MODE=true in Supabase Edge Function secrets');
console.log('  Go to: Supabase Dashboard → Project Settings → Edge Functions → Environment Variables');


