/**
 * Test grace period calculation with a correct Monday date
 */

const timingModule = await import('../supabase/functions/_shared/timing.ts');

// Use a real Monday: January 19, 2026 is a Monday
const mondayDate = new Date('2026-01-19T12:00:00-05:00'); // Monday Jan 19, 2026 12:00 ET

console.log('🧪 Testing Grace Period with Correct Monday Date\n');
console.log(`Monday deadline: ${mondayDate.toLocaleString('en-US', { 
  timeZone: 'America/New_York',
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
})}\n`);

const graceDeadline = timingModule.getGraceDeadline(mondayDate, false);

const graceET = graceDeadline.toLocaleString('en-US', { 
  timeZone: 'America/New_York',
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

const graceETDate = new Date(graceDeadline.toLocaleString('en-US', { timeZone: 'America/New_York' }));
const isTuesday = graceETDate.getDay() === 2;
const hourET = graceETDate.getHours();
const isNoon = hourET === 12;

console.log(`Grace deadline: ${graceET}`);
console.log(`Expected: Tuesday 12:00 ET`);
console.log(`Got: ${isTuesday ? 'Tuesday' : 'Not Tuesday'} ${hourET}:00 ET\n`);

if (isTuesday && isNoon) {
  console.log('✅ Grace period calculation is CORRECT!');
} else {
  console.log('❌ Grace period calculation needs fix');
}

