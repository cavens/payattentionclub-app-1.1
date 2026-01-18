/**
 * Set Stripe Secret Key for quick-handler Edge Function
 * Matches the pattern used by bright-service
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/set_stripe_secret_for_quick_handler.ts
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";

const projectRef = Deno.env.get('SUPABASE_PROJECT_REF') || 'auqujbppoytkeqdsgrbl';

// Get Stripe key from environment (same as bright-service uses)
const stripeSecretKeyTest = Deno.env.get('STRIPE_SECRET_KEY_TEST');
const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY');
const stripeKey = stripeSecretKeyTest || stripeSecretKey;

if (!stripeKey) {
  console.error('❌ STRIPE_SECRET_KEY_TEST or STRIPE_SECRET_KEY not found in environment!');
  console.error('');
  console.error('Set it in your .env file:');
  console.error('  STRIPE_SECRET_KEY_TEST=sk_test_...');
  console.error('  OR');
  console.error('  STRIPE_SECRET_KEY=sk_test_...');
  console.error('');
  console.error('Then run this script again.');
  Deno.exit(1);
}

console.log('🔄 Setting Stripe secret key for quick-handler...');
console.log(`   Using: ${stripeKey.substring(0, 20)}...`);
console.log('');

// Set STRIPE_SECRET_KEY_TEST (preferred, matches bright-service)
if (stripeSecretKeyTest) {
  console.log('Setting STRIPE_SECRET_KEY_TEST...');
  const { success } = await new Deno.Command('supabase', {
    args: [
      'secrets',
      'set',
      `STRIPE_SECRET_KEY_TEST=${stripeSecretKeyTest}`,
      '--project-ref',
      projectRef
    ],
    stdout: 'piped',
    stderr: 'piped'
  }).output();

  if (success) {
    console.log('✅ STRIPE_SECRET_KEY_TEST set successfully');
  } else {
    console.error('❌ Failed to set STRIPE_SECRET_KEY_TEST');
    console.error('   You may need to set it manually in Dashboard');
  }
} else if (stripeSecretKey) {
  console.log('Setting STRIPE_SECRET_KEY...');
  const { success } = await new Deno.Command('supabase', {
    args: [
      'secrets',
      'set',
      `STRIPE_SECRET_KEY=${stripeSecretKey}`,
      '--project-ref',
      projectRef
    ],
    stdout: 'piped',
    stderr: 'piped'
  }).output();

  if (success) {
    console.log('✅ STRIPE_SECRET_KEY set successfully');
  } else {
    console.error('❌ Failed to set STRIPE_SECRET_KEY');
    console.error('   You may need to set it manually in Dashboard');
  }
}

console.log('');
console.log('✅ Done! quick-handler should now have Stripe credentials.');
console.log('');
console.log('Next: Reset the queue entry and test:');
console.log('  UPDATE reconciliation_queue SET status = \'pending\', processed_at = NULL WHERE id = \'...\';');

