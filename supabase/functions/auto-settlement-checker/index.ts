/**
 * Auto Settlement Checker Edge Function
 * 
 * Checks for commitments with expired grace periods and triggers settlement automatically.
 * This function is called by a cron job that runs frequently (every 1 min in testing, every 5 min in normal mode).
 * 
 * Only processes commitments where:
 * - week_grace_expires_at <= NOW()
 * - Not already settled (no penalty record with settlement_status)
 * - Has payment method and Stripe customer
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { TESTING_MODE } from "../_shared/timing.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SECRET_KEY = 
  Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || 
  Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY");

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Use POST", { status: 405 });
  }

  if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
    return new Response(
      JSON.stringify({ error: "Supabase credentials missing" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY);

  try {
    // Find commitments with expired grace periods that haven't been settled yet
    const now = new Date().toISOString();
    
    // Query commitments where grace period has expired
    const { data: expiredCommitments, error: fetchError } = await supabase
      .from("commitments")
      .select(`
        id,
        user_id,
        week_end_date,
        week_grace_expires_at,
        saved_payment_method_id,
        max_charge_cents,
        status,
        created_at
      `)
      .lte("week_grace_expires_at", now)
      .not("saved_payment_method_id", "is", null)
      .eq("status", "active");

    if (fetchError) {
      console.error("auto-settlement-checker: Error fetching commitments:", fetchError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch commitments", details: fetchError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!expiredCommitments || expiredCommitments.length === 0) {
      return new Response(
        JSON.stringify({ 
          message: "No commitments with expired grace periods found",
          checked_at: now,
          count: 0
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`auto-settlement-checker: Found ${expiredCommitments.length} commitments with expired grace periods`);

    // Check which ones are already settled by checking user_week_penalties
    const userIds = expiredCommitments.map(c => c.user_id);
    const { data: existingPenalties, error: penaltyError } = await supabase
      .from("user_week_penalties")
      .select("user_id, week_start_date, settlement_status")
      .in("user_id", userIds);

    if (penaltyError) {
      console.error("auto-settlement-checker: Error fetching penalties:", penaltyError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch penalties", details: penaltyError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Filter out already settled commitments
    const settledUserIds = new Set(
      (existingPenalties || [])
        .filter(p => p.settlement_status && 
          (p.settlement_status === "charged_worst_case" || 
           p.settlement_status === "charged_actual" ||
           p.settlement_status === "charged_actual_adjusted"))
        )
        .map(p => p.user_id)
    );

    const needsSettlement = expiredCommitments.filter(c => !settledUserIds.has(c.user_id));

    if (needsSettlement.length === 0) {
      return new Response(
        JSON.stringify({ 
          message: "All expired commitments are already settled",
          checked_at: now,
          expired_count: expiredCommitments.length,
          settled_count: settledUserIds.size
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`auto-settlement-checker: ${needsSettlement.length} commitments need settlement`);

    // Trigger settlement for all expired grace periods
    // We'll call bright-service which will handle the settlement logic
    const settlementUrl = `${SUPABASE_URL}/functions/v1/bright-service`;
    const settlementResponse = await fetch(settlementUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SUPABASE_SECRET_KEY}`,
        'x-manual-trigger': 'true',
      },
      body: JSON.stringify({}),
    });

    if (!settlementResponse.ok) {
      const errorText = await settlementResponse.text();
      console.error("auto-settlement-checker: Settlement trigger failed:", errorText);
      return new Response(
        JSON.stringify({ 
          error: "Settlement trigger failed", 
          details: errorText,
          needs_settlement_count: needsSettlement.length
        }),
        { status: settlementResponse.status, headers: { "Content-Type": "application/json" } }
      );
    }

    const settlementResult = await settlementResponse.json();

    return new Response(
      JSON.stringify({
        message: "Settlement triggered successfully",
        checked_at: now,
        expired_count: expiredCommitments.length,
        needs_settlement_count: needsSettlement.length,
        settlement_result: settlementResult
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("auto-settlement-checker: Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: "Unexpected error", details: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

