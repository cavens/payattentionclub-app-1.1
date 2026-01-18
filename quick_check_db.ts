import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing environment variables');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

// Get jef@cavens.io user
const { data: users } = await supabase
  .from('users')
  .select('id, email')
  .eq('email', 'jef@cavens.io')
  .limit(1);

if (!users || users.length === 0) {
  console.log('❌ User not found');
  Deno.exit(1);
}

const userId = users[0].id;
const now = new Date();

// Get latest commitment
const { data: commitments } = await supabase
  .from('commitments')
  .select('*')
  .eq('user_id', userId)
  .order('created_at', { ascending: false })
  .limit(1);

if (!commitments || commitments.length === 0) {
  console.log('❌ No commitment found');
  Deno.exit(1);
}

const commitment = commitments[0];

// Use week_end_timestamp if available (testing mode), otherwise calculate from week_end_date
let deadline: Date;
if (commitment.week_end_timestamp) {
  deadline = new Date(commitment.week_end_timestamp);
  console.log('🧪 TESTING MODE: Using week_end_timestamp');
} else {
  deadline = new Date(commitment.week_end_date + 'T12:00:00-05:00'); // Noon ET
  console.log('📅 NORMAL MODE: Using week_end_date + 12:00 ET');
}

const timeUntilDeadline = deadline.getTime() - now.getTime();
const minutesUntilDeadline = Math.floor(timeUntilDeadline / (1000 * 60));

// Get latest daily usage
const { data: usage } = await supabase
  .from('daily_usage')
  .select('*')
  .eq('user_id', userId)
  .eq('date', commitment.week_end_date)
  .order('reported_at', { ascending: false })
  .limit(1);

// Get penalties
const { data: penalties } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', userId)
  .eq('week_end_date', commitment.week_end_date)
  .limit(1);

console.log('⏰ QUICK STATUS CHECK');
console.log('==================');
console.log(`Current time: ${now.toISOString()}`);
console.log(`Week end date: ${commitment.week_end_date}`);
console.log(`Week end timestamp: ${commitment.week_end_timestamp || 'NULL (normal mode)'}`);
console.log(`Deadline: ${deadline.toISOString()}`);
console.log(`Time until deadline: ${minutesUntilDeadline} minutes`);
console.log(`Status: ${timeUntilDeadline > 0 ? '✅ BEFORE DEADLINE' : '❌ AFTER DEADLINE'}`);
console.log('');

if (usage && usage.length > 0) {
  const latestUsage = usage[0];
  console.log('📊 Latest Usage Entry:');
  console.log(`  Date: ${latestUsage.date}`);
  console.log(`  Used: ${latestUsage.used_minutes} minutes`);
  console.log(`  Limit: ${latestUsage.limit_minutes} minutes`);
  console.log(`  Exceeded: ${latestUsage.exceeded_minutes} minutes`);
  console.log(`  Penalty: $${(latestUsage.penalty_cents / 100).toFixed(2)}`);
  console.log(`  Reported at: ${latestUsage.reported_at}`);
  console.log('');
} else {
  console.log('📊 No usage entry found for today');
  console.log('');
}

if (penalties && penalties.length > 0) {
  const penalty = penalties[0];
  console.log('💰 Penalty Record:');
  console.log(`  Total penalty: $${(penalty.total_penalty_cents / 100).toFixed(2)}`);
  console.log(`  Status: ${penalty.status}`);
  console.log('');
} else {
  console.log('💰 No penalty record found yet');
  console.log('');
}

console.log('📝 Commitment Status:');
console.log(`  Status: ${commitment.status}`);
console.log(`  Limit: ${commitment.limit_minutes} min`);
console.log(`  Penalty: $${(commitment.penalty_per_minute_cents / 100).toFixed(2)}/min`);
console.log(`  Grace expires: ${commitment.week_grace_expires_at || 'Not set'}`);
console.log('');

