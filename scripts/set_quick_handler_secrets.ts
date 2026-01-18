/**
 * Set quick-handler Edge Function Secrets
 * Reads values from app_config and sets them as Edge Function secrets
 * 
 * Usage:
 *   deno run --allow-net --allow-env scripts/set_quick_handler_secrets.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const projectRef = Deno.env.get('SUPABASE_PROJECT_REF') || 'auqujbppoytkeqdsgrbl';

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  console.error('Need: STAGING_SUPABASE_URL (or SUPABASE_URL) and STAGING_SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEY)');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔄 Reading values from app_config...');
console.log('');

// Get values from app_config
const { data: config, error: configError } = await supabase
  .from('app_config')
  .select('key, value')
  .in('key', ['supabase_url', 'service_role_key', 'reconciliation_secret']);

if (configError) {
  console.error('❌ Failed to read app_config:', configError.message);
  Deno.exit(1);
}

const configMap = new Map(config?.map(c => [c.key, c.value]) || []);

const supabaseUrlValue = configMap.get('supabase_url');
const secretKeyValue = configMap.get('service_role_key');
const reconciliationSecret = configMap.get('reconciliation_secret');

if (!supabaseUrlValue || !secretKeyValue) {
  console.error('❌ Missing required values in app_config!');
  console.error('Need: supabase_url and service_role_key');
  Deno.exit(1);
}

console.log('✅ Found values in app_config:');
console.log(`   SUPABASE_URL: ${supabaseUrlValue.substring(0, 30)}...`);
console.log(`   SECRET_KEY: ${secretKeyValue.substring(0, 20)}...`);
console.log(`   RECONCILIATION_SECRET: ${reconciliationSecret ? 'SET' : 'MISSING'}`);
console.log('');

// Get Stripe key from environment (not in app_config)
const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY_TEST') || Deno.env.get('STRIPE_SECRET_KEY');
if (!stripeSecretKey) {
  console.warn('⚠️  STRIPE_SECRET_KEY not found in environment - you may need to set it manually');
}

console.log('📋 Setting Edge Function secrets via Supabase CLI...');
console.log('');
console.log('Run these commands:');
console.log('');
console.log(`supabase secrets set SUPABASE_URL="${supabaseUrlValue}" --project-ref ${projectRef}`);
console.log(`supabase secrets set STAGING_SUPABASE_SECRET_KEY="${secretKeyValue}" --project-ref ${projectRef}`);
if (reconciliationSecret) {
  console.log(`supabase secrets set RECONCILIATION_SECRET="${reconciliationSecret}" --project-ref ${projectRef}`);
}
if (stripeSecretKey) {
  console.log(`supabase secrets set STRIPE_SECRET_KEY_TEST="${stripeSecretKey}" --project-ref ${projectRef}`);
}
console.log('');
console.log('Or set them manually in Dashboard:');
console.log(`  https://supabase.com/dashboard/project/${projectRef}/functions/quick-handler/settings`);
console.log('');
console.log('Required secrets:');
console.log('  - SUPABASE_URL');
console.log('  - STAGING_SUPABASE_SECRET_KEY (or PRODUCTION_SUPABASE_SECRET_KEY)');
console.log('  - RECONCILIATION_SECRET');
console.log('  - STRIPE_SECRET_KEY_TEST (or STRIPE_SECRET_KEY)');

