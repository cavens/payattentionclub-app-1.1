/**
 * Test Client Setup
 * 
 * Creates and exports Supabase and Stripe clients for use in tests.
 * Uses service role key for full database access.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import Stripe from "https://esm.sh/stripe@14.5.0";
import { config } from "../config.ts";

// MARK: - Supabase Client

/**
 * Supabase client with service role privileges.
 * Use this for all test operations - bypasses RLS.
 */
export const supabase: SupabaseClient = createClient(
  config.supabase.url,
  config.supabase.secretKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  }
);

// MARK: - Stripe Client

/**
 * Stripe client for payment-related tests.
 * Only available if STRIPE_SECRET_KEY_TEST is set.
 */
export const stripe: Stripe | null = config.stripe.hasStripeKey
  ? new Stripe(config.stripe.secretKey, {
      apiVersion: "2023-10-16",
      typescript: true,
    })
  : null;

/**
 * Check if Stripe is available for payment tests.
 */
export function hasStripe(): boolean {
  return stripe !== null;
}

/**
 * Get Stripe client, throwing if not configured.
 * Use this in tests that require Stripe.
 */
export function requireStripe(): Stripe {
  if (!stripe) {
    throw new Error(
      "Stripe not configured. Set STRIPE_SECRET_KEY_TEST in .env to run payment tests."
    );
  }
  return stripe;
}

// MARK: - Helper Functions

/**
 * Call an RPC function and return the result.
 * Throws on error for cleaner test code.
 */
export async function callRpc<T>(
  functionName: string,
  params: Record<string, unknown> = {}
): Promise<T> {
  const { data, error } = await supabase.rpc(functionName, params);
  
  if (error) {
    throw new Error(`RPC ${functionName} failed: ${error.message}`);
  }
  
  return data as T;
}

/**
 * Call an edge function and return the JSON response.
 * Throws on non-2xx status.
 * 
 * Note: Always includes Authorization header with Supabase secret key.
 * This satisfies Supabase's middleware requirement for all Edge Functions.
 * Admin functions (like weekly-close) use the secret key internally, so passing
 * it externally is consistent and required by Supabase's platform.
 */
export async function callEdgeFunction<T>(
  functionName: string,
  body: Record<string, unknown> = {},
  method: "GET" | "POST" = "POST"
): Promise<T> {
  const url = `${config.supabase.url}/functions/v1/${functionName}`;
  
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    // Include apikey header for Supabase secret key
    "apikey": config.supabase.secretKey,
    // Include Authorization header (required by Supabase middleware)
    // Note: For weekly-close, JWT verification must be disabled in Supabase dashboard
    // Go to: Supabase Dashboard → Edge Functions → weekly-close → Settings → Verify JWT = false
    "Authorization": `Bearer ${config.supabase.secretKey}`,
  };
  
  const response = await fetch(url, {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
  
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Edge function ${functionName} failed (${response.status}): ${errorText}`
    );
  }
  
  return await response.json() as T;
}




