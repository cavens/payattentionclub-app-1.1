import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { TESTING_MODE, getNextDeadline } from "../_shared/timing.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * Format a Date object as YYYY-MM-DD string (normal mode)
 * or ISO 8601 string (testing mode for precise timing)
 */
function formatDeadlineDate(date: Date, isTestingMode: boolean): string {
  if (isTestingMode) {
    // In testing mode, return full ISO timestamp for precise timing
    // Format: YYYY-MM-DDTHH:mm:ss.sssZ
    return date.toISOString();
  }
  // In normal mode, return just the date (YYYY-MM-DD)
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
    date.getDate()
  ).padStart(2, "0")}`;
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

    // Check testing mode from both environment variable AND database config
    // This allows testing mode to work even if only database config is set
    // Database config (app_config) is the primary source of truth
    let isTestingMode = TESTING_MODE;
    
    if (!isTestingMode) {
      // Check database app_config table for testing mode
      // Use service role key to bypass RLS (if enabled)
      try {
        const supabaseAdmin = createClient(supabaseUrl, supabaseSecretKey);
        const { data: config, error: configError } = await supabaseAdmin
          .from('app_config')
          .select('value')
          .eq('key', 'testing_mode')
          .single();
        
        if (!configError && config && config.value === 'true') {
          isTestingMode = true;
          console.log('super-service: Testing mode enabled via app_config table');
        } else if (configError) {
          console.log(`super-service: Could not read app_config: ${configError.message}`);
        }
      } catch (error) {
        // If app_config table doesn't exist or query fails, continue with env var check
        console.log(`super-service: Could not check app_config: ${error instanceof Error ? error.message : String(error)}`);
      }
    } else {
      console.log('super-service: Testing mode enabled via environment variable');
    }

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
    // Testing mode: 3 minutes from now
    // Normal mode: Next Monday 12:00 ET
    // Note: We use isTestingMode (from database or env var) instead of TESTING_MODE constant
    // because getNextDeadline() uses the constant which is evaluated at module load time
    const now = new Date();
    const deadline = isTestingMode 
      ? new Date(now.getTime() + (3 * 60 * 1000)) // 3 minutes from now
      : getNextDeadline(now); // Normal mode: next Monday 12:00 ET
    
    const deadlineDateForRPC = formatDeadlineDate(deadline, isTestingMode).split('T')[0]; // Extract YYYY-MM-DD
    const deadlineTimestampForRPC = isTestingMode ? formatDeadlineDate(deadline, isTestingMode) : null; // Precise timestamp for testing mode
    const compressedDeadlineISO = isTestingMode ? formatDeadlineDate(deadline, isTestingMode) : null; // Store full ISO timestamp for response transformation
    
    console.log(`super-service: Calculated deadline date: ${deadlineDateForRPC} (testing mode: ${isTestingMode})`);
    console.log(`🧪 TEST 5 - COMMITMENT: Backend calculated deadline at ${new Date().toISOString()}: ${compressedDeadlineISO || deadlineDateForRPC}`);

    // Call the RPC function
    // Note: deadlineDateForRPC is the deadline date (YYYY-MM-DD), not the start date
    // The commitment starts NOW (when user commits) and ends on the deadline
    // Parameters must match the RPC function signature order:
    // p_deadline_date, p_limit_minutes, p_penalty_per_minute_cents, p_app_count, p_apps_to_limit, p_saved_payment_method_id, p_deadline_timestamp
    const { data, error } = await supabase.rpc('rpc_create_commitment', {
      p_deadline_date: deadlineDateForRPC,  // Date format (YYYY-MM-DD) for RPC
      p_limit_minutes: limitMinutes,
      p_penalty_per_minute_cents: penaltyPerMinuteCents,
      p_app_count: appCount,  // Explicit app count parameter (single source of truth)
      p_apps_to_limit: appsToLimit,
      p_saved_payment_method_id: savedPaymentMethodId || null,
      p_deadline_timestamp: deadlineTimestampForRPC  // Precise timestamp (testing mode) or NULL (normal mode)
    })

    if (error) {
      console.error('RPC error:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // In testing mode, transform the response to include full ISO timestamp for deadline
    // The RPC returns week_end_date as a date (YYYY-MM-DD), but we need the full timestamp
    if (isTestingMode && data && compressedDeadlineISO) {
      // Replace week_end_date with full ISO timestamp
      data.week_end_date = compressedDeadlineISO;
      console.log(`super-service: Testing mode - transformed week_end_date to ISO timestamp: ${compressedDeadlineISO}`);
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

