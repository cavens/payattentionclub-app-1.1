// Supabase Edge Function: rapid-service
// This function confirms a Stripe PaymentIntent using an Apple Pay payment token,
// then immediately cancels it to release the authorization hold.
// The payment method is saved via setup_future_usage and returned.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno"
import { validateNonEmptyString } from '../_shared/validation.ts'
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
    // Use environment-specific secret key (STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY')
    
    if (!supabaseSecretKey) {
      console.error('rapid-service: Missing Supabase secret key')
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
    // Payment endpoints: 10 requests per minute per user
    const rateLimitResult = await checkRateLimit(
      supabase,
      user.id,
      {
        maxRequests: 10,
        windowMs: 60 * 1000, // 1 minute
        keyPrefix: "rapid-service",
      }
    );

    if (!rateLimitResult.allowed) {
      console.warn(`rapid-service: Rate limit exceeded for user ${user.id}`);
      return createRateLimitResponse(rateLimitResult, corsHeaders);
    }

    console.log(`rapid-service: Rate limit check passed. Remaining: ${rateLimitResult.remaining}`);

    // Parse request body
    const body = await req.json()
    const { clientSecret, paymentMethodId } = body

    // Validate required fields exist
    if (!clientSecret || !paymentMethodId) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: clientSecret and paymentMethodId' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate clientSecret format (should start with "pi_" and contain "_secret_")
    const validatedClientSecret = validateNonEmptyString(clientSecret, 200)
    if (!validatedClientSecret || !validatedClientSecret.startsWith('pi_') || !validatedClientSecret.includes('_secret_')) {
      return new Response(
        JSON.stringify({ error: 'Invalid clientSecret format. Expected Stripe PaymentIntent client secret (pi_xxx_secret_yyy)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate paymentMethodId format (should start with "pm_")
    const validatedPaymentMethodId = validateNonEmptyString(paymentMethodId, 100)
    if (!validatedPaymentMethodId || !validatedPaymentMethodId.startsWith('pm_')) {
      return new Response(
        JSON.stringify({ error: 'Invalid paymentMethodId format. Expected Stripe payment method ID (pm_...)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get Stripe secret key from environment
    const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY_TEST') || Deno.env.get('STRIPE_SECRET_KEY')
    if (!stripeSecretKey) {
      console.error('STRIPE_SECRET_KEY_TEST or STRIPE_SECRET_KEY not configured')
      return new Response(
        JSON.stringify({ error: 'Stripe configuration error - missing secret key' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Initialize Stripe client
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16"
    })

    // Extract PaymentIntent ID from validated client secret (format: pi_xxx_secret_yyy)
    const paymentIntentId = validatedClientSecret.split('_secret_')[0]

    // First, retrieve the PaymentIntent to check its current status
    let paymentIntent: Stripe.PaymentIntent
    try {
      paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId)
    } catch (error) {
      console.error('Failed to retrieve PaymentIntent:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to retrieve PaymentIntent from Stripe', details: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // If already succeeded or canceled, check if payment method was saved
    if (paymentIntent.status === 'succeeded' || paymentIntent.status === 'canceled') {
      // Payment method should be saved via setup_future_usage
      const savedPaymentMethodId = paymentIntent.payment_method
      if (savedPaymentMethodId && typeof savedPaymentMethodId === 'string') {
        return new Response(
          JSON.stringify({ 
            success: true, 
            paymentIntentId: paymentIntent.id, 
            paymentMethodId: savedPaymentMethodId,
            alreadyProcessed: true 
          }),
          { 
            status: 200, 
            headers: { 
              ...corsHeaders, 
              'Content-Type': 'application/json',
              ...createRateLimitHeaders(rateLimitResult),
            } 
          }
        )
      }
    }

    // If requires_capture or requires_action, we can't proceed
    if (paymentIntent.status === 'requires_capture' || paymentIntent.status === 'requires_action') {
      console.error('PaymentIntent is in invalid state for this flow:', paymentIntent.status)
      return new Response(
        JSON.stringify({ error: `PaymentIntent is in invalid state: ${paymentIntent.status}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Confirm the PaymentIntent with the validated PaymentMethod
    try {
      paymentIntent = await stripe.paymentIntents.confirm(paymentIntentId, {
        payment_method: validatedPaymentMethodId,
        return_url: "https://payattentionclub.app/payment-return" // Required by Stripe even though we use allow_redirects: never
      })
    } catch (error) {
      console.error('Stripe PaymentIntent confirmation error:', error)
      let errorMessage = 'Failed to confirm PaymentIntent with Stripe'
      if (error.message) {
        errorMessage = error.message
      }
      return new Response(
        JSON.stringify({ 
          error: errorMessage, 
          details: error.toString()
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract saved payment method ID (from setup_future_usage)
    const savedPaymentMethodId = paymentIntent.payment_method
    if (!savedPaymentMethodId || typeof savedPaymentMethodId !== 'string') {
      console.error('Payment method not saved after confirmation')
      return new Response(
        JSON.stringify({ error: 'Payment method was not saved. setup_future_usage may have failed.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Immediately cancel the PaymentIntent to release the authorization hold
    try {
      await stripe.paymentIntents.cancel(paymentIntentId)
      console.log(`PaymentIntent ${paymentIntentId} cancelled successfully - authorization released`)
    } catch (cancelError) {
      // Log error but don't fail - payment method is already saved
      console.error(`Warning: Failed to cancel PaymentIntent ${paymentIntentId}:`, cancelError)
      // Continue anyway - the payment method is saved and that's what matters
    }

    // Update user's has_active_payment_method flag in database
    try {
      const { error: updateError } = await supabase
        .from('users')
        .update({ has_active_payment_method: true })
        .eq('id', user.id)

      if (updateError) {
        console.error('Error updating has_active_payment_method:', updateError)
        // Don't fail - payment method is saved in Stripe
      }
    } catch (dbError) {
      console.error('Database update error:', dbError)
      // Don't fail - payment method is saved in Stripe
    }

    // Return success with saved payment method ID
    return new Response(
      JSON.stringify({ 
        success: true, 
        paymentIntentId: paymentIntent.id, 
        paymentMethodId: savedPaymentMethodId 
      }),
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
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})





