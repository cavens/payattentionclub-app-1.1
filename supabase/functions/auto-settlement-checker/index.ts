/**
 * Auto Settlement Checker Edge Function
 * 
 * Automatically checks for expired grace periods and triggers settlement.
 * Only works in TESTING_MODE=true.
 * 
 * In testing mode:
 * - Runs every minute (via pg_cron)
 * - Finds commitments with expired grace periods
 * - Triggers settlement automatically
 * 
 * In normal mode:
 * - Exits immediately (does nothing)
 * - Normal settlement handled by weekly-close cron job
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { TESTING_MODE, GRACE_PERIOD_MS, WEEK_DURATION_MS } from "../_shared/timing.ts";

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

  // CRITICAL: Only work in testing mode
  if (!TESTING_MODE) {
    // In normal mode, exit immediately - don't interfere with production
    return new Response(
      JSON.stringify({ 
        message: 'Auto settlement checker is only for testing mode. Normal mode uses weekly-close cron job.',
        testing_mode: false 
      }),
      { status: 200, headers: corsHeaders }
    );
  }

  console.log("AUTO_SETTLEMENT_CHECKER: Testing mode active - checking for expired grace periods...");

  try {
    // Get Supabase client with service role (for full database access)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY') ||
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'); // Fallback for legacy name

    if (!supabaseUrl || !supabaseSecretKey) {
      return new Response(
        JSON.stringify({ error: 'Supabase credentials missing' }),
        { status: 500, headers: corsHeaders }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseSecretKey);

    // Get current time for comparison
    const now = new Date();

    // Find active commitments with expired grace periods
    // In testing mode, we need to check:
    // 1. If week_grace_expires_at is set and expired
    // 2. If week_grace_expires_at is null, calculate from created_at (4 minutes total: 3 min week + 1 min grace)
    const { data: commitments, error: fetchError } = await supabase
      .from('commitments')
      .select('id, user_id, week_end_date, week_grace_expires_at, created_at, status')
      .in('status', ['active', 'pending']);

    if (fetchError) {
      console.error("AUTO_SETTLEMENT_CHECKER: Error fetching commitments:", fetchError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch commitments', details: fetchError.message }),
        { status: 500, headers: corsHeaders }
      );
    }

    if (!commitments || commitments.length === 0) {
      console.log("AUTO_SETTLEMENT_CHECKER: No active commitments found.");
      return new Response(
        JSON.stringify({ message: 'No commitments to check', checked: 0, expired: 0 }),
        { status: 200, headers: corsHeaders }
      );
    }

    console.log(`AUTO_SETTLEMENT_CHECKER: Found ${commitments.length} active commitments to check.`);

    // Filter for commitments with expired grace periods
    const expiredCommitments = commitments.filter(commitment => {
      // Check explicit grace deadline first
      if (commitment.week_grace_expires_at) {
        const graceDeadline = new Date(commitment.week_grace_expires_at);
        return graceDeadline.getTime() <= now.getTime();
      }

      // In testing mode, calculate from created_at if week_grace_expires_at is null
      // Deadline is 3 minutes after creation, grace expires 1 minute after deadline (4 minutes total)
      if (commitment.created_at) {
        const createdAt = new Date(commitment.created_at);
        const deadline = new Date(createdAt.getTime() + WEEK_DURATION_MS); // 3 minutes
        const graceDeadline = new Date(deadline.getTime() + GRACE_PERIOD_MS); // 1 minute after deadline
        return graceDeadline.getTime() <= now.getTime();
      }

      // If no created_at, can't determine - skip
      return false;
    });

    if (expiredCommitments.length === 0) {
      console.log("AUTO_SETTLEMENT_CHECKER: No commitments with expired grace periods found.");
      return new Response(
        JSON.stringify({ 
          message: 'No expired grace periods', 
          checked: commitments.length, 
          expired: 0 
        }),
        { status: 200, headers: corsHeaders }
      );
    }

    console.log(`AUTO_SETTLEMENT_CHECKER: Found ${expiredCommitments.length} commitments with expired grace periods.`);

    // Trigger settlement for each expired commitment
    const settlementResults = [];
    for (const commitment of expiredCommitments) {
      console.log(`AUTO_SETTLEMENT_CHECKER: Triggering settlement for user ${commitment.user_id}, week ${commitment.week_end_date}`);
      
      const settlementUrl = `${supabaseUrl}/functions/v1/bright-service`;
      try {
        const settlementResponse = await fetch(settlementUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-manual-trigger': 'true', // Required for testing mode
            'Authorization': `Bearer ${supabaseSecretKey}`, // Use service role key for auth
          },
          body: JSON.stringify({ 
            targetWeek: commitment.week_end_date 
          }),
        });

        const settlementData = await settlementResponse.json();
        if (!settlementResponse.ok) {
          console.error(`AUTO_SETTLEMENT_CHECKER: Settlement failed for user ${commitment.user_id}:`, settlementData);
          settlementResults.push({
            userId: commitment.user_id,
            weekEndDate: commitment.week_end_date,
            status: 'failed',
            details: settlementData,
          });
        } else {
          console.log(`AUTO_SETTLEMENT_CHECKER: Settlement successful for user ${commitment.user_id}:`, settlementData);
          settlementResults.push({
            userId: commitment.user_id,
            weekEndDate: commitment.week_end_date,
            status: 'success',
            details: settlementData,
          });
        }
      } catch (error) {
        console.error(`AUTO_SETTLEMENT_CHECKER: Exception during settlement for user ${commitment.user_id}:`, error);
        settlementResults.push({
          userId: commitment.user_id,
          weekEndDate: commitment.week_end_date,
          status: 'exception',
          details: error.message,
        });
      }
    }

    return new Response(
      JSON.stringify({ 
        message: 'Auto settlement check complete', 
        checked: commitments.length,
        expired: expiredCommitments.length,
        results: settlementResults 
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error("AUTO_SETTLEMENT_CHECKER: Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: 'Unexpected error', details: error.message }),
      { status: 500, headers: corsHeaders }
    );
  }
});

