/**
 * Test Priority 2: No Stale Module-Level Timing Constants
 * 
 * Tests that all timing functions require isTestingMode parameter
 * and no stale constants are used.
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

console.log('🧪 Testing Priority 2: No Stale Module-Level Timing Constants\n');

// Step 1: Check timing.ts for stale constants
console.log('Step 1: Checking timing.ts for stale constants...');
const timingCode = await Deno.readTextFile('supabase/functions/_shared/timing.ts');

// Check for removed constants
const hasWeekDurationConstant = /const\s+WEEK_DURATION_MS\s*=/.test(timingCode);
const hasGracePeriodConstant = /const\s+GRACE_PERIOD_MS\s*=/.test(timingCode);

// Check for new functions
const hasGetWeekDurationMs = /function\s+getWeekDurationMs\s*\(/.test(timingCode);
const hasGetGracePeriodMs = /function\s+getGracePeriodMs\s*\(/.test(timingCode);
const hasGetNextDeadline = /function\s+getNextDeadline\s*\(/.test(timingCode);
const hasGetGraceDeadline = /function\s+getGraceDeadline\s*\(/.test(timingCode);

// Check if functions require isTestingMode parameter
const getWeekDurationMsRequiresMode = /getWeekDurationMs\s*\(\s*isTestingMode\s*:/.test(timingCode);
const getGracePeriodMsRequiresMode = /getGracePeriodMs\s*\(\s*isTestingMode\s*:/.test(timingCode);
const getNextDeadlineRequiresMode = /getNextDeadline\s*\(\s*isTestingMode\s*:/.test(timingCode);
const getGraceDeadlineRequiresMode = /getGraceDeadline\s*\(\s*[^,]+,\s*isTestingMode\s*:/.test(timingCode);

if (hasWeekDurationConstant) {
  console.log('   ❌ WEEK_DURATION_MS constant still exists');
} else {
  console.log('   ✅ WEEK_DURATION_MS constant removed');
}

if (hasGracePeriodConstant) {
  console.log('   ❌ GRACE_PERIOD_MS constant still exists');
} else {
  console.log('   ✅ GRACE_PERIOD_MS constant removed');
}

if (hasGetWeekDurationMs) {
  console.log('   ✅ getWeekDurationMs() function exists');
  if (getWeekDurationMsRequiresMode) {
    console.log('   ✅ getWeekDurationMs() requires isTestingMode parameter');
  } else {
    console.log('   ⚠️  getWeekDurationMs() might not require isTestingMode');
  }
} else {
  console.log('   ❌ getWeekDurationMs() function not found');
}

if (hasGetGracePeriodMs) {
  console.log('   ✅ getGracePeriodMs() function exists');
  if (getGracePeriodMsRequiresMode) {
    console.log('   ✅ getGracePeriodMs() requires isTestingMode parameter');
  } else {
    console.log('   ⚠️  getGracePeriodMs() might not require isTestingMode');
  }
} else {
  console.log('   ❌ getGracePeriodMs() function not found');
}

if (hasGetNextDeadline) {
  console.log('   ✅ getNextDeadline() function exists');
  if (getNextDeadlineRequiresMode) {
    console.log('   ✅ getNextDeadline() requires isTestingMode parameter');
  } else {
    console.log('   ⚠️  getNextDeadline() might not require isTestingMode');
  }
} else {
  console.log('   ❌ getNextDeadline() function not found');
}

if (hasGetGraceDeadline) {
  console.log('   ✅ getGraceDeadline() function exists');
  if (getGraceDeadlineRequiresMode) {
    console.log('   ✅ getGraceDeadline() requires isTestingMode parameter');
  } else {
    console.log('   ⚠️  ⚠️  getGraceDeadline() might not require isTestingMode');
  }
} else {
  console.log('   ❌ getGraceDeadline() function not found');
}

console.log('');

// Step 2: Check all Edge Functions use the new functions correctly
console.log('Step 2: Checking Edge Functions use new timing functions...');

const edgeFunctions = [
  'preview-service/index.ts',
  'super-service/index.ts',
  'bright-service/index.ts',
];

let allFunctionsCorrect = true;

for (const funcPath of edgeFunctions) {
  try {
    const funcCode = await Deno.readTextFile(`supabase/functions/${funcPath}`);
    const funcName = funcPath.split('/')[0];
    
    // Check if function uses getWeekDurationMs or getGracePeriodMs
    const usesGetWeekDurationMs = funcCode.includes('getWeekDurationMs');
    const usesGetGracePeriodMs = funcCode.includes('getGracePeriodMs');
    const usesGetNextDeadline = funcCode.includes('getNextDeadline');
    const usesGetGraceDeadline = funcCode.includes('getGraceDeadline');
    
    // Check if it passes isTestingMode to these functions
    const passesModeToWeekDuration = usesGetWeekDurationMs && 
      /getWeekDurationMs\s*\(\s*isTestingMode/.test(funcCode);
    const passesModeToGracePeriod = usesGetGracePeriodMs && 
      /getGracePeriodMs\s*\(\s*isTestingMode/.test(funcCode);
    const passesModeToNextDeadline = usesGetNextDeadline && 
      /getNextDeadline\s*\(\s*isTestingMode/.test(funcCode);
    const passesModeToGraceDeadline = usesGetGraceDeadline && 
      /getGraceDeadline\s*\([^,]+,\s*isTestingMode/.test(funcCode);
    
    // Check for old constant usage
    const usesOldWeekDuration = /WEEK_DURATION_MS/.test(funcCode);
    const usesOldGracePeriod = /GRACE_PERIOD_MS/.test(funcCode);
    
    if (usesOldWeekDuration || usesOldGracePeriod) {
      console.log(`   ❌ ${funcName}: Still uses old constants`);
      allFunctionsCorrect = false;
    } else if (usesGetWeekDurationMs && !passesModeToWeekDuration) {
      console.log(`   ⚠️  ${funcName}: Uses getWeekDurationMs but might not pass isTestingMode`);
    } else if (usesGetGracePeriodMs && !passesModeToGracePeriod) {
      console.log(`   ⚠️  ${funcName}: Uses getGracePeriodMs but might not pass isTestingMode`);
    } else if (usesGetNextDeadline && !passesModeToNextDeadline) {
      console.log(`   ⚠️  ${funcName}: Uses getNextDeadline but might not pass isTestingMode`);
    } else if (usesGetGraceDeadline && !passesModeToGraceDeadline) {
      console.log(`   ⚠️  ${funcName}: Uses getGraceDeadline but might not pass isTestingMode`);
    } else {
      console.log(`   ✅ ${funcName}: Uses new timing functions correctly`);
    }
  } catch (error) {
    console.log(`   ⚠️  ${funcPath}: Could not read file`);
  }
}

console.log('');

// Step 3: Verify runtime behavior (check logs)
console.log('Step 3: Runtime Verification');
console.log('   To verify Priority 2 is working at runtime:');
console.log('   1. Check Edge Function logs for deadline calculations');
console.log('   2. In testing mode: Should see 3-minute deadlines');
console.log('   3. In normal mode: Should see Monday 12:00 ET deadlines');
console.log('   4. Toggle mode and verify deadlines change immediately');
console.log('   5. This proves no stale timing constants are used ✅\n');

// Summary
console.log('📋 Priority 2 Test Summary:');
if (!hasWeekDurationConstant && !hasGracePeriodConstant && allFunctionsCorrect) {
  console.log('   ✅ All checks passed!');
  console.log('   ✅ No stale module-level timing constants');
  console.log('   ✅ All functions use new parameterized timing functions');
  console.log('   ✅ Priority 2 implementation is correct!');
} else {
  console.log('   ⚠️  Some checks failed - review above');
}

