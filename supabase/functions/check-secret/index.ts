/**
 * Check Secret Edge Function
 * 
 * Safely checks if a secret is set and returns its value (for testing purposes only).
 * This allows verification that secrets are updated correctly.
 * 
 * Usage:
 *   POST /functions/v1/check-secret
 *   Headers: Authorization: Bearer <service_role_key>
 *   Body: { secretName: "TESTING_MODE" }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      { status: 405, headers: corsHeaders }
    );
  }

  try {
    // Get Supabase credentials for authentication
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY');

    if (!supabaseUrl || !supabaseSecretKey) {
      return new Response(
        JSON.stringify({ error: 'Supabase credentials missing' }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Security: Require secret header for authentication
    const CHECK_SECRET_KEY = Deno.env.get('CHECK_SECRET_KEY');
    if (CHECK_SECRET_KEY) {
      const providedSecret = req.headers.get('x-check-secret-key');
      if (providedSecret !== CHECK_SECRET_KEY) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized', message: 'Invalid or missing x-check-secret-key header' }),
          { status: 401, headers: corsHeaders }
        );
      }
    } else {
      // Fallback: Use service role key in Authorization header
      const authHeader = req.headers.get('Authorization');
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized', message: 'Missing Authorization header' }),
          { status: 401, headers: corsHeaders }
        );
      }
      const token = authHeader.replace('Bearer ', '');
      if (token !== supabaseSecretKey) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized', message: 'Invalid authorization token' }),
          { status: 401, headers: corsHeaders }
        );
      }
    }

    // Parse request body
    const body = await req.json();
    const { secretName } = body;

    if (!secretName) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: secretName' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Read the secret value from environment
    const secretValue = Deno.env.get(secretName);

    return new Response(
      JSON.stringify({ 
        success: true,
        secretName,
        exists: secretValue !== undefined,
        value: secretValue || null,  // Return actual value for verification
        length: secretValue ? secretValue.length : 0
      }),
      { status: 200, headers: corsHeaders }
    );

  } catch (error) {
    console.error('check-secret: Error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        details: error instanceof Error ? error.message : String(error) 
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

