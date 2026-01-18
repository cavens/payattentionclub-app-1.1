/**
 * Analyze Authorization Calculation
 * Shows step-by-step calculation for a specific commitment
 * 
 * Usage:
 *   deno run --allow-net --allow-env --allow-read scripts/analyze_authorization_calculation.ts [commitment_id]
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const commitmentId = Deno.args[0] || 'fb68a996-3e6d-4e7a-a931-f588afba3c6b';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Missing environment variables!');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

console.log('🔍 Analyzing Authorization Calculation');
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

console.log('Commitment Details:');
console.log(`  Created: ${commitment.created_at}`);
console.log(`  Week End Timestamp: ${commitment.week_end_timestamp || 'NULL'}`);
console.log(`  Limit: ${commitment.limit_minutes} minutes`);
console.log(`  Penalty Rate: $${(commitment.penalty_per_minute_cents || 0) / 100}/min`);
console.log(`  App Count: ${commitment.apps_to_limit?.app_bundle_ids?.length || 0}`);
console.log(`  Max Charge (stored): $${(commitment.max_charge_cents || 0) / 100}`);
console.log('');

// Calculate what it should be
const created = new Date(commitment.created_at);
const deadline = commitment.week_end_timestamp 
  ? new Date(commitment.week_end_timestamp)
  : new Date(created.getTime() + (3 * 60 * 1000)); // Fallback: 3 minutes

const now = new Date();
const minutesRemaining = Math.max(0, (deadline.getTime() - now.getTime()) / (60 * 1000));
const daysRemaining = minutesRemaining / (24 * 60);
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
const finalAmount = Math.max(1500, Math.min(100000, Math.floor(afterDamping)));

console.log('Step-by-Step Calculation:');
console.log('=' .repeat(60));
console.log(`1. Minutes Remaining: ${minutesRemaining.toFixed(2)}`);
console.log(`2. Days Remaining: ${daysRemaining.toFixed(6)}`);
console.log(`3. Max Usage Minutes: ${maxUsageMinutes.toFixed(2)}`);
console.log(`4. Potential Overage: ${potentialOverage.toFixed(2)} minutes`);
console.log(`5. Strictness Ratio: ${strictnessRatio.toFixed(2)}`);
console.log(`6. Strictness Multiplier: ${strictnessMultiplier.toFixed(2)}x`);
console.log(`7. Base Amount (before factors): $${(baseAmount / 100).toFixed(2)}`);
console.log(`8. Risk Factor: ${riskFactor.toFixed(2)}x`);
console.log(`9. Time Factor: ${timeFactor.toFixed(2)}x`);
console.log(`10. After Factors: $${(afterFactors / 100).toFixed(2)}`);
console.log(`11. After Damping (0.026): $${(afterDamping / 100).toFixed(2)}`);
console.log(`12. Final Amount (after min/max): $${(finalAmount / 100).toFixed(2)}`);
console.log('');

console.log('Analysis:');
console.log('=' .repeat(60));
if (finalAmount === 1500) {
  console.log('⚠️  Result hit MINIMUM ($15.00)');
  console.log(`   Calculated amount was $${(afterDamping / 100).toFixed(2)}, but minimum is $15.00`);
  console.log(`   This happens when the calculation result is below $15.00`);
} else if (finalAmount === 100000) {
  console.log('⚠️  Result hit MAXIMUM ($1000.00)');
} else {
  console.log('✅ Result is within bounds (not at minimum or maximum)');
}

if (minutesRemaining < 0.1) {
  console.log('');
  console.log('⚠️  WARNING: Very little time remaining (or deadline passed)');
  console.log('   This causes the calculation to be very small, hitting the minimum');
}

console.log('');


