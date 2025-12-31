import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";
// Priority: STRIPE_SECRET_KEY_TEST (if exists) → STRIPE_SECRET_KEY (fallback)
const STRIPE_SECRET_KEY_TEST = Deno.env.get("STRIPE_SECRET_KEY_TEST");
const STRIPE_SECRET_KEY_PROD = Deno.env.get("STRIPE_SECRET_KEY");
const STRIPE_SECRET_KEY = STRIPE_SECRET_KEY_TEST || STRIPE_SECRET_KEY_PROD;
if (!STRIPE_SECRET_KEY) {
  console.error("ERROR: No Stripe secret key found. Please set STRIPE_SECRET_KEY_TEST or STRIPE_SECRET_KEY in Supabase secrets.");
}
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY");
// Change this if you want a different currency
const CURRENCY = "usd";
const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: "2023-10-16"
});
// Helper: format Date -> "YYYY-MM-DD"
function toDateString(d) {
  return d.toISOString().slice(0, 10);
}
Deno.serve(async (req)=>{
  try {
    // Optional: only allow POST
    if (req.method !== "POST") {
      return new Response("Use POST", {
        status: 405
      });
    }
    const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY);
    // 1) Determine last week (week being closed)
    // Assume function is scheduled every Monday 12:00 EST for "last week"
    // We need to find the deadline (week_end_date) that just passed
    // The deadline is Monday before noon. If function runs on Monday, we close the week ending today.
    // If it runs Tue-Sun, we close the week ending last Monday.
    const now = new Date();
    // Get today's day of week (0 = Sunday, 1 = Monday, etc.)
    const dayOfWeek = now.getUTCDay();
    // Calculate the Monday deadline for the week being closed
    let deadlineDate = new Date(now);
    if (dayOfWeek === 1) {
      // Today is Monday - close the week ending today
      // No adjustment needed
    } else if (dayOfWeek === 0) {
      // Today is Sunday - close the week ending tomorrow (Monday)
      deadlineDate.setUTCDate(deadlineDate.getUTCDate() + 1);
    } else {
      // Today is Tue-Sat - close the week ending last Monday
      const daysToSubtract = dayOfWeek - 1; // Days back to Monday
      deadlineDate.setUTCDate(deadlineDate.getUTCDate() - daysToSubtract);
    }
    const deadlineStr = toDateString(deadlineDate);
    console.log("Closing week with deadline:", deadlineStr);
    // 2) Insert estimated rows for commitments with revoked monitoring
    // FIXED: Use week_end_date (deadline) to identify commitments for this week
    // week_end_date stores the deadline (next Monday), which groups commitments by week
    const { data: revokedCommitments, error: revokedError } = await supabase.from("commitments").select("id, user_id, week_start_date, week_end_date, limit_minutes, penalty_per_minute_cents, monitoring_status, monitoring_revoked_at").eq("week_end_date", deadlineStr).eq("monitoring_status", "revoked");
    if (revokedError) {
      console.error("Error fetching revoked commitments:", revokedError);
      return new Response("Error fetching revoked commitments", {
        status: 500
      });
    }
    for (const c of revokedCommitments ?? []){
      if (!c.monitoring_revoked_at) continue;
      const revDate = new Date(c.monitoring_revoked_at);
      // Start from the date of revocation (date-only)
      let d = new Date(toDateString(revDate));
      const commitmentEnd = new Date(c.week_end_date || deadlineStr);
      while(d < commitmentEnd){
        const dayStr = toDateString(d);
        // Check if there's already a daily_usage row for this day
        const { data: existing, error: existingErr } = await supabase.from("daily_usage").select("id").eq("user_id", c.user_id).eq("commitment_id", c.id).eq("date", dayStr).maybeSingle();
        if (existingErr) {
          console.error("Error checking existing daily_usage:", existingErr);
          break;
        }
        if (!existing) {
          // Simple estimation rule: assume double usage → full limit exceeded
          const usedMinutes = c.limit_minutes * 2;
          const exceededMinutes = c.limit_minutes; // "extra" over the limit
          const penaltyCents = exceededMinutes * c.penalty_per_minute_cents;
          const { error: insertEstErr } = await supabase.from("daily_usage").insert({
            user_id: c.user_id,
            commitment_id: c.id,
            date: dayStr,
            used_minutes: usedMinutes,
            limit_minutes: c.limit_minutes,
            exceeded_minutes: exceededMinutes,
            penalty_cents: penaltyCents,
            is_estimated: true,
            reported_at: new Date().toISOString()
          });
          if (insertEstErr) {
            console.error("Error inserting estimated daily_usage:", insertEstErr);
            break;
          }
        }
        d.setUTCDate(d.getUTCDate() + 1);
      }
    }
    // 3) Recompute user_week_penalties for this week
    // FIXED: Use week_end_date (deadline) to identify commitments for this week
    const { data: commitmentsRes, error: commitmentsErr } = await supabase.from("commitments").select("id, user_id").eq("week_end_date", deadlineStr);
    if (commitmentsErr) {
      console.error("Error fetching commitments for week:", commitmentsErr);
      return new Response("Error fetching commitments", {
        status: 500
      });
    }
    // Get unique user IDs and commitment IDs for this week
    const uniqueUserIds = Array.from(new Set((commitmentsRes ?? []).map((r)=>r.user_id)));
    const commitmentIds = (commitmentsRes ?? []).map((r)=>r.id);
    const userTotals = {};
    // For each user, sum their penalty_cents for the week
    // FIXED: Filter daily_usage by commitment_ids for this week
    for (const userId of uniqueUserIds){
      const { data: userDaily, error: userDailyErr } = await supabase.from("daily_usage").select("penalty_cents, commitment_id").eq("user_id", userId).in("commitment_id", commitmentIds);
      if (userDailyErr) {
        console.error("Error fetching daily_usage for user:", userId, userDailyErr);
        continue;
      }
      // Now we're only summing penalties from commitments in this week
      const totalPenalty = (userDaily ?? []).reduce((sum, row)=>sum + (row.penalty_cents ?? 0), 0);
      userTotals[userId] = totalPenalty;
      // Note: user_week_penalties.week_start_date stores the deadline (legacy naming)
      const { error: upsertUwpErr } = await supabase.from("user_week_penalties").upsert({
        user_id: userId,
        week_start_date: deadlineStr, // Stores deadline (legacy naming)
        total_penalty_cents: totalPenalty,
        status: "pending",
        last_updated: new Date().toISOString()
      }, {
        onConflict: "user_id,week_start_date"
      });
      if (upsertUwpErr) {
        console.error("Error upserting user_week_penalties:", upsertUwpErr);
      }
    }
    // Compute pool total = sum of all user totals
    const poolTotal = Object.values(userTotals).reduce((sum, v)=>sum + (v ?? 0), 0);
    // Update weekly_pools total_penalty_cents
    // Note: weekly_pools.week_start_date stores the deadline (legacy naming)
    const { error: poolUpdateErr } = await supabase.from("weekly_pools").update({
      total_penalty_cents: poolTotal
    }).eq("week_start_date", deadlineStr); // Uses deadline as identifier
    if (poolUpdateErr) {
      console.error("Error updating weekly_pools total:", poolUpdateErr);
    }
    // 4) Charge users with a balance
    // Fetch all user_week_penalties for this week with pending > 0
    // Note: user_week_penalties.week_start_date stores the deadline (legacy naming)
    const { data: penalties, error: penaltiesErr } = await supabase.from("user_week_penalties").select("user_id, week_start_date, total_penalty_cents, status").eq("week_start_date", deadlineStr).eq("status", "pending");
    if (penaltiesErr) {
      console.error("Error fetching user_week_penalties:", penaltiesErr);
      return new Response("Error fetching penalties", {
        status: 500
      });
    }
    let chargedCount = 0;
    let succeededCount = 0;
    let requiresActionCount = 0;
    let failedCount = 0;
    const results = [];
    for (const p of penalties ?? []){
      if (!p.total_penalty_cents || p.total_penalty_cents <= 0) continue;
      // Fetch user to get stripe_customer_id and has_active_payment_method
      const { data: userRow, error: userRowErr } = await supabase.from("users").select("id, stripe_customer_id, has_active_payment_method").eq("id", p.user_id).single();
      if (userRowErr) {
        console.error("Error fetching user for penalty billing:", userRowErr);
        results.push({
          userId: p.user_id,
          success: false,
          error: `Failed to fetch user: ${userRowErr.message}`
        });
        continue;
      }
      // Skip test users with fake Stripe customer IDs
      if (userRow.stripe_customer_id && userRow.stripe_customer_id.startsWith("cus_test_")) {
        console.log("Skipping test user with fake Stripe customer ID:", p.user_id, userRow.stripe_customer_id);
        results.push({
          userId: p.user_id,
          success: false,
          error: "Test user with fake Stripe customer ID"
        });
        continue;
      }
      if (!userRow.stripe_customer_id || !userRow.has_active_payment_method) {
        console.log("Skipping user without Stripe customer or active PM:", p.user_id);
        results.push({
          userId: p.user_id,
          success: false,
          error: "No Stripe customer ID or active payment method"
        });
        continue;
      }
      try {
        // First, get the customer's default payment method
        const customer = await stripe.customers.retrieve(userRow.stripe_customer_id);
        const defaultPaymentMethodId = (customer as any).invoice_settings?.default_payment_method || 
                                      (customer as any).default_source;
        
        // Create PaymentIntent with confirm: true and off_session: true
        // If customer has a default payment method, use it; otherwise create unconfirmed
        const paymentIntentParams: any = {
          amount: p.total_penalty_cents,
          currency: CURRENCY,
          customer: userRow.stripe_customer_id,
          description: `PayAttentionClub week ending ${deadlineStr}`,
          metadata: {
            supabase_user_id: p.user_id,
            week_deadline: deadlineStr
          }
        };
        
        if (defaultPaymentMethodId) {
          // Customer has a payment method - can confirm immediately
          paymentIntentParams.payment_method = defaultPaymentMethodId;
          paymentIntentParams.confirm = true;
          paymentIntentParams.off_session = true;
        } else {
          // No payment method - create unconfirmed PaymentIntent
          // User will need to add payment method later
          paymentIntentParams.confirm = false;
        }
        
        const paymentIntent = await stripe.paymentIntents.create(paymentIntentParams);
        console.log(`Created PaymentIntent ${paymentIntent.id} for user ${p.user_id} with status: ${paymentIntent.status}`);
        // Determine payment status based on PaymentIntent status
        let paymentStatus;
        let penaltyStatus;
        if (paymentIntent.status === 'succeeded') {
          paymentStatus = 'succeeded';
          penaltyStatus = 'paid';
          succeededCount++;
        } else if (paymentIntent.status === 'requires_action') {
          // Payment requires 3D Secure or other authentication
          // User will need to complete this later (via webhook or manual flow)
          paymentStatus = 'requires_action';
          penaltyStatus = 'charge_initiated'; // Keep as initiated until user completes
          requiresActionCount++;
        } else if (paymentIntent.status === 'requires_payment_method' || paymentIntent.status === 'canceled') {
          // Payment requires payment method (customer doesn't have one set up) or was canceled
          paymentStatus = 'requires_payment_method';
          penaltyStatus = 'pending'; // Keep as pending until user adds payment method
          failedCount++;
        } else if (paymentIntent.status === 'processing') {
          // Payment is processing (e.g., for certain payment methods)
          paymentStatus = 'processing';
          penaltyStatus = 'charge_initiated'; // Will be updated by webhook
        } else {
          // Unknown status, default to charge_initiated
          paymentStatus = 'charge_initiated';
          penaltyStatus = 'charge_initiated';
        }
        // Insert into payments table with correct status
        // Note: payments.week_start_date stores the deadline (legacy naming)
        const { error: paymentInsertErr } = await supabase.from("payments").insert({
          user_id: p.user_id,
          week_start_date: deadlineStr, // Stores deadline (legacy naming)
          amount_cents: p.total_penalty_cents,
          currency: CURRENCY,
          stripe_payment_intent_id: paymentIntent.id,
          stripe_charge_id: paymentIntent.charges?.data[0]?.id || null,
          status: paymentStatus,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        });
        if (paymentInsertErr) {
          console.error("Error inserting into payments:", paymentInsertErr);
          results.push({
            userId: p.user_id,
            success: false,
            error: `Failed to insert payment: ${paymentInsertErr.message}`
          });
          continue;
        }
        // Update user_week_penalties status based on PaymentIntent status
        // Note: user_week_penalties.week_start_date stores the deadline (legacy naming)
        const { error: uwpUpdateErr } = await supabase.from("user_week_penalties").update({
          status: penaltyStatus,
          last_updated: new Date().toISOString()
        }).eq("user_id", p.user_id).eq("week_start_date", deadlineStr);
        if (uwpUpdateErr) {
          console.error("Error updating user_week_penalties status:", uwpUpdateErr);
          results.push({
            userId: p.user_id,
            success: false,
            error: `Failed to update penalty status: ${uwpUpdateErr.message}`
          });
          continue;
        }
        chargedCount++;
        results.push({
          userId: p.user_id,
          success: true,
          paymentIntentId: paymentIntent.id,
          status: paymentIntent.status,
          amountCents: p.total_penalty_cents
        });
      } catch (err) {
        console.error("Stripe PaymentIntent error for user", p.user_id, err);
        // Store error details
        const errorMessage = err.message || err.toString();
        // Try to insert failed payment record
        // Note: payments.week_start_date stores the deadline (legacy naming)
        try {
          await supabase.from("payments").insert({
            user_id: p.user_id,
            week_start_date: deadlineStr, // Stores deadline (legacy naming)
            amount_cents: p.total_penalty_cents,
            currency: CURRENCY,
            status: 'failed',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
          });
        } catch (insertErr) {
          console.error("Error inserting failed payment record:", insertErr);
        }
        // Update penalty status to failed
        // Note: user_week_penalties.week_start_date stores the deadline (legacy naming)
        try {
          await supabase.from("user_week_penalties").update({
            status: 'failed',
            last_updated: new Date().toISOString()
          }).eq("user_id", p.user_id).eq("week_start_date", deadlineStr);
        } catch (updateErr) {
          console.error("Error updating penalty status to failed:", updateErr);
        }
        failedCount++;
        results.push({
          userId: p.user_id,
          success: false,
          error: errorMessage
        });
      }
    }
    // 5) Close weekly pool
    // Note: weekly_pools.week_start_date stores the deadline (legacy naming)
    const { error: closePoolErr } = await supabase.from("weekly_pools").update({
      status: "closed",
      closed_at: new Date().toISOString()
    }).eq("week_start_date", deadlineStr); // Uses deadline as identifier
    if (closePoolErr) {
      console.error("Error closing weekly_pools:", closePoolErr);
    }
    return new Response(JSON.stringify({
      weekDeadline: deadlineStr,
      poolTotalCents: poolTotal,
      chargedUsers: chargedCount,
      succeededPayments: succeededCount,
      requiresActionPayments: requiresActionCount,
      failedPayments: failedCount,
      results: results
    }), {
      headers: {
        "Content-Type": "application/json"
      },
      status: 200
    });
  } catch (err) {
    console.error("weekly-close error:", err);
    return new Response(JSON.stringify({
      error: "Internal server error",
      details: err instanceof Error ? err.message : String(err)
    }), {
      status: 500
    });
  }
});
