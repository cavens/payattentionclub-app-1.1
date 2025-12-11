// Supabase Edge Function: confirm-setup-intent
// This function confirms a Stripe SetupIntent using an Apple Pay payment token

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
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
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
    const { clientSecret, paymentMethodId } = body

    // Validate required fields
    if (!clientSecret || !paymentMethodId) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: clientSecret and paymentMethodId' }),
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

    // Extract SetupIntent ID from client secret (format: seti_xxx_secret_yyy)
    const setupIntentId = clientSecret.split('_secret_')[0]

    // First, retrieve the SetupIntent to check its current status
    const retrieveResponse = await fetch(`https://api.stripe.com/v1/setup_intents/${setupIntentId}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${stripeSecretKey}`,
      },
    })

    if (!retrieveResponse.ok) {
      const errorText = await retrieveResponse.text()
      console.error('Failed to retrieve SetupIntent:', errorText)
      return new Response(
        JSON.stringify({ error: 'Failed to retrieve SetupIntent from Stripe', details: errorText }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const setupIntent = await retrieveResponse.json()

    // If already confirmed or succeeded, return success
    if (setupIntent.status === 'succeeded' || setupIntent.status === 'processing') {
      return new Response(
        JSON.stringify({ 
          success: true, 
          setupIntentId: setupIntent.id, 
          paymentMethodId: setupIntent.payment_method || paymentMethodId,
          alreadyConfirmed: true 
        }),
        { 
          status: 200, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // If cancelled, we can't confirm it
    if (setupIntent.status === 'canceled') {
      console.error('SetupIntent is in invalid state:', setupIntent.status)
      return new Response(
        JSON.stringify({ error: `SetupIntent is in invalid state: ${setupIntent.status}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Now confirm the SetupIntent with the PaymentMethod
    const returnUrl = 'https://payattentionclub.app/payment-return'
    
    const confirmResponse = await fetch(`https://api.stripe.com/v1/setup_intents/${setupIntentId}/confirm`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${stripeSecretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        payment_method: paymentMethodId,
        return_url: returnUrl,
      }).toString()
    })

    if (!confirmResponse.ok) {
      const errorText = await confirmResponse.text()
      console.error('Stripe SetupIntent confirmation error (status:', confirmResponse.status, '):', errorText)
      let errorDetails = errorText
      let errorMessage = 'Failed to confirm SetupIntent with Stripe'
      try {
        const errorJson = JSON.parse(errorText)
        if (errorJson.error) {
          errorMessage = errorJson.error.message || errorMessage
          if (errorJson.error.type) {
            errorMessage = `${errorMessage} (type: ${errorJson.error.type})`
          }
          if (errorJson.error.code) {
            errorMessage = `${errorMessage} (code: ${errorJson.error.code})`
          }
        }
        errorDetails = JSON.stringify(errorJson, null, 2)
      } catch (e) {
        errorDetails = errorText
      }
      return new Response(
        JSON.stringify({ 
          error: errorMessage, 
          details: errorDetails,
          statusCode: confirmResponse.status
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const setupIntentData = await confirmResponse.json()

    // Return success
    return new Response(
      JSON.stringify({ success: true, setupIntentId: setupIntentData.id, paymentMethodId: paymentMethodId }),
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



