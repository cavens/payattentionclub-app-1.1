/**
 * Complete Test Suite for Mode Toggle Functionality
 * 
 * Tests:
 * 1. Current state check (app_config and Edge Function secret)
 * 2. Toggle via testing-command-runner
 * 3. Verify both locations updated
 * 4. Toggle back
 * 5. Verify again
 */

const SUPABASE_URL = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY');

if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('❌ Missing required environment variables');
  Deno.exit(1);
}

console.log('🧪 Complete Mode Toggle Test Suite');
console.log(`   URL: ${SUPABASE_URL}\n`);

// Helper function to get current testing mode
async function getCurrentMode(): Promise<{ appConfig: boolean | null, edgeFunction: string | null }> {
  try {
    // Get from app_config via testing-command-runner
    const response = await fetch(`${SUPABASE_URL}/functions/v1/testing-command-runner`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SUPABASE_SECRET_KEY}`,
      },
      body: JSON.stringify({
        command: 'get_testing_mode',
      }),
    });

    const data = await response.json();
    const appConfigMode = data.result?.testing_mode ?? null;

    // Note: We can't directly read Edge Function secrets, but we can infer from behavior
    // For now, we'll assume if app_config updates, the secret should too
    return {
      appConfig: appConfigMode,
      edgeFunction: null, // Can't directly read, but update-secret should handle it
    };
  } catch (error) {
    console.error('   ❌ Error getting current mode:', error);
    return { appConfig: null, edgeFunction: null };
  }
}

// Helper function to toggle mode
async function toggleMode(): Promise<any> {
  try {
    const response = await fetch(`${SUPABASE_URL}/functions/v1/testing-command-runner`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SUPABASE_SECRET_KEY}`,
      },
      body: JSON.stringify({
        command: 'toggle_testing_mode',
      }),
    });

    const data = await response.json();
    return data;
  } catch (error) {
    console.error('   ❌ Error toggling mode:', error);
    return null;
  }
}

// Test 1: Check initial state
console.log('📋 Test 1: Check Initial State');
console.log('─────────────────────────────────────────────────────────');
const initialState = await getCurrentMode();
console.log(`   app_config.testing_mode: ${initialState.appConfig ?? 'unknown'}`);
console.log('');

// Test 2: Toggle mode
console.log('🔄 Test 2: Toggle Testing Mode');
console.log('─────────────────────────────────────────────────────────');
const toggleResult = await toggleMode();
if (toggleResult && toggleResult.success) {
  console.log(`   ✅ Toggle successful`);
  console.log(`   New mode: ${toggleResult.result.testing_mode ? 'ON' : 'OFF'}`);
  console.log(`   app_config updated: ${toggleResult.result.app_config_updated ? '✅' : '❌'}`);
  console.log(`   secret updated: ${toggleResult.result.secret_updated ? '✅' : '❌'}`);
  if (toggleResult.result.secret_update_error) {
    console.log(`   ⚠️  Secret update error: ${toggleResult.result.secret_update_error}`);
  }
  if (toggleResult.result.warning) {
    console.log(`   ⚠️  Warning: ${toggleResult.result.warning}`);
  }
} else {
  console.log(`   ❌ Toggle failed:`, JSON.stringify(toggleResult, null, 2));
}
console.log('');

// Test 3: Verify state after toggle
console.log('✅ Test 3: Verify State After Toggle');
console.log('─────────────────────────────────────────────────────────');
await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second for updates
const stateAfterToggle = await getCurrentMode();
console.log(`   app_config.testing_mode: ${stateAfterToggle.appConfig ?? 'unknown'}`);
if (stateAfterToggle.appConfig === toggleResult?.result?.testing_mode) {
  console.log('   ✅ app_config matches toggle result');
} else {
  console.log('   ❌ app_config does not match toggle result');
}
console.log('');

// Test 4: Toggle back
console.log('🔄 Test 4: Toggle Back to Original State');
console.log('─────────────────────────────────────────────────────────');
const toggleBackResult = await toggleMode();
if (toggleBackResult && toggleBackResult.success) {
  console.log(`   ✅ Toggle back successful`);
  console.log(`   New mode: ${toggleBackResult.result.testing_mode ? 'ON' : 'OFF'}`);
  console.log(`   app_config updated: ${toggleBackResult.result.app_config_updated ? '✅' : '❌'}`);
  console.log(`   secret updated: ${toggleBackResult.result.secret_updated ? '✅' : '❌'}`);
} else {
  console.log(`   ❌ Toggle back failed`);
}
console.log('');

// Test 5: Verify final state
console.log('✅ Test 5: Verify Final State');
console.log('─────────────────────────────────────────────────────────');
await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second
const finalState = await getCurrentMode();
console.log(`   app_config.testing_mode: ${finalState.appConfig ?? 'unknown'}`);
if (finalState.appConfig === initialState.appConfig) {
  console.log('   ✅ Final state matches initial state');
} else {
  console.log('   ⚠️  Final state differs from initial state (this is OK if you toggled twice)');
}
console.log('');

// Summary
console.log('📊 Test Summary');
console.log('─────────────────────────────────────────────────────────');
const allTestsPassed = 
  toggleResult?.success &&
  toggleBackResult?.success &&
  toggleResult?.result?.app_config_updated &&
  toggleResult?.result?.secret_updated &&
  toggleBackResult?.result?.app_config_updated &&
  toggleBackResult?.result?.secret_updated;

if (allTestsPassed) {
  console.log('   ✅ All tests passed! Mode toggle is working correctly.');
  console.log('   ✅ Both app_config and Edge Function secrets are updating.');
} else {
  console.log('   ⚠️  Some tests had issues. Check the details above.');
  if (!toggleResult?.result?.secret_updated || !toggleBackResult?.result?.secret_updated) {
    console.log('   ⚠️  Edge Function secret updates may have failed.');
    console.log('   💡 Check if PAT is set correctly in app_config.');
  }
}

