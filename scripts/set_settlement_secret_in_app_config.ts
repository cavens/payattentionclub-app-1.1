/**
 * Set Settlement Secret in app_config
 * Reads SETTLEMENT_SECRET from environment and sets it in app_config table
 * This ensures the cron job can access the same secret as the Edge Function
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const settlementSecret = Deno.env.get('SETTLEMENT_SECRET');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  console.error('Need: STAGING_SUPABASE_URL (or SUPABASE_URL) and STAGING_SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEY)');
  Deno.exit(1);
}

if (!settlementSecret) {
  console.error('❌ Missing SETTLEMENT_SECRET environment variable!');
  console.error('Set SETTLEMENT_SECRET in your .env file (should match the value in Supabase Edge Function secrets)');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔄 Setting settlement_secret in app_config...');
console.log('');

// Insert or update settlement_secret
const { data, error } = await supabase
  .from('app_config')
  .upsert({
    key: 'settlement_secret',
    value: settlementSecret,
    description: 'Secret for authenticating settlement cron job calls to bright-service Edge Function',
    updated_at: new Date().toISOString()
  }, {
    onConflict: 'key'
  })
  .select();

if (error) {
  console.error('❌ Error setting settlement_secret:', error.message);
  Deno.exit(1);
}

console.log('✅ settlement_secret set successfully!');
console.log('');

// Verify it's set (but don't show the actual secret value)
const { data: verify, error: verifyError } = await supabase
  .from('app_config')
  .select('key, value, description, updated_at')
  .eq('key', 'settlement_secret')
  .single();

if (verifyError) {
  console.error('⚠️  Warning: Could not verify setting:', verifyError.message);
} else {
  console.log('📋 Current setting:');
  console.log(`   Key: ${verify.key}`);
  console.log(`   Value: ${verify.value ? '***' + verify.value.slice(-4) : 'N/A'} (hidden for security)`);
  console.log(`   Description: ${verify.description || 'N/A'}`);
  console.log(`   Updated: ${verify.updated_at}`);
  console.log('');
}

console.log('✅ Settlement secret is now configured in app_config!');
console.log('');
console.log('The cron job can now authenticate with bright-service Edge Function.');
console.log('');


