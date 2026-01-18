/**
 * Test Settlement Flow
 * 
 * 1. Gets the latest commitment for jef@cavens.io
 * 2. Checks usage data
 * 3. Checks if deadline has passed
 * 4. Checks penalty calculation
 * 5. Optionally triggers settlement
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/test_settlement_flow.ts [--trigger]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const shouldTrigger = Deno.args.includes('--trigger');

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🧪 Testing Settlement Flow');
console.log('='.repeat(60));
console.log('');

// Get test user
const testEmail = 'jef@cavens.io';
console.log(`1. Finding user: ${testEmail}`);
const { data: users, error: userError } = await supabase
  .from('users')
  .select('id, email')
  .eq('email', testEmail)
  .limit(1);

if (!users || users.length === 0) {
  console.log('   ❌ User not found');
  Deno.exit(1);
}

const userId = users[0].id;
console.log(`   ✅ Found user: ${userId}`);
console.log('');

// Get latest commitment
console.log('2. Getting latest commitment...');
const { data: commitments, error: commitError } = await supabase
  .from('commitments')
  .select('*')
  .eq('user_id', userId)
  .order('created_at', { ascending: false })
  .limit(1);

if (!commitments || commitments.length === 0) {
  console.log('   ❌ No commitment found');
  Deno.exit(1);
}

const commitment = commitments[0];
console.log(`   ✅ Found commitment: ${commitment.id}`);
console.log(`   Created: ${commitment.created_at}`);
console.log(`   Week End Date: ${commitment.week_end_date}`);
console.log(`   Week End Timestamp: ${commitment.week_end_timestamp || '❌ NULL'}`);
console.log(`   Limit: ${commitment.limit_minutes} minutes`);
console.log(`   Penalty Rate: $${(commitment.penalty_per_minute_cents || 0) / 100}/min`);
console.log(`   Max Charge: $${(commitment.max_charge_cents || 0) / 100}`);
console.log(`   Status: ${commitment.status}`);
console.log('');

// Check deadline
console.log('3. Checking deadline...');
const now = new Date();
let deadline: Date;
if (commitment.week_end_timestamp) {
  deadline = new Date(commitment.week_end_timestamp);
  console.log('   🧪 TESTING MODE: Using week_end_timestamp');
} else {
  deadline = new Date(commitment.week_end_date + 'T12:00:00-05:00'); // Noon ET
  console.log('   📅 NORMAL MODE: Using week_end_date + 12:00 ET');
}

const timeUntilDeadline = deadline.getTime() - now.getTime();
const minutesUntilDeadline = Math.floor(timeUntilDeadline / (1000 * 60));
const secondsUntilDeadline = Math.floor((timeUntilDeadline % (1000 * 60)) / 1000);

console.log(`   Deadline: ${deadline.toISOString()}`);
console.log(`   Now: ${now.toISOString()}`);
if (timeUntilDeadline > 0) {
  console.log(`   ⏳ Time until deadline: ${minutesUntilDeadline}m ${secondsUntilDeadline}s`);
} else {
  console.log(`   ✅ Deadline has passed: ${Math.abs(minutesUntilDeadline)}m ${Math.abs(secondsUntilDeadline)}s ago`);
}
console.log('');

// Get usage data
console.log('4. Checking usage data...');
const { data: usage, error: usageError } = await supabase
  .from('daily_usage')
  .select('*')
  .eq('user_id', userId)
  .order('date', { ascending: false })
  .limit(10);

if (usage && usage.length > 0) {
  console.log(`   ✅ Found ${usage.length} usage entry(ies):`);
  let totalMinutes = 0;
  let totalExceeded = 0;
  usage.forEach((u, i) => {
    const minutes = u.used_minutes || 0;
    const exceeded = u.exceeded_minutes || 0;
    const penalty = u.penalty_cents || 0;
    totalMinutes += minutes;
    totalExceeded += exceeded;
    console.log(`   ${i + 1}. Date: ${u.date}`);
    console.log(`      Used Minutes: ${minutes}`);
    console.log(`      Exceeded Minutes: ${exceeded}`);
    console.log(`      Penalty Cents: ${penalty} ($${(penalty / 100).toFixed(2)})`);
    console.log(`      Reported At: ${u.reported_at || 'N/A'}`);
  });
  console.log(`   Total Minutes: ${totalMinutes}`);
  console.log(`   Total Exceeded: ${totalExceeded}`);
  console.log(`   Limit: ${commitment.limit_minutes} minutes`);
  const overage = Math.max(0, totalMinutes - commitment.limit_minutes);
  console.log(`   Overage: ${overage} minutes`);
  const expectedPenalty = overage * (commitment.penalty_per_minute_cents || 0);
  const cappedPenalty = Math.min(expectedPenalty, commitment.max_charge_cents || 0);
  console.log(`   Expected Penalty: $${(expectedPenalty / 100).toFixed(2)}`);
  console.log(`   Capped Penalty: $${(cappedPenalty / 100).toFixed(2)}`);
  console.log(`   User reported: $3.29`);
  if (Math.abs(cappedPenalty - 329) < 1) {
    console.log(`   ✅ Penalty matches user's report!`);
  } else {
    console.log(`   ⚠️  Penalty mismatch: expected $${(cappedPenalty / 100).toFixed(2)}, user sees $3.29`);
  }
} else {
  console.log('   ❌ No usage data found');
  console.log('   ⚠️  This is a problem - user reported 4 minutes of usage');
}
console.log('');

// Get penalty record
console.log('5. Checking penalty record...');
const { data: penalties, error: penaltyError } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', userId)
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
  if (timeUntilDeadline <= 0) {
    console.log('   ⚠️  Deadline has passed but no penalty record exists');
    console.log('   💡 Settlement may need to be triggered');
  }
}
console.log('');

// Get payments
console.log('6. Checking payments...');
const { data: payments, error: paymentError } = await supabase
  .from('payments')
  .select('*')
  .eq('user_id', userId)
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
console.log('='.repeat(60));
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
  if (timeUntilDeadline <= 0) {
    console.log('💡 Settlement may need to be triggered');
  }
}
console.log('');

// Trigger settlement if requested
if (shouldTrigger) {
  console.log('🚀 Triggering settlement...');
  console.log('   (Using service role key - function remains private for security)');
  console.log('');
  
  try {
    // Use direct HTTP request with service role key
    // This works even when the function is private
    const url = `${supabaseUrl}/functions/v1/bright-service`;
    
    // Get settlement secret from environment (if set)
    // If not set, function will require authentication via Supabase gateway
    const settlementSecret = Deno.env.get('SETTLEMENT_SECRET');
    
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "x-manual-trigger": "true"
    };
    
    // Add settlement secret if available (allows public function access)
    if (settlementSecret) {
      headers["x-settlement-secret"] = settlementSecret;
      console.log('   Using settlement secret for authentication');
    } else {
      // Fallback: try service role key (may not work if function is public)
      headers["Authorization"] = `Bearer ${supabaseKey}`;
      console.log('   Using service role key (function must be private)');
      console.log('   💡 To use public function, set SETTLEMENT_SECRET in .env');
    }
    
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({})
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("❌ Settlement trigger failed:");
      console.error(`   Status: ${response.status} ${response.statusText}`);
      console.error(`   Response: ${errorText}`);
      console.error('');
      console.error('💡 Make sure you are using the service role key (not anon key)');
      console.error('   Get it from: Supabase Dashboard → Settings → API → service_role key');
    } else {
      const data = await response.json();
      console.log("✅ Settlement triggered successfully!");
      console.log("");
      console.log("Response:", JSON.stringify(data, null, 2));
      console.log('');
      console.log('💡 Run this script again (without --trigger) to check the results');
    }
  } catch (err) {
    console.error("❌ Unexpected error:");
    console.error(err);
  }
} else if (timeUntilDeadline <= 0 && (!penalties || penalties.length === 0)) {
  console.log('💡 To trigger settlement, run:');
  console.log(`   deno run --allow-net --allow-env --allow-read scripts/test_settlement_flow.ts --trigger`);
}

