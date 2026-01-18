import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const userId = Deno.args[0] || 'bf800520-094c-4a20-96f0-1afe99d0c05d';
const weekStartDate = Deno.args[1] || '2026-01-17';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

console.log('🔄 Manually Triggering Reconciliation');
console.log('='.repeat(60));
console.log(`User ID: ${userId}`);
console.log(`Week Start Date: ${weekStartDate}`);
console.log('');

// Check current status
const supabase = createClient(supabaseUrl, supabaseKey);

const { data: penalty, error: penaltyError } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', userId)
  .eq('week_start_date', weekStartDate)
  .single();

if (penaltyError) {
  console.error(`❌ Error fetching penalty: ${penaltyError.message}`);
  Deno.exit(1);
}

if (!penalty) {
  console.error('❌ No penalty record found');
  Deno.exit(1);
}

console.log('📊 Current Status:');
console.log(`   Needs Reconciliation: ${penalty.needs_reconciliation}`);
console.log(`   Reconciliation Delta: ${penalty.reconciliation_delta_cents} cents`);
console.log(`   Charged Amount: ${penalty.charged_amount_cents} cents`);
console.log(`   Actual Amount: ${penalty.actual_amount_cents} cents`);
console.log(`   Refund Amount: ${penalty.refund_amount_cents} cents`);
console.log('');

if (!penalty.needs_reconciliation) {
  console.log('✅ No reconciliation needed');
  Deno.exit(0);
}

console.log('🚀 Calling quick-handler Edge Function...');
console.log('');

// Call quick-handler Edge Function directly with service role key
// Note: Service role key should work as Bearer token for Edge Functions
const functionUrl = `${supabaseUrl}/functions/v1/quick-handler`;

try {
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${supabaseKey}`
    },
    body: JSON.stringify({
      userId: userId,
      limit: 10
    })
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`❌ Edge Function call failed:`);
    console.error(`   Status: ${response.status} ${response.statusText}`);
    console.error(`   Response: ${errorText}`);
    console.error('');
    console.error('💡 Note: If you see "Invalid JWT", the service role key may need to be used differently.');
    console.error('   Try invoking via Supabase Dashboard: Edge Functions → quick-handler → Invoke');
    Deno.exit(1);
  }

  const result = await response.json();
  console.log('✅ Edge Function Response:');
  console.log(JSON.stringify(result, null, 2));
  console.log('');

  // Wait a moment for database updates
  console.log('⏳ Waiting 2 seconds for database updates...');
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Check updated status
  const { data: updatedPenalty, error: updatedError } = await supabase
    .from('user_week_penalties')
    .select('*')
    .eq('user_id', userId)
    .eq('week_start_date', weekStartDate)
    .single();

  if (updatedError) {
    console.error(`❌ Error fetching updated penalty: ${updatedError.message}`);
  } else if (updatedPenalty) {
    console.log('📊 Updated Status:');
    console.log(`   Needs Reconciliation: ${updatedPenalty.needs_reconciliation}`);
    console.log(`   Reconciliation Delta: ${updatedPenalty.reconciliation_delta_cents} cents`);
    console.log(`   Charged Amount: ${updatedPenalty.charged_amount_cents} cents`);
    console.log(`   Actual Amount: ${updatedPenalty.actual_amount_cents} cents`);
    console.log(`   Refund Amount: ${updatedPenalty.refund_amount_cents} cents`);
    console.log(`   Settlement Status: ${updatedPenalty.settlement_status}`);
    console.log(`   Refund Payment Intent: ${updatedPenalty.refund_payment_intent_id || 'N/A'}`);
    console.log(`   Refund Issued At: ${updatedPenalty.refund_issued_at || 'N/A'}`);
    console.log('');

    if (updatedPenalty.needs_reconciliation === false && updatedPenalty.refund_amount_cents > 0) {
      console.log('✅ Reconciliation completed successfully!');
    } else if (updatedPenalty.needs_reconciliation === true) {
      console.log('⚠️  Reconciliation still needed - check Edge Function logs for errors');
    }
  }
} catch (err) {
  console.error('❌ Unexpected error:');
  console.error(err);
  Deno.exit(1);
}

