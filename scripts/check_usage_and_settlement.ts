/**
 * Check Usage and Settlement Status
 * Analyzes usage data and settlement status for a specific commitment
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/check_usage_and_settlement.ts [commitment_id]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const commitmentId = Deno.args[0] || '7aaba52d-14ef-4ea2-b784-56cba49c919f';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Checking Usage and Settlement Status');
console.log('=' .repeat(60));
console.log(`Commitment ID: ${commitmentId}`);
console.log('');

// Get commitment details
console.log('1. Commitment Details:');
const { data: commitment, error: commitError } = await supabase
  .from('commitments')
  .select('*')
  .eq('id', commitmentId)
  .single();

if (commitment) {
  console.log(`   ✅ Found commitment`);
  console.log(`   User ID: ${commitment.user_id}`);
  console.log(`   Created: ${commitment.created_at}`);
  console.log(`   Week End Date: ${commitment.week_end_date}`);
  console.log(`   Week End Timestamp: ${commitment.week_end_timestamp || '❌ NULL'}`);
  console.log(`   Limit: ${commitment.limit_minutes} minutes`);
  console.log(`   Penalty Rate: $${(commitment.penalty_per_minute_cents || 0) / 100}/min`);
  console.log(`   Max Charge: $${(commitment.max_charge_cents || 0) / 100}`);
  console.log(`   Status: ${commitment.status}`);
  
  // Calculate expected deadline
  if (commitment.created_at) {
    const created = new Date(commitment.created_at);
    const expectedDeadline = new Date(created.getTime() + (3 * 60 * 1000)); // 3 minutes
    console.log(`   Expected Deadline (3 min): ${expectedDeadline.toISOString()}`);
  }
} else {
  console.log(`   ❌ Commitment not found: ${commitError?.message}`);
  Deno.exit(1);
}

console.log('');

// Get usage data
console.log('2. Usage Data:');
const { data: usage, error: usageError } = await supabase
  .from('daily_usage')
  .select('*')
  .eq('user_id', commitment.user_id)
  .order('date', { ascending: false })
  .limit(10);

if (usage && usage.length > 0) {
  console.log(`   ✅ Found ${usage.length} usage entry(ies):`);
  let totalMinutes = 0;
  usage.forEach((u, i) => {
    const minutes = u.used_minutes || 0;
    const exceeded = u.exceeded_minutes || 0;
    const penalty = u.penalty_cents || 0;
    totalMinutes += minutes;
    console.log(`   ${i + 1}. Date: ${u.date}`);
    console.log(`      Used Minutes: ${minutes}`);
    console.log(`      Exceeded Minutes: ${exceeded}`);
    console.log(`      Penalty Cents: ${penalty} ($${(penalty / 100).toFixed(2)})`);
    console.log(`      Reported At: ${u.reported_at || 'N/A'}`);
  });
  console.log(`   Total Minutes: ${totalMinutes}`);
  console.log(`   Limit: ${commitment.limit_minutes} minutes`);
  const overage = Math.max(0, totalMinutes - commitment.limit_minutes);
  console.log(`   Overage: ${overage} minutes`);
  const expectedPenalty = overage * (commitment.penalty_per_minute_cents || 0);
  const cappedPenalty = Math.min(expectedPenalty, commitment.max_charge_cents || 0);
  console.log(`   Expected Penalty: $${(expectedPenalty / 100).toFixed(2)}`);
  console.log(`   Capped Penalty: $${(cappedPenalty / 100).toFixed(2)}`);
} else {
  console.log('   ❌ No usage data found');
}

console.log('');

// Get penalty record
console.log('3. Penalty Record:');
const { data: penalties, error: penaltyError } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', commitment.user_id)
  .eq('week_start_date', commitment.week_end_date)
  .order('created_at', { ascending: false })
  .limit(1);

if (penalties && penalties.length > 0) {
  const penalty = penalties[0];
  console.log(`   ✅ Found penalty record`);
  console.log(`   ID: ${penalty.id}`);
  console.log(`   Total Penalty: $${(penalty.total_penalty_cents || 0) / 100}`);
  console.log(`   Actual Amount: $${(penalty.actual_amount_cents || 0) / 100}`);
  console.log(`   Charged Amount: $${(penalty.charged_amount_cents || 0) / 100}`);
  console.log(`   Status: ${penalty.status}`);
  console.log(`   Settlement Status: ${penalty.settlement_status}`);
  console.log(`   Needs Reconciliation: ${penalty.needs_reconciliation}`);
  console.log(`   Last Updated: ${penalty.last_updated}`);
  console.log(`   Charged At: ${penalty.charged_at || 'Not charged yet'}`);
} else {
  console.log('   ❌ No penalty record found');
}

console.log('');

// Get payments
console.log('4. Payments:');
const { data: payments, error: paymentError } = await supabase
  .from('payments')
  .select('*')
  .eq('user_id', commitment.user_id)
  .order('created_at', { ascending: false })
  .limit(5);

if (payments && payments.length > 0) {
  console.log(`   ✅ Found ${payments.length} payment(s):`);
  payments.forEach((p, i) => {
    console.log(`   ${i + 1}. Type: ${p.type}`);
    console.log(`      Amount: $${(p.amount_cents || 0) / 100}`);
    console.log(`      Status: ${p.status}`);
    console.log(`      Created: ${p.created_at}`);
  });
} else {
  console.log('   ℹ️  No payments found');
}

console.log('');

// Summary
console.log('📊 Summary');
console.log('=' .repeat(60));
if (commitment.week_end_timestamp) {
  console.log('✅ week_end_timestamp is set');
} else {
  console.log('❌ week_end_timestamp is NULL (should be set in testing mode)');
}

if (usage && usage.length > 0) {
  const totalMinutes = usage.reduce((sum, u) => sum + (u.used_minutes || 0), 0);
  const totalExceeded = usage.reduce((sum, u) => sum + (u.exceeded_minutes || 0), 0);
  const overage = Math.max(0, totalMinutes - commitment.limit_minutes);
  if (overage > 0 || totalExceeded > 0) {
    console.log(`✅ Usage recorded: ${totalMinutes} minutes (${totalExceeded} exceeded, ${overage} over limit)`);
  } else {
    console.log(`✅ Usage recorded: ${totalMinutes} minutes (within limit)`);
  }
} else {
  console.log('❌ No usage data found');
}

if (penalties && penalties.length > 0) {
  const penalty = penalties[0];
  if (penalty.actual_amount_cents > 0) {
    console.log(`✅ Penalty calculated: $${(penalty.actual_amount_cents / 100).toFixed(2)}`);
  } else {
    console.log('⚠️  Penalty is 0 (may not be calculated yet)');
  }
  if (penalty.settlement_status === 'settled') {
    console.log('✅ Settlement completed');
  } else {
    console.log(`⏳ Settlement status: ${penalty.settlement_status}`);
  }
} else {
  console.log('❌ No penalty record found');
}

console.log('');

