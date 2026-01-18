/**
 * Trigger preview-service Edge Function to generate logs
 * This helps verify Priority 1 (standardized mode checking) is working
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
const SUPABASE_ANON_KEY = Deno.env.get('STAGING_SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_ANON_KEY');
const SUPABASE_SECRET_KEY = 
  Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
  Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY');

if (!SUPABASE_URL) {
  console.error('❌ Missing SUPABASE_URL');
  Deno.exit(1);
}

console.log('🚀 Triggering preview-service to generate logs...\n');
console.log(`   URL: ${SUPABASE_URL}/functions/v1/preview-service\n`);

// Try with anon key first (if function is public)
let response;
if (SUPABASE_ANON_KEY) {
  console.log('   Attempting with anon key...');
  response = await fetch(`${SUPABASE_URL}/functions/v1/preview-service`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      'apikey': SUPABASE_ANON_KEY,
    },
    body: JSON.stringify({
      limitMinutes: 60,
      penaltyPerMinuteCents: 100,
      appCount: 1,
      appsToLimit: {
        app_bundle_ids: ['com.example.test'],
        categories: []
      }
    })
  });
} else {
  console.log('   Attempting without auth (public function)...');
  response = await fetch(`${SUPABASE_URL}/functions/v1/preview-service`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      limitMinutes: 60,
      penaltyPerMinuteCents: 100,
      appCount: 1,
      appsToLimit: {
        app_bundle_ids: ['com.example.test'],
        categories: []
      }
    })
  });
}

console.log(`   Status: ${response.status} ${response.statusText}`);

if (!response.ok) {
  const errorText = await response.text();
  console.error(`   ❌ Error: ${errorText}\n`);
  
  // Try with service role key as fallback
  if (SUPABASE_SECRET_KEY) {
    console.log('   Trying with service role key...');
    const response2 = await fetch(`${SUPABASE_URL}/functions/v1/preview-service`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SUPABASE_SECRET_KEY}`,
        'apikey': SUPABASE_SECRET_KEY,
      },
      body: JSON.stringify({
        limitMinutes: 60,
        penaltyPerMinuteCents: 100,
        appCount: 1,
        appsToLimit: {
          app_bundle_ids: ['com.example.test'],
          categories: []
        }
      })
    });
    
    console.log(`   Status: ${response2.status} ${response2.statusText}`);
    if (response2.ok) {
      const data = await response2.json();
      console.log('   ✅ Success! Function was triggered.\n');
      console.log('   Response:', JSON.stringify(data, null, 2));
    } else {
      const errorText2 = await response2.text();
      console.error(`   ❌ Error: ${errorText2}`);
    }
  }
} else {
  const data = await response.json();
  console.log('   ✅ Success! Function was triggered.\n');
  console.log('   Response:', JSON.stringify(data, null, 2));
}

console.log('\n📋 Next Steps:');
console.log('   1. Wait 10-30 seconds for logs to appear');
console.log('   2. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/functions');
console.log('   3. Click on "preview-service"');
console.log('   4. Click on "Logs" tab');
console.log('   5. Look for: "preview-service: Testing mode: <value> (checked from database/env var)"');

