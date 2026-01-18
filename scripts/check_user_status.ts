/**
 * Check User Status
 * Verifies if a user exists in the database and checks their payment method status
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/check_user_status.ts [email]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const email = Deno.args[0] || "jef@cavens.io";

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  console.error('Need: STAGING_SUPABASE_URL (or SUPABASE_URL) and STAGING_SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEY)');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Checking User Status');
console.log('=' .repeat(60));
console.log(`Email: ${email}`);
console.log('');

// Check auth.users
console.log('1. Checking auth.users...');
const { data: authUsers, error: authError } = await supabase.auth.admin.listUsers();
const authUser = authUsers?.users?.find(u => u.email === email);

if (authUser) {
  console.log('   ✅ User exists in auth.users');
  console.log(`   ID: ${authUser.id}`);
  console.log(`   Email: ${authUser.email}`);
  console.log(`   Created: ${authUser.created_at}`);
} else {
  console.log('   ❌ User NOT found in auth.users');
}

console.log('');

// Check public.users
console.log('2. Checking public.users...');
const { data: publicUser, error: publicError } = await supabase
  .from('users')
  .select('*')
  .eq('email', email)
  .single();

if (publicUser) {
  console.log('   ✅ User exists in public.users');
  console.log(`   ID: ${publicUser.id}`);
  console.log(`   Email: ${publicUser.email}`);
  console.log(`   Stripe Customer ID: ${publicUser.stripe_customer_id || 'null'}`);
  console.log(`   Has Active Payment Method: ${publicUser.has_active_payment_method}`);
  console.log(`   Created: ${publicUser.created_at}`);
} else {
  if (publicError?.code === 'PGRST116') {
    console.log('   ❌ User NOT found in public.users');
  } else {
    console.log(`   ⚠️  Error checking public.users: ${publicError?.message}`);
  }
}

console.log('');

// Check commitments
console.log('3. Checking commitments...');
if (publicUser) {
  const { data: commitments, error: commitmentsError } = await supabase
    .from('commitments')
    .select('*')
    .eq('user_id', publicUser.id)
    .order('created_at', { ascending: false })
    .limit(5);

  if (commitments && commitments.length > 0) {
    console.log(`   ✅ Found ${commitments.length} commitment(s)`);
    commitments.forEach((c, i) => {
      console.log(`   ${i + 1}. ID: ${c.id}`);
      console.log(`      Status: ${c.status}`);
      console.log(`      Week End Date: ${c.week_end_date}`);
      console.log(`      Max Charge: $${(c.max_charge_cents || 0) / 100}`);
      console.log(`      Created: ${c.created_at}`);
    });
  } else {
    console.log('   ℹ️  No commitments found');
  }
} else {
  console.log('   ⚠️  Cannot check commitments (user not found in public.users)');
}

console.log('');

// Check payments
console.log('4. Checking payments...');
if (publicUser) {
  const { data: payments, error: paymentsError } = await supabase
    .from('payments')
    .select('*')
    .eq('user_id', publicUser.id)
    .order('created_at', { ascending: false })
    .limit(5);

  if (payments && payments.length > 0) {
    console.log(`   ✅ Found ${payments.length} payment(s)`);
    payments.forEach((p, i) => {
      console.log(`   ${i + 1}. ID: ${p.id}`);
      console.log(`      Type: ${p.type}`);
      console.log(`      Amount: $${(p.amount_cents || 0) / 100}`);
      console.log(`      Status: ${p.status}`);
      console.log(`      Created: ${p.created_at}`);
    });
  } else {
    console.log('   ℹ️  No payments found');
  }
} else {
  console.log('   ⚠️  Cannot check payments (user not found in public.users)');
}

console.log('');

// Summary
console.log('📊 Summary');
console.log('=' .repeat(60));
if (authUser && publicUser) {
  console.log('✅ User exists in both auth.users and public.users');
  console.log(`   Payment Method Status: ${publicUser.has_active_payment_method ? '✅ Has active payment method' : '❌ No active payment method'}`);
  if (publicUser.has_active_payment_method) {
    console.log('   ⚠️  This explains why payment was bypassed!');
    console.log('   The user has has_active_payment_method = true, so billing-status returns needsPaymentIntent: false');
  }
} else if (authUser && !publicUser) {
  console.log('⚠️  User exists in auth.users but NOT in public.users');
  console.log('   This might cause issues - user row should be created automatically');
} else if (!authUser && publicUser) {
  console.log('⚠️  User exists in public.users but NOT in auth.users');
  console.log('   This is unusual - user should exist in auth.users first');
} else {
  console.log('✅ User does NOT exist (fully deleted)');
  console.log('   This is expected if you deleted the test user before creating commitment');
}

console.log('');


