/**
 * Set Reconciliation Secret in app_config - Quick Script
 * Uses the generated secret value
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

// Generated secret value
const reconciliationSecret = 'fa9c58888f388864814114b81de1f12f30188eb3aa258c85b9ba9e57d06e69c4';

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

console.log('✅ reconciliation_secret set successfully in app_config!');
console.log('');
console.log('📝 IMPORTANT: You also need to set this secret in Supabase Edge Function secrets:');
console.log('   1. Go to Supabase Dashboard → Edge Functions → quick-handler → Settings → Secrets');
console.log('   2. Add new secret:');
console.log('      Key: RECONCILIATION_SECRET');
console.log(`      Value: ${reconciliationSecret}`);
console.log('');
console.log('✅ After that, reconciliation should work!');
console.log('');

