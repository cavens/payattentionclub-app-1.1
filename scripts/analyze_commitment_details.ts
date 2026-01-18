/**
 * Analyze Commitment Details
 * Shows detailed breakdown of a commitment's settings and calculated values
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/analyze_commitment_details.ts [commitment_id]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const commitmentId = Deno.args[0] || '8c0c995e-122b-4e71-8a6e-5a9a6230b7e0';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('📊 Analyzing Commitment Details');
console.log('=' .repeat(60));
console.log(`Commitment ID: ${commitmentId}`);
console.log('');

// Get commitment
const { data: commitment, error: commitError } = await supabase
  .from('commitments')
  .select('*')
  .eq('id', commitmentId)
  .single();

if (!commitment) {
  console.error(`❌ Commitment not found: ${commitError?.message}`);
  Deno.exit(1);
}

console.log('📋 Commitment Settings:');
console.log('=' .repeat(60));
console.log(`  Limit: ${commitment.limit_minutes} minutes (${(commitment.limit_minutes / 60).toFixed(2)} hours)`);
console.log(`  Penalty Rate: $${(commitment.penalty_per_minute_cents || 0) / 100}/min (${commitment.penalty_per_minute_cents} cents/min)`);
console.log(`  App Count: ${commitment.apps_to_limit?.app_bundle_ids?.length || 0} apps`);
console.log(`  Apps: ${JSON.stringify(commitment.apps_to_limit?.app_bundle_ids || [])}`);
console.log('');

console.log('⏰ Timeline:');
console.log('=' .repeat(60));
const created = new Date(commitment.created_at);
const deadline = commitment.week_end_timestamp 
  ? new Date(commitment.week_end_timestamp)
  : new Date(created.getTime() + (3 * 60 * 1000)); // Fallback: 3 minutes

const now = new Date();
const minutesRemaining = Math.max(0, (deadline.getTime() - now.getTime()) / (60 * 1000));
const minutesFromCreation = (deadline.getTime() - created.getTime()) / (60 * 1000);

console.log(`  Created: ${created.toISOString()}`);
console.log(`  Deadline: ${deadline.toISOString()}`);
console.log(`  Time from creation to deadline: ${minutesFromCreation.toFixed(2)} minutes`);
console.log(`  Time remaining now: ${minutesRemaining.toFixed(2)} minutes`);
console.log(`  Mode: ${minutesFromCreation < 10 ? 'Testing Mode (3-min deadline)' : 'Normal Mode (7-day deadline)'}`);
console.log('');

console.log('💰 Authorization Amount:');
console.log('=' .repeat(60));
console.log(`  Stored max_charge_cents: ${commitment.max_charge_cents} cents`);
console.log(`  Stored max_charge: $${(commitment.max_charge_cents || 0) / 100}`);
console.log('');

// Calculate what it should be
const daysRemaining = minutesFromCreation / (24 * 60);
const maxUsageMinutes = Math.min(7.0, daysRemaining) * 720.0;
const potentialOverage = Math.max(0, maxUsageMinutes - commitment.limit_minutes);
const strictnessRatio = maxUsageMinutes / Math.max(1, commitment.limit_minutes);
const strictnessMultiplier = Math.min(10.0, strictnessRatio * 0.4);
const baseAmount = potentialOverage * commitment.penalty_per_minute_cents * strictnessMultiplier;
const appCount = commitment.apps_to_limit?.app_bundle_ids?.length || 1;
const riskFactor = 1.0 + ((Math.max(1, appCount) - 1) * 0.02);
const timeFactor = 1.0 + (Math.min(7.0, daysRemaining) / 7.0 * 0.2);
const afterFactors = baseAmount * riskFactor * timeFactor;
const afterDamping = afterFactors * 0.026;
const finalAmount = Math.max(500, Math.min(100000, Math.floor(afterDamping))); // Using $5 minimum for new calculation

console.log('🧮 Calculation Breakdown:');
console.log('=' .repeat(60));
console.log(`  1. Days Remaining: ${daysRemaining.toFixed(6)}`);
console.log(`  2. Max Usage Minutes: ${maxUsageMinutes.toFixed(2)}`);
console.log(`  3. Potential Overage: ${potentialOverage.toFixed(2)} minutes`);
console.log(`  4. Strictness Ratio: ${strictnessRatio.toFixed(2)}`);
console.log(`  5. Strictness Multiplier: ${strictnessMultiplier.toFixed(2)}x`);
console.log(`  6. Base Amount: $${(baseAmount / 100).toFixed(2)}`);
console.log(`  7. Risk Factor: ${riskFactor.toFixed(2)}x`);
console.log(`  8. Time Factor: ${timeFactor.toFixed(2)}x`);
console.log(`  9. After Factors: $${(afterFactors / 100).toFixed(2)}`);
console.log(`  10. After Damping (0.026): $${(afterDamping / 100).toFixed(2)}`);
console.log(`  11. Final (with $5 min): $${(finalAmount / 100).toFixed(2)}`);
console.log('');

console.log('📊 Comparison:');
console.log('=' .repeat(60));
console.log(`  Stored: $${(commitment.max_charge_cents || 0) / 100} (${commitment.max_charge_cents} cents)`);
console.log(`  Calculated (with $5 min): $${(finalAmount / 100).toFixed(2)} (${finalAmount} cents)`);
console.log(`  Calculated (with $15 min): $${(Math.max(1500, Math.min(100000, Math.floor(afterDamping))) / 100).toFixed(2)} (${Math.max(1500, Math.min(100000, Math.floor(afterDamping)))} cents)`);
console.log('');

if (commitment.max_charge_cents === 1500) {
  console.log('⚠️  Note: This commitment was created with $15 minimum');
  console.log('   New commitments will use $5 minimum after migration');
} else if (commitment.max_charge_cents === 500) {
  console.log('✅ This commitment uses $5 minimum');
} else {
  console.log(`ℹ️  This commitment has calculated amount: $${(commitment.max_charge_cents / 100).toFixed(2)}`);
}

console.log('');


