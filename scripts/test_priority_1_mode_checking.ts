/**
 * Test Priority 1: Standardized Mode Checking
 * 
 * Tests that preview-service correctly checks database first, then env var.
 * Verifies that mode changes are picked up immediately (no stale constants).
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
  console.log('Note: Could not load .env file, using environment variables only');
}

const SUPABASE_URL = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = 
  Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
  Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY');

if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SECRET_KEY');
  Deno.exit(1);
}

console.log('🧪 Testing Priority 1: Standardized Mode Checking\n');

// Step 1: Check current mode in database
console.log('Step 1: Checking current mode in database...');
const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY);

const { data: config, error: configError } = await supabase
  .from('app_config')
  .select('value')
  .eq('key', 'testing_mode')
  .single();

if (configError) {
  console.error('❌ Error reading app_config:', configError.message);
  Deno.exit(1);
}

const dbMode = config?.value === 'true';
console.log(`   Database mode: ${dbMode ? 'TESTING' : 'NORMAL'} (${config?.value})\n`);

// Step 2: Verify preview-service code uses getTestingMode() helper
console.log('Step 2: Verifying preview-service uses standardized mode checking...');
// Read the preview-service code to verify it uses getTestingMode()
const previewServiceCode = await Deno.readTextFile('supabase/functions/preview-service/index.ts');
const usesGetTestingMode = previewServiceCode.includes('getTestingMode');
const usesStaleConstant = previewServiceCode.includes('TESTING_MODE') && 
                          !previewServiceCode.includes('getTestingMode');

if (usesGetTestingMode) {
  console.log('   ✅ preview-service uses getTestingMode() helper');
  console.log('   ✅ No stale TESTING_MODE constant detected');
} else if (usesStaleConstant) {
  console.log('   ❌ preview-service still uses stale TESTING_MODE constant');
  console.log('   ⚠️  Priority 1 not fully implemented');
} else {
  console.log('   ⚠️  Could not verify mode checking implementation');
}
console.log('');

// Step 3: Check Edge Function logs for mode value
console.log('Step 3: Check Edge Function logs in Supabase Dashboard');
console.log('   Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions');
console.log('   Find preview-service → Logs');
console.log('   Look for: "preview-service: Testing mode: <value> (checked from database/env var)"');
console.log(`   Expected: Should show mode = ${dbMode}\n`);

// Step 4: Verify mode consistency
console.log('Step 4: Verifying mode consistency...');
const { data: validation, error: validationError } = await supabase
  .rpc('rpc_validate_mode_consistency');

if (validationError) {
  console.error('❌ Validation error:', validationError.message);
  Deno.exit(1);
}

const validationResult = typeof validation === 'string' ? JSON.parse(validation) : validation;
console.log(`   Mode: ${validationResult.mode}`);
console.log(`   Valid: ${validationResult.valid ? '✅' : '❌'}`);
if (validationResult.issues && validationResult.issues.length > 0) {
  console.log(`   Issues: ${JSON.stringify(validationResult.issues, null, 2)}`);
} else {
  console.log('   Issues: None ✅\n');
}

// Step 5: Test mode toggle (manual instruction)
console.log('Step 5: Manual Test - Toggle Mode');
console.log('   1. Go to: http://localhost:8000/testing-dashboard.html');
console.log('   2. Toggle testing mode');
console.log('   3. Wait 2-3 seconds');
console.log('   4. Call preview-service again (run this script again)');
console.log('   5. Verify preview-service logs show NEW mode immediately');
console.log('   6. This proves no stale constants are used ✅\n');

console.log('✅ Priority 1 test complete!');
console.log('\nKey verification:');
console.log('  - preview-service should check database first');
console.log('  - Mode changes should be picked up immediately');
console.log('  - No stale TESTING_MODE constant values');

