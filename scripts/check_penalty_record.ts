/**
 * Check Penalty Record
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/check_penalty_record.ts [user_id] [week_start_date]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const userId = Deno.args[0] || 'ef9a25f8-64e1-435d-b994-39a1d724c2bc';
const weekStartDate = Deno.args[1] || '2026-01-17';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Checking Penalty Record');
console.log('='.repeat(60));
console.log(`User ID: ${userId}`);
console.log(`Week Start Date: ${weekStartDate}`);
console.log('');

const { data: penalties, error } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', userId)
  .eq('week_start_date', weekStartDate)
  .order('last_updated', { ascending: false });

if (error) {
  console.error('❌ Error:', error);
  Deno.exit(1);
}

if (penalties && penalties.length > 0) {
  console.log(`✅ Found ${penalties.length} penalty record(s):`);
  penalties.forEach((p, i) => {
    console.log(`\n${i + 1}. ID: ${p.id}`);
    console.log(`   User ID: ${p.user_id}`);
    console.log(`   Week Start Date: ${p.week_start_date}`);
    console.log(`   Total Penalty: $${(p.total_penalty_cents || 0) / 100}`);
    console.log(`   Actual Amount: $${(p.actual_amount_cents || 0) / 100}`);
    console.log(`   Charged Amount: $${(p.charged_amount_cents || 0) / 100}`);
    console.log(`   Refund Amount: $${(p.refund_amount_cents || 0) / 100}`);
    console.log(`   Status: ${p.status}`);
    console.log(`   Settlement Status: ${p.settlement_status}`);
    console.log(`   Charge Payment Intent ID: ${p.charge_payment_intent_id || 'N/A'}`);
    console.log(`   Refund Payment Intent ID: ${p.refund_payment_intent_id || 'N/A'}`);
    console.log(`   Charged At: ${p.charged_at || 'Not charged yet'}`);
    console.log(`   Refund Issued At: ${p.refund_issued_at || 'Not refunded yet'}`);
    console.log(`   Last Updated: ${p.last_updated}`);
    console.log(`   Needs Reconciliation: ${p.needs_reconciliation}`);
    console.log(`   Reconciliation Delta: ${p.reconciliation_delta_cents || 0} cents`);
    
    // Calculate net charge
    const netCharge = (p.charged_amount_cents || 0) - (p.refund_amount_cents || 0);
    console.log(`   Net Charge: $${netCharge / 100}`);
    
    // Check if refund matches expected delta
    if (p.needs_reconciliation && p.reconciliation_delta_cents) {
      const expectedRefund = Math.abs(p.reconciliation_delta_cents);
      const actualRefund = p.refund_amount_cents || 0;
      if (actualRefund === expectedRefund) {
        console.log(`   ✅ Refund matches expected delta: $${expectedRefund / 100}`);
      } else if (actualRefund > 0) {
        console.log(`   ⚠️  Refund issued but amount differs: expected $${expectedRefund / 100}, got $${actualRefund / 100}`);
      } else {
        console.log(`   ❌ Refund not issued yet: expected $${expectedRefund / 100}`);
      }
    }
  });
  
  // Check for refund payment records
  console.log('\n🔍 Checking for refund payment records...');
  const penalty = penalties[0];
  if (penalty.charge_payment_intent_id) {
    const { data: refundPayments, error: paymentError } = await supabase
      .from('payments')
      .select('*')
      .eq('user_id', penalty.user_id)
      .eq('week_start_date', penalty.week_start_date)
      .eq('payment_type', 'penalty_refund')
      .order('created_at', { ascending: false });
    
    if (paymentError) {
      console.error('   ❌ Error checking payments:', paymentError.message);
    } else if (refundPayments && refundPayments.length > 0) {
      console.log(`   ✅ Found ${refundPayments.length} refund payment record(s):`);
      refundPayments.forEach((payment, i) => {
        console.log(`\n   ${i + 1}. Payment ID: ${payment.id}`);
        console.log(`      Amount: $${(payment.amount_cents || 0) / 100}`);
        console.log(`      Status: ${payment.status}`);
        console.log(`      Stripe Payment Intent ID: ${payment.stripe_payment_intent_id || 'N/A'}`);
        console.log(`      Stripe Charge ID: ${payment.stripe_charge_id || 'N/A'}`);
        console.log(`      Created At: ${payment.created_at}`);
      });
    } else {
      console.log('   ⚠️  No refund payment records found');
      console.log('   💡 This might mean the refund was not issued yet, or it failed silently');
    }
  }
} else {
  console.log('❌ No penalty record found');
  console.log('');
  console.log('💡 Checking all penalty records for this user...');
  const { data: allPenalties } = await supabase
    .from('user_week_penalties')
    .select('*')
    .eq('user_id', userId)
    .order('last_updated', { ascending: false })
    .limit(5);
  
  if (allPenalties && allPenalties.length > 0) {
    console.log(`Found ${allPenalties.length} penalty record(s) for this user:`);
    allPenalties.forEach((p, i) => {
      console.log(`  ${i + 1}. Week Start Date: ${p.week_start_date}, Settlement Status: ${p.settlement_status}`);
    });
  } else {
    console.log('  No penalty records found for this user');
  }
}

