import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { getNextDeadline } from "../_shared/timing.ts"
import { getTestingMode } from "../_shared/mode-check.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// formatDeadlineDate function removed - no longer needed
// Both modes now use timestamps directly via toISOString()

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract the JWT token
    const token = authHeader.replace('Bearer ', '')
    
    // Create Supabase client with the user's JWT token
    // This ensures auth.uid() in the RPC function works correctly
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    // Use environment-specific secret key (STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY)
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY')
    
    if (!supabaseSecretKey) {
      return new Response(
        JSON.stringify({ error: 'supabaseKey is required. STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY must be set in Edge Function secrets.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    
    const supabase = createClient(supabaseUrl, supabaseSecretKey, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    })
    
    // Verify the token and get the user
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check testing mode from database (primary source) or env var (fallback)
    // This ensures consistent mode checking across all functions
    const supabaseAdmin = createClient(supabaseUrl, supabaseSecretKey);
    const isTestingMode = await getTestingMode(supabaseAdmin);
    console.log(`super-service: Testing mode: ${isTestingMode} (checked from database/env var)`);

    // Parse request body
    const body = await req.json()
    // Note: weekStartDate parameter removed - backend now calculates deadline internally
    const { limitMinutes, penaltyPerMinuteCents, appCount, appsToLimit, savedPaymentMethodId } = body

    // Validate required fields
    if (!limitMinutes || penaltyPerMinuteCents === undefined || appCount === undefined || !appsToLimit) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: limitMinutes, penaltyPerMinuteCents, appCount, appsToLimit' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate appCount is a non-negative integer
    if (typeof appCount !== 'number' || appCount < 0 || !Number.isInteger(appCount)) {
      return new Response(
        JSON.stringify({ error: 'Invalid appCount. Must be a non-negative integer.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Calculate deadline internally (single source of truth)
    // Testing mode: 4 minutes from now
    // Normal mode: Next Monday 12:00 ET
    const now = new Date();
    const deadline = getNextDeadline(isTestingMode, now);
    
    // Always use timestamp (both modes now use same structure)
    const deadlineTimestamp = deadline.toISOString();
    
    // Calculate grace duration based on mode
    // Testing mode: 1 minute = 0.0167 hours
    // Normal mode: 24 hours
    const TESTING_GRACE_PERIOD_MINUTES = 1;
    const graceDurationHours = isTestingMode 
      ? TESTING_GRACE_PERIOD_MINUTES / 60.0  // 1 minute = 0.0167 hours
      : 24;  // 24 hours
    
    console.log(`super-service: Calculated deadline timestamp: ${deadlineTimestamp} (testing mode: ${isTestingMode})`);
    console.log(`super-service: Grace duration: ${graceDurationHours} hours`);
    console.log(`🧪 TEST 5 - COMMITMENT: Backend calculated deadline at ${new Date().toISOString()}: ${deadlineTimestamp}`);

    // Call the RPC function
    // ALIGNED WITH TESTING MODE: Both modes now pass timestamp and grace_duration_hours
    // Parameters must match the RPC function signature order:
    // p_limit_minutes, p_penalty_per_minute_cents, p_app_count, p_apps_to_limit, p_saved_payment_method_id, p_deadline_timestamp, p_grace_duration_hours
    const { data, error } = await supabase.rpc('rpc_create_commitment', {
      p_limit_minutes: limitMinutes,
      p_penalty_per_minute_cents: penaltyPerMinuteCents,
      p_app_count: appCount,  // Explicit app count parameter (single source of truth)
      p_apps_to_limit: appsToLimit,
      p_deadline_timestamp: deadlineTimestamp,  // Always pass timestamp (both modes)
      p_grace_duration_hours: graceDurationHours,  // Always pass grace duration (both modes)
      p_saved_payment_method_id: savedPaymentMethodId || null  // Optional: comes last
    })

    if (error) {
      console.error('RPC error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Response now includes week_end_timestamp (both modes)
    // No transformation needed - timestamp is already in response
    if (data) {
      console.log(`super-service: Commitment created with week_end_timestamp: ${data.week_end_timestamp}`);
    }

    // Return the JSON response
    return new Response(
      JSON.stringify(data),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  } catch (error) {
    console.error('Edge function error:', error)
    const errorMessage = error instanceof Error ? error.message : String(error)
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

