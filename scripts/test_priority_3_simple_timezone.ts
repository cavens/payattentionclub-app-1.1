/**
 * Simple test to verify timezone calculations work correctly
 */

// Test the toDateInTimeZone function
function toDateInTimeZone(date: Date, timeZone: string): Date {
  return new Date(date.toLocaleString("en-US", { timeZone }));
}

// Test: Monday 12:00 ET should be calculated correctly
const TIME_ZONE = "America/New_York";

console.log('🧪 Simple Timezone Test\n');

// Test 1: Create a Monday 12:00 ET date
const mondayNoonET = new Date('2026-01-20T12:00:00-05:00'); // Monday Jan 20, 2026 12:00 ET
console.log('Test 1: Monday 12:00 ET');
console.log(`   Input: ${mondayNoonET.toISOString()}`);
console.log(`   ET time: ${mondayNoonET.toLocaleString('en-US', { timeZone: 'America/New_York' })}`);
console.log(`   UTC time: ${mondayNoonET.toUTCString()}`);
console.log('');

// Test 2: Use toDateInTimeZone to convert
const now = new Date('2026-01-20T12:00:00-05:00'); // Monday 12:00 ET
const nowET = toDateInTimeZone(now, TIME_ZONE);
console.log('Test 2: toDateInTimeZone conversion');
console.log(`   Input: ${now.toISOString()}`);
console.log(`   Converted: ${nowET.toISOString()}`);
console.log(`   ET time: ${nowET.toLocaleString('en-US', { timeZone: 'America/New_York' })}`);
console.log(`   Day of week: ${nowET.getDay()} (0=Sun, 1=Mon)`);
console.log(`   Hour: ${nowET.getHours()}`);
console.log('');

// Test 3: Set hours to 12
const testDate = new Date(nowET);
testDate.setHours(12, 0, 0, 0);
console.log('Test 3: After setHours(12, 0, 0, 0)');
console.log(`   Result: ${testDate.toISOString()}`);
console.log(`   ET time: ${testDate.toLocaleString('en-US', { timeZone: 'America/New_York' })}`);
console.log(`   Hour in ET: ${new Date(testDate.toLocaleString('en-US', { timeZone: 'America/New_York' })).getHours()}`);
console.log('');

// The issue: setHours() sets hours in LOCAL timezone, not ET
// We need to set hours in ET timezone instead

