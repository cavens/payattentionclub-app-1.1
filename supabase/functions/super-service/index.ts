import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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

    // Parse request body
    const body = await req.json()
    // Note: weekStartDate from the app is actually the deadline (next Monday before noon)
    const { weekStartDate, limitMinutes, penaltyPerMinuteCents, appCount, appsToLimit, savedPaymentMethodId } = body

    // Validate required fields
    if (!weekStartDate || !limitMinutes || penaltyPerMinuteCents === undefined || appCount === undefined || !appsToLimit) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: weekStartDate, limitMinutes, penaltyPerMinuteCents, appCount, appsToLimit' }),
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

    // Call the RPC function
    // Note: weekStartDate is the deadline, not the start date
    // The commitment starts NOW (when user commits) and ends on the deadline
    const { data, error } = await supabase.rpc('rpc_create_commitment', {
      p_deadline_date: weekStartDate,  // This is the deadline (next Monday before noon)
      p_limit_minutes: limitMinutes,
      p_penalty_per_minute_cents: penaltyPerMinuteCents,
      p_app_count: appCount,  // NEW: Explicit app count parameter (single source of truth)
      p_apps_to_limit: appsToLimit,
      p_saved_payment_method_id: savedPaymentMethodId || null
    })

    if (error) {
      console.error('RPC error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
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
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

