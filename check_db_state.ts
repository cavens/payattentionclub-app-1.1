import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing environment variables');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

// Get all users (most recent first)
const { data: users, error: userError } = await supabase
  .from('users')
  .select('id, email, created_at')
  .order('created_at', { ascending: false })
  .limit(5);

if (userError) {
  console.error('Error fetching users:', userError);
  Deno.exit(1);
}

if (!users || users.length === 0) {
  console.log('No users found');
  Deno.exit(0);
}

console.log('📋 Found', users.length, 'user(s):');
users.forEach((u, i) => {
  console.log(`  ${i+1}. ${u.email} (ID: ${u.id}) - Created: ${u.created_at}`);
});
console.log('');

// Check jef@cavens.io user first (most likely the real test user)
const testUser = users.find(u => u.email === 'jef@cavens.io') || users[0];
const userId = testUser.id;
console.log('🔍 Checking data for:', testUser.email);
console.log('');

// Get commitments
const { data: commitments, error: commitError } = await supabase
  .from('commitments')
  .select('*')
  .eq('user_id', userId)
  .order('created_at', { ascending: false });

if (commitError) {
  console.error('Error fetching commitments:', commitError);
} else {
  console.log('📝 Commitments:', commitments?.length || 0);
  if (commitments && commitments.length > 0) {
    commitments.forEach((c, i) => {
      console.log(`  ${i+1}. ID: ${c.id}`);
      console.log(`     Full data:`, JSON.stringify(c, null, 2));
    });
  }
  console.log('');
}

// Get daily_usage
const { data: usage, error: usageError } = await supabase
  .from('daily_usage')
  .select('*')
  .eq('user_id', userId)
  .order('date', { ascending: false });

if (usageError) {
  console.error('Error fetching daily_usage:', usageError);
} else {
  console.log('📊 Daily Usage entries:', usage?.length || 0);
  if (usage && usage.length > 0) {
    usage.forEach((u, i) => {
      console.log(`  ${i+1}. Full data:`, JSON.stringify(u, null, 2));
    });
  }
  console.log('');
}

// Get user_week_penalties (try without ordering first to see what columns exist)
const { data: penalties, error: penaltyError } = await supabase
  .from('user_week_penalties')
  .select('*')
  .eq('user_id', userId);

if (penaltyError) {
  console.error('Error fetching penalties:', penaltyError);
} else {
  console.log('💰 Penalties:', penalties?.length || 0);
  if (penalties && penalties.length > 0) {
    penalties.forEach((p, i) => {
      console.log(`  ${i+1}. Week ending: ${p.week_end_date}`);
      console.log(`     Minutes over: ${p.minutes_over_limit}`);
      console.log(`     Penalty amount: $${p.penalty_amount}`);
      console.log(`     Status: ${p.status}`);
      console.log(`     Created: ${p.created_at}`);
    });
  }
  console.log('');
}

// Get weekly_pools to see if any pools exist
const { data: pools, error: poolError } = await supabase
  .from('weekly_pools')
  .select('*')
  .order('week_end_date', { ascending: false })
  .limit(5);

if (poolError) {
  console.error('Error fetching pools:', poolError);
} else {
  console.log('🏊 Weekly Pools:', pools?.length || 0);
  if (pools && pools.length > 0) {
    pools.forEach((p, i) => {
      console.log(`  ${i+1}. Week ending: ${p.week_end_date}`);
      console.log(`     Total penalties: $${p.total_penalties}`);
      console.log(`     Status: ${p.status}`);
      console.log(`     Created: ${p.created_at}`);
    });
  }
  console.log('');
}

// Calculate current time and check against deadline
if (commitments && commitments.length > 0) {
  const latestCommitment = commitments[0];
  const deadlineDate = latestCommitment.deadline_date || latestCommitment.deadline || latestCommitment.week_end_date;
  
  if (deadlineDate) {
    const deadline = new Date(deadlineDate);
    const now = new Date();
    const timeUntilDeadline = deadline.getTime() - now.getTime();
    const minutesUntilDeadline = Math.floor(timeUntilDeadline / (1000 * 60));
    
    console.log('⏰ Timeline Check:');
    console.log(`  Current time: ${now.toISOString()}`);
    console.log(`  Deadline: ${deadline.toISOString()}`);
    console.log(`  Time until deadline: ${minutesUntilDeadline} minutes`);
    console.log(`  Status: ${timeUntilDeadline > 0 ? 'Before deadline' : 'After deadline'}`);
    
    // Check if we're in grace period (assuming 1 minute grace in testing mode)
    const gracePeriodEnd = new Date(deadline.getTime() + (1 * 60 * 1000)); // 1 minute after deadline
    const isInGracePeriod = now >= deadline && now < gracePeriodEnd;
    console.log(`  Grace period end: ${gracePeriodEnd.toISOString()}`);
    console.log(`  In grace period: ${isInGracePeriod ? 'YES' : 'NO'}`);
    console.log('');
  } else {
    console.log('⏰ Timeline Check: No deadline found in commitment');
    console.log('');
  }
}

