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
    // Create Supabase client (preview doesn't require auth, but we'll use service role for RPC)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY')
    
    if (!supabaseSecretKey) {
      return new Response(
        JSON.stringify({ error: 'supabaseKey is required. STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY must be set in Edge Function secrets.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    
    const supabase = createClient(supabaseUrl, supabaseSecretKey)

    // Check testing mode from database (primary source) or env var (fallback)
    // This ensures consistent mode checking across all functions
    const isTestingMode = await getTestingMode(supabase);
    console.log(`preview-service: Testing mode: ${isTestingMode} (checked from database/env var)`);

    // Parse request body
    const body = await req.json()
    const { limitMinutes, penaltyPerMinuteCents, appCount, appsToLimit } = body

    // Validate required fields
    if (limitMinutes === undefined || penaltyPerMinuteCents === undefined || appCount === undefined || !appsToLimit) {
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
    const deadline = getNextDeadline(isTestingMode);
    
    // Always use timestamp (both modes now use same structure)
    const deadlineTimestamp = deadline.toISOString();
    const deadlineDateForRPC = deadlineTimestamp.split('T')[0]; // Extract YYYY-MM-DD for RPC
    
    console.log(`preview-service: Calculated deadline timestamp: ${deadlineTimestamp} (testing mode: ${isTestingMode})`);
    console.log(`🧪 TEST 5 - PREVIEW: Backend calculated deadline at ${new Date().toISOString()}: ${deadlineTimestamp}`);

    // Call the RPC function with calculated deadline
    // Note: rpc_preview_max_charge still uses p_deadline_date (date format)
    // This is fine - it extracts the date component from the timestamp
    const { data, error } = await supabase.rpc('rpc_preview_max_charge', {
      p_deadline_date: deadlineDateForRPC,  // Date format (YYYY-MM-DD) for RPC
      p_limit_minutes: limitMinutes,
      p_penalty_per_minute_cents: penaltyPerMinuteCents,
      p_app_count: appCount,
      p_apps_to_limit: appsToLimit
    })

    if (error) {
      console.error('RPC error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Return the JSON response (includes calculated deadline_date)
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

