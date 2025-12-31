import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { validateUUID, validatePositiveNumber, validateDateString, validateStringArray } from '../_shared/validation.ts'
import { checkRateLimit, createRateLimitHeaders, createRateLimitResponse } from '../_shared/rateLimit.ts'

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

    // Rate limiting: Check if user has exceeded rate limit
    // Critical Edge Functions: 30 requests per minute per user
    const rateLimitResult = await checkRateLimit(
      supabase,
      user.id,
      {
        maxRequests: 30,
        windowMs: 60 * 1000, // 1 minute
        keyPrefix: "super-service",
      }
    );

    if (!rateLimitResult.allowed) {
      console.warn(`super-service: Rate limit exceeded for user ${user.id}`);
      return createRateLimitResponse(rateLimitResult, corsHeaders);
    }

    console.log(`super-service: Rate limit check passed. Remaining: ${rateLimitResult.remaining}`);

    // Parse request body
    const body = await req.json()
    // Note: weekStartDate from the app is actually the deadline (next Monday before noon)
    const { weekStartDate, limitMinutes, penaltyPerMinuteCents, appsToLimit, savedPaymentMethodId } = body

    // Validate required fields exist
    if (!weekStartDate || limitMinutes === undefined || penaltyPerMinuteCents === undefined || !appsToLimit) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: weekStartDate, limitMinutes, penaltyPerMinuteCents, appsToLimit' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate user ID from authenticated user matches (if provided in body)
    if (body.userId) {
      const userId = validateUUID(body.userId)
      if (!userId) {
        return new Response(
          JSON.stringify({ error: 'Invalid user ID format' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      // Verify user ID matches authenticated user
      if (userId !== user.id) {
        return new Response(
          JSON.stringify({ error: 'User ID mismatch' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Validate date format (YYYY-MM-DD)
    const validatedDate = validateDateString(weekStartDate)
    if (!validatedDate) {
      return new Response(
        JSON.stringify({ error: 'Invalid date format. Expected YYYY-MM-DD' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate limitMinutes (0 to 2520 minutes = 42 hours max)
    const validatedLimitMinutes = validatePositiveNumber(limitMinutes, 2520)
    if (validatedLimitMinutes === null) {
      return new Response(
        JSON.stringify({ error: 'Invalid limitMinutes. Must be a positive number between 0 and 2520 (42 hours)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate penaltyPerMinuteCents (0 to 500 cents = $5.00 max per minute)
    const validatedPenaltyCents = validatePositiveNumber(penaltyPerMinuteCents, 500)
    if (validatedPenaltyCents === null) {
      return new Response(
        JSON.stringify({ error: 'Invalid penaltyPerMinuteCents. Must be a positive number between 0 and 500 ($5.00 per minute)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate appsToLimit is an array of strings
    const validatedApps = validateStringArray(appsToLimit)
    if (!validatedApps) {
      return new Response(
        JSON.stringify({ error: 'Invalid appsToLimit. Must be an array of strings' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate savedPaymentMethodId if provided (should be a string starting with "pm_")
    if (savedPaymentMethodId !== null && savedPaymentMethodId !== undefined) {
      if (typeof savedPaymentMethodId !== 'string' || !savedPaymentMethodId.startsWith('pm_')) {
        return new Response(
          JSON.stringify({ error: 'Invalid savedPaymentMethodId format. Expected Stripe payment method ID (pm_...)' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Call the RPC function with validated data
    // Note: weekStartDate is the deadline, not the start date
    // The commitment starts NOW (when user commits) and ends on the deadline
    const { data, error } = await supabase.rpc('rpc_create_commitment', {
      p_deadline_date: validatedDate,  // This is the deadline (next Monday before noon)
      p_limit_minutes: validatedLimitMinutes,
      p_penalty_per_minute_cents: validatedPenaltyCents,
      p_apps_to_limit: validatedApps,
      p_saved_payment_method_id: savedPaymentMethodId || null
    })

    if (error) {
      console.error('RPC error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Return the JSON response with rate limit headers
    return new Response(
      JSON.stringify(data),
      { 
        status: 200, 
        headers: { 
          ...corsHeaders, 
          'Content-Type': 'application/json',
          ...createRateLimitHeaders(rateLimitResult),
        } 
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

