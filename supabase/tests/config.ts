/**
 * Test Configuration
 * 
 * Loads environment variables for test execution.
 * Filter logs by "TESTCONFIG" to see configuration status.
 * 
 * Usage:
 *   1. Copy .env.example to .env and fill in your values
 *   2. Run tests with: deno test --allow-net --allow-env --allow-read
 */

import "https://deno.land/std@0.208.0/dotenv/load.ts";

// MARK: - Environment Variables

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const STRIPE_SECRET_KEY_TEST = Deno.env.get("STRIPE_SECRET_KEY_TEST");

// MARK: - Validation

const missingVars: string[] = [];

if (!SUPABASE_URL) missingVars.push("SUPABASE_URL");
if (!SUPABASE_SERVICE_ROLE_KEY) missingVars.push("SUPABASE_SERVICE_ROLE_KEY");
// SUPABASE_ANON_KEY is optional for backend tests (we use service role)
// STRIPE_SECRET_KEY_TEST is optional (only needed for payment tests)

if (missingVars.length > 0) {
  console.error("TESTCONFIG ❌ Missing required environment variables:");
  missingVars.forEach((v) => console.error(`TESTCONFIG   - ${v}`));
  console.error("TESTCONFIG");
  console.error("TESTCONFIG 💡 Create a .env file in the project root with:");
  console.error("TESTCONFIG    SUPABASE_URL=https://your-project.supabase.co");
  console.error("TESTCONFIG    SUPABASE_SERVICE_ROLE_KEY=your-service-role-key");
  console.error("TESTCONFIG");
  throw new Error(`Missing required environment variables: ${missingVars.join(", ")}`);
}

// MARK: - Exported Config

export const config = {
  supabase: {
    url: SUPABASE_URL!,
    serviceRoleKey: SUPABASE_SERVICE_ROLE_KEY!,
    anonKey: SUPABASE_ANON_KEY ?? "",
  },
  stripe: {
    secretKey: STRIPE_SECRET_KEY_TEST ?? "",
    hasStripeKey: !!STRIPE_SECRET_KEY_TEST,
  },
} as const;

// MARK: - Test User IDs (matching rpc_setup_test_data)

export const TEST_USER_IDS = {
  testUser1: "11111111-1111-1111-1111-111111111111",
  testUser2: "22222222-2222-2222-2222-222222222222",
  testUser3: "33333333-3333-3333-3333-333333333333",
  // Real user ID is dynamic (looked up by email in rpc_setup_test_data)
} as const;

// MARK: - Logging

console.log("TESTCONFIG ========================================");
console.log(`TESTCONFIG Supabase URL: ${config.supabase.url}`);
console.log(`TESTCONFIG Service Role Key: ${config.supabase.serviceRoleKey.substring(0, 20)}...`);
console.log(`TESTCONFIG Anon Key: ${config.supabase.anonKey ? config.supabase.anonKey.substring(0, 20) + "..." : "(not set)"}`);
console.log(`TESTCONFIG Stripe Key: ${config.stripe.hasStripeKey ? "✅ Set" : "⚠️ Not set (payment tests will skip)"}`);
console.log("TESTCONFIG ========================================");

