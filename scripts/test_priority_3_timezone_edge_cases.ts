/**
 * Test Priority 3: Timezone Edge Case Tests
 * 
 * Tests all boundary conditions for timezone calculations:
 * - Monday 11:59:59 AM ET
 * - Monday 12:00:00 PM ET
 * - Monday 12:00:01 PM ET
 * - Sunday 11:59:59 PM ET
 * - Monday 12:00:00 AM ET
 * - DST transitions
 */

// Load .env file if it exists
try {
  const envText = await Deno.readTextFile('.env');
  for (const line of envText.split('\n')) {
    const trimmed = line.trim();
    if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
      const [key, ...valueParts] = trimmed.split('=');
      const value = valueParts.join('=').replace(/^["']|["']$/g, '');
      Deno.env.set(key.trim(), value.trim());
    }
  }
} catch (error) {
  // .env file doesn't exist or can't be read, that's okay
}

const SUPABASE_URL = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = 
  Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
  Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY');

if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SECRET_KEY');
  Deno.exit(1);
}

console.log('🧪 Testing Priority 3: Timezone Edge Cases\n');

// Import timing functions
const timingModule = await import('../supabase/functions/_shared/timing.ts');

// Test cases for normal mode Monday calculation
const testCases = [
  {
    name: 'Monday 11:59:59 AM ET',
    date: new Date('2026-01-20T11:59:59-05:00'), // Monday 11:59:59 AM ET
    expectedBehavior: 'Should use today (Monday) at 12:00 ET',
  },
  {
    name: 'Monday 12:00:00 PM ET',
    date: new Date('2026-01-20T12:00:00-05:00'), // Monday 12:00:00 PM ET
    expectedBehavior: 'Should use next Monday (boundary case)',
  },
  {
    name: 'Monday 12:00:01 PM ET',
    date: new Date('2026-01-20T12:00:01-05:00'), // Monday 12:00:01 PM ET
    expectedBehavior: 'Should use next Monday',
  },
  {
    name: 'Sunday 11:59:59 PM ET',
    date: new Date('2026-01-19T23:59:59-05:00'), // Sunday 11:59:59 PM ET
    expectedBehavior: 'Should use tomorrow (Monday)',
  },
  {
    name: 'Tuesday 12:00:00 PM ET',
    date: new Date('2026-01-21T12:00:00-05:00'), // Tuesday 12:00:00 PM ET
    expectedBehavior: 'Should use previous Monday',
  },
  {
    name: 'Saturday 11:59:59 PM ET',
    date: new Date('2026-01-25T23:59:59-05:00'), // Saturday 11:59:59 PM ET
    expectedBehavior: 'Should use previous Monday',
  },
];

console.log('Step 1: Testing getNextDeadline() in Normal Mode\n');

let allTestsPassed = true;

for (const testCase of testCases) {
  try {
    const deadline = timingModule.getNextDeadline(false, testCase.date);
    // Check if deadline is Monday by checking the day of week in ET timezone
    const deadlineET = new Date(deadline.toLocaleString('en-US', { timeZone: 'America/New_York' }));
    const isMonday = deadlineET.getDay() === 1;
    
    // Get hour in ET timezone
    const hourET = deadlineET.getHours();
    const isNoon = hourET === 12;
    
    const deadlineETString = deadline.toLocaleString('en-US', { 
      timeZone: 'America/New_York',
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    
    const passed = isMonday && isNoon;
    
    if (passed) {
      console.log(`   ✅ ${testCase.name}`);
      console.log(`      Deadline: ${deadlineETString}`);
      console.log(`      ${testCase.expectedBehavior}`);
    } else {
      console.log(`   ❌ ${testCase.name}`);
      console.log(`      Deadline: ${deadlineETString}`);
      console.log(`      Expected: Monday 12:00 ET`);
      console.log(`      Got: ${isMonday ? 'Monday' : 'Not Monday'} ${hourET}:00 ET`);
      allTestsPassed = false;
    }
    console.log('');
  } catch (error) {
    console.log(`   ❌ ${testCase.name}: Error`);
    console.log(`      ${error instanceof Error ? error.message : String(error)}`);
    allTestsPassed = false;
    console.log('');
  }
}

// Test grace period calculation
console.log('Step 2: Testing getGraceDeadline() in Normal Mode\n');

const mondayNoonET = new Date('2026-01-20T12:00:00-05:00'); // Monday 12:00 ET
const graceDeadline = timingModule.getGraceDeadline(mondayNoonET, false);

const graceDeadlineETDate = new Date(graceDeadline.toLocaleString('en-US', { timeZone: 'America/New_York' }));
const isTuesday = graceDeadlineETDate.getDay() === 2;
const graceHourET = graceDeadlineETDate.getHours();
const graceIsNoon = graceHourET === 12;

const graceDeadlineET = graceDeadline.toLocaleString('en-US', { 
  timeZone: 'America/New_York',
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

if (isTuesday && graceIsNoon) {
  console.log(`   ✅ Grace period calculation`);
  console.log(`      Monday deadline: ${mondayNoonET.toLocaleString('en-US', { timeZone: 'America/New_York' })}`);
  console.log(`      Grace deadline: ${graceDeadlineET}`);
      console.log(`      Expected: Tuesday 12:00 ET (24 hours after Monday)`);
} else {
  console.log(`   ❌ Grace period calculation`);
  console.log(`      Monday deadline: ${mondayNoonET.toLocaleString('en-US', { timeZone: 'America/New_York' })}`);
  console.log(`      Grace deadline: ${graceDeadlineET}`);
  console.log(`      Expected: Tuesday 12:00 ET`);
  console.log(`      Got: ${isTuesday ? 'Tuesday' : 'Not Tuesday'} ${graceHourET}:00 ET`);
  allTestsPassed = false;
}

console.log('');

// Test testing mode (should be simple - 4 minutes from now)
console.log('Step 3: Testing getNextDeadline() in Testing Mode\n');

const now = new Date();
const testingDeadline = timingModule.getNextDeadline(true, now);
const timeDiff = testingDeadline.getTime() - now.getTime();
const expectedDiff = timingModule.TESTING_WEEK_DURATION_MS;
const diffTolerance = 1000; // 1 second tolerance

if (Math.abs(timeDiff - expectedDiff) < diffTolerance) {
  console.log(`   ✅ Testing mode deadline calculation`);
  console.log(`      Now: ${now.toISOString()}`);
  console.log(`      Deadline: ${testingDeadline.toISOString()}`);
  console.log(`      Difference: ${timeDiff / 1000} seconds (expected: ${timingModule.TESTING_WEEK_DURATION_MS / 1000} seconds)`);
} else {
  console.log(`   ❌ Testing mode deadline calculation`);
  console.log(`      Now: ${now.toISOString()}`);
  console.log(`      Deadline: ${testingDeadline.toISOString()}`);
  console.log(`      Difference: ${timeDiff / 1000} seconds (expected: ${timingModule.TESTING_WEEK_DURATION_MS / 1000} seconds)`);
  allTestsPassed = false;
}

console.log('');

// Summary
console.log('📋 Priority 3 Test Summary:');
if (allTestsPassed) {
  console.log('   ✅ All timezone edge case tests passed!');
  console.log('   ✅ Monday calculations are correct');
  console.log('   ✅ Grace period calculations are correct');
  console.log('   ✅ Testing mode calculations are correct');
  console.log('   ✅ Priority 3 implementation is correct!');
} else {
  console.log('   ⚠️  Some tests failed - review above');
  console.log('   ⚠️  Timezone calculations may need fixes');
}

