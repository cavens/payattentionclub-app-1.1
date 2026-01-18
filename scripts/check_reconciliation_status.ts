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

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Reconciliation Status Check');
console.log('='.repeat(60));
console.log(`User ID: ${userId}`);
console.log(`Week Start Date: ${weekStartDate}`);
console.log('');

// 1. Check penalty record
console.log('1️⃣  Penalty Record:');
const { data: penalties, error: penaltyError } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', userId)
  .eq('week_start_date', weekStartDate)
  .single();

if (penaltyError) {
  console.error(`❌ Error: ${penaltyError.message}`);
} else if (penalties) {
  console.log(`   Settlement Status: ${penalties.settlement_status}`);
  console.log(`   Needs Reconciliation: ${penalties.needs_reconciliation}`);
  console.log(`   Reconciliation Delta: ${penalties.reconciliation_delta_cents} cents`);
  console.log(`   Charged Amount: ${penalties.charged_amount_cents} cents ($${(penalties.charged_amount_cents / 100).toFixed(2)})`);
  console.log(`   Actual Amount: ${penalties.actual_amount_cents} cents ($${(penalties.actual_amount_cents / 100).toFixed(2)})`);
  console.log(`   Refund Amount: ${penalties.refund_amount_cents} cents ($${(penalties.refund_amount_cents / 100).toFixed(2)})`);
  console.log(`   Refund Payment Intent: ${penalties.refund_payment_intent_id || 'N/A'}`);
  console.log(`   Refund Issued At: ${penalties.refund_issued_at || 'N/A'}`);
} else {
  console.log('   ❌ No penalty record found');
}
console.log('');

// 2. Check queue entry
console.log('2️⃣  Reconciliation Queue:');
const { data: queueEntries, error: queueError } = await supabase
  .from('reconciliation_queue')
  .select('*')
  .eq('user_id', userId)
  .eq('week_start_date', weekStartDate)
  .order('created_at', { ascending: false })
  .limit(1);

if (queueError) {
  console.error(`❌ Error: ${queueError.message}`);
} else if (queueEntries && queueEntries.length > 0) {
  const entry = queueEntries[0];
  console.log(`   Status: ${entry.status}`);
  console.log(`   Delta: ${entry.reconciliation_delta_cents} cents`);
  console.log(`   Created: ${entry.created_at}`);
  console.log(`   Processed: ${entry.processed_at || 'N/A'}`);
  console.log(`   Error: ${entry.error_message || 'None'}`);
  console.log(`   Retry Count: ${entry.retry_count}`);
} else {
  console.log('   ❌ No queue entry found');
}
console.log('');

// 3. Check payments
console.log('3️⃣  Payment Records:');
const { data: payments, error: paymentError } = await supabase
  .from('payments')
  .select('*')
  .eq('user_id', userId)
  .eq('week_start_date', weekStartDate)
  .order('created_at', { ascending: false });

if (paymentError) {
  console.error(`❌ Error: ${paymentError.message}`);
} else if (payments && payments.length > 0) {
  console.log(`   Found ${payments.length} payment(s):`);
  payments.forEach((payment, i) => {
    console.log(`\n   ${i + 1}. ${payment.payment_type}`);
    console.log(`      Amount: ${payment.amount_cents} cents ($${(payment.amount_cents / 100).toFixed(2)})`);
    console.log(`      Status: ${payment.status}`);
    console.log(`      Payment Intent: ${payment.stripe_payment_intent_id}`);
    console.log(`      Charge ID: ${payment.stripe_charge_id || 'N/A'}`);
    console.log(`      Created: ${payment.created_at}`);
  });
} else {
  console.log('   ❌ No payment records found');
}
console.log('');

// 4. Check cron job status (requires direct SQL query)
console.log('4️⃣  Cron Job Status:');
console.log('   (Checking pg_cron.job table...)');
const { data: cronJobs, error: cronError } = await supabase
  .rpc('exec_sql', {
    query: `
      SELECT 
        jobid,
        jobname,
        schedule,
        active,
        database,
        command
      FROM cron.job
      WHERE jobname LIKE '%reconciliation%'
      ORDER BY jobname;
    `
  });

if (cronError) {
  // Try alternative: direct query if RPC doesn't exist
  console.log('   ⚠️  Cannot check cron jobs via RPC (may require direct SQL)');
  console.log('   💡 Run this SQL in Supabase SQL Editor:');
  console.log('');
  console.log('   SELECT');
  console.log('     jobid,');
  console.log('     jobname,');
  console.log('     schedule,');
  console.log('     active,');
  console.log('     database,');
  console.log('     command');
  console.log('   FROM cron.job');
  console.log('   WHERE jobname LIKE \'%reconciliation%\';');
  console.log('');
} else if (cronJobs) {
  console.log(`   Found ${cronJobs.length} cron job(s):`);
  cronJobs.forEach((job: any) => {
    console.log(`\n   - ${job.jobname}`);
    console.log(`     Active: ${job.active}`);
    console.log(`     Schedule: ${job.schedule}`);
    console.log(`     Command: ${job.command?.substring(0, 100)}...`);
  });
}
console.log('');

// 5. Summary
console.log('📊 Summary:');
if (penalties) {
  const expectedRefund = Math.abs(penalties.reconciliation_delta_cents || 0);
  const actualRefund = penalties.refund_amount_cents || 0;
  
  if (penalties.needs_reconciliation && actualRefund === 0) {
    console.log('   ⚠️  Reconciliation needed but refund not issued');
    console.log(`   Expected refund: $${(expectedRefund / 100).toFixed(2)}`);
    console.log(`   Actual refund: $${(actualRefund / 100).toFixed(2)}`);
    console.log('');
    console.log('   Possible causes:');
    console.log('   1. Cron job not running');
    console.log('   2. quick-handler Edge Function failed');
    console.log('   3. Stripe refund failed');
    console.log('   4. Database update failed');
  } else if (penalties.needs_reconciliation === false && actualRefund > 0) {
    console.log('   ✅ Reconciliation completed');
    console.log(`   Refund issued: $${(actualRefund / 100).toFixed(2)}`);
  } else if (penalties.needs_reconciliation === false && actualRefund === 0) {
    console.log('   ✅ No reconciliation needed');
  }
}


