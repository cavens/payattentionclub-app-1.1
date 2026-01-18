/**
 * Set Reconciliation Secret in app_config
 * Reads RECONCILIATION_SECRET from environment and sets it in app_config table
 * This ensures the cron job can access the same secret as the Edge Function
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const reconciliationSecret = Deno.env.get('RECONCILIATION_SECRET');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  console.error('Need: STAGING_SUPABASE_URL (or SUPABASE_URL) and STAGING_SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEY)');
  Deno.exit(1);
}

if (!reconciliationSecret) {
  console.error('❌ Missing RECONCILIATION_SECRET environment variable!');
  console.error('Set RECONCILIATION_SECRET in your .env file (should match the value in Supabase Edge Function secrets)');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔄 Setting reconciliation_secret in app_config...');
console.log('');

// Insert or update reconciliation_secret
const { data, error } = await supabase
  .from('app_config')
  .upsert({
    key: 'reconciliation_secret',
    value: reconciliationSecret,
    description: 'Secret for authenticating reconciliation cron job calls to quick-handler Edge Function',
    updated_at: new Date().toISOString()
  }, {
    onConflict: 'key'
  })
  .select();

if (error) {
  console.error('❌ Error setting reconciliation_secret:', error.message);
  Deno.exit(1);
}

console.log('✅ reconciliation_secret set successfully!');
console.log('');
console.log('📝 Next steps:');
console.log('   1. Set RECONCILIATION_SECRET in Supabase Edge Function secrets (for quick-handler)');
console.log('   2. Make sure quick-handler Edge Function is Public in Supabase Dashboard');
console.log('   3. Apply the cron job migration: supabase/migrations/20260111220100_setup_reconciliation_queue_cron.sql');
console.log('');

