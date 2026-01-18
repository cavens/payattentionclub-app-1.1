/**
 * Test script for update-secret Edge Function
 * Tests if the Management API can update Edge Function secrets
 */

const SUPABASE_URL = Deno.env.get('STAGING_SUPABASE_URL') || Deno.env.get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || Deno.env.get('SUPABASE_SECRET_KEY');

if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('❌ Missing required environment variables:');
  console.error('   STAGING_SUPABASE_URL (or SUPABASE_URL)');
  console.error('   STAGING_SUPABASE_SECRET_KEY (or SUPABASE_SECRET_KEY)');
  Deno.exit(1);
}

console.log('🧪 Testing update-secret Edge Function');
console.log(`   URL: ${SUPABASE_URL}`);
console.log('');

// Test 1: Try to update TESTING_MODE secret
console.log('Test 1: Updating TESTING_MODE secret...');
try {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/update-secret`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SUPABASE_SECRET_KEY}`,
    },
    body: JSON.stringify({
      secretName: 'TESTING_MODE',
      secretValue: 'true', // Test value
    }),
  });

  const data = await response.json();
  
  console.log(`   Status: ${response.status} ${response.statusText}`);
  console.log(`   Response:`, JSON.stringify(data, null, 2));
  
  if (response.ok) {
    console.log('   ✅ Success! Management API works');
  } else {
    console.log('   ❌ Failed - Management API may not be available or requires different auth');
    console.log('   💡 You may need to update secrets manually in Supabase Dashboard');
  }
} catch (error) {
  console.error('   ❌ Error:', error instanceof Error ? error.message : String(error));
  console.error('   💡 Check if update-secret function is deployed and accessible');
}

console.log('');
console.log('📝 Next steps:');
console.log('   1. If test succeeds: The toggle_testing_mode command will work automatically');
console.log('   2. If test fails: We may need to use a different approach (CLI or manual update)');
console.log('   3. Check Supabase Dashboard → Edge Functions → update-secret → Logs for details');

