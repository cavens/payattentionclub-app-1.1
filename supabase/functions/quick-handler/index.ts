import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";

// Note: Environment variables are read at runtime in the handler (matching bright-service pattern)
// This allows for environment-specific configuration (staging vs production)

const CURRENCY = "usd";
const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

type RequestPayload = {
  limit?: number;
  week?: string;
  userId?: string;
  dryRun?: boolean;
};

type UserWeekPenaltyRow = {
  user_id: string;
  week_start_date: string;
  settlement_status: string | null;
  charged_amount_cents: number | null;
  actual_amount_cents: number | null;
  refund_amount_cents: number | null;
  charge_payment_intent_id: string | null;
  refund_payment_intent_id: string | null;
  needs_reconciliation: boolean;
  reconciliation_delta_cents: number | null;
  reconciliation_reason: string | null;
  reconciliation_detected_at: string | null;
};

type UserRow = {
  id: string;
  email: string | null;
  stripe_customer_id: string | null;
  has_active_payment_method: boolean | null;
};

type CommitmentRow = {
  id: string;
  user_id: string;
  week_end_date: string;
  saved_payment_method_id: string | null;
  status: string | null;
};

type Candidate = {
  penalty: UserWeekPenaltyRow;
  user?: UserRow;
  commitment?: CommitmentRow;
};

type Failure = {
  userId: string;
  weekStartDate: string;
  reason: string;
};

type Summary = {
  dryRun: boolean;
  requestedLimit: number;
  totalCandidates: number;
  processed: number;
  refundsIssued: number;
  chargesIssued: number;
  skipped: {
    zeroDelta: number;
    missingStripeCustomer: number;
    missingPaymentMethod: number;
    missingPaymentIntent: number;
  };
  failures: Failure[];
  details: Array<{
    userId: string;
    weekStartDate: string;
    action: "refund" | "charge";
    amountCents: number;
    dryRun: boolean;
  }>;
};

function getLimit(requested?: number): number {
  if (!requested || Number.isNaN(requested)) {
    return DEFAULT_LIMIT;
  }
  return Math.min(Math.max(requested, 1), MAX_LIMIT);
}

function candidateKey(userId: string, weekStartDate: string): string {
  return `${userId}_${weekStartDate}`;
}

async function fetchCandidates(
  supabase: ReturnType<typeof createClient>,
  filters: { limit: number; week?: string; userId?: string }
): Promise<Candidate[]> {
  let query = supabase
    .from("user_week_penalties")
    .select(
      [
        "user_id",
        "week_start_date",
        "settlement_status",
        "charged_amount_cents",
        "actual_amount_cents",
        "refund_amount_cents",
        "charge_payment_intent_id",
        "refund_payment_intent_id",
        "needs_reconciliation",
        "reconciliation_delta_cents",
        "reconciliation_reason",
        "reconciliation_detected_at"
      ].join(",")
    )
    .eq("needs_reconciliation", true)
    .order("reconciliation_detected_at", { ascending: true })
    .limit(filters.limit);

  if (filters.week) {
    query = query.eq("week_start_date", filters.week);
  }
  if (filters.userId) {
    query = query.eq("user_id", filters.userId);
  }

  const { data: penalties, error } = await query;
  if (error) {
    throw new Error(`Failed to load reconciliation rows: ${error.message}`);
  }

  const rows = penalties ?? [];
  if (rows.length === 0) {
    return [];
  }

  const userIds = Array.from(new Set(rows.map((row) => row.user_id)));
  const weekDates = Array.from(
    new Set(rows.map((row) => row.week_start_date))
  );

  const [usersRes, commitmentsRes] = await Promise.all([
    userIds.length === 0
      ? Promise.resolve({ data: [] as UserRow[] })
      : supabase
          .from("users")
          .select("id,email,stripe_customer_id,has_active_payment_method")
          .in("id", userIds),
    userIds.length === 0 || weekDates.length === 0
      ? Promise.resolve({ data: [] as CommitmentRow[] })
      : supabase
          .from("commitments")
          .select("id,user_id,week_end_date,saved_payment_method_id,status")
          .in("user_id", userIds)
          .in("week_end_date", weekDates)
  ]);

  if (usersRes.error) {
    throw new Error(`Failed to load users: ${usersRes.error.message}`);
  }
  if (commitmentsRes.error) {
    throw new Error(
      `Failed to load commitments: ${commitmentsRes.error.message}`
    );
  }

  const userMap = new Map<string, UserRow>();
  for (const user of usersRes.data ?? []) {
    userMap.set(user.id, user);
  }

  const commitmentMap = new Map<string, CommitmentRow>();
  for (const commitment of commitmentsRes.data ?? []) {
    commitmentMap.set(
      candidateKey(commitment.user_id, commitment.week_end_date),
      commitment
    );
  }

  return rows.map((penalty) => ({
    penalty,
    user: userMap.get(penalty.user_id),
    commitment: commitmentMap.get(
      candidateKey(penalty.user_id, penalty.week_start_date)
    )
  }));
}

async function recordPayment(
  supabase: ReturnType<typeof createClient>,
  params: {
    userId: string;
    weekStartDate: string;
    amountCents: number;
    paymentType: "penalty_refund" | "penalty_adjustment";
    status: string;
    stripePaymentIntentId: string | null;
    stripeChargeId: string | null;
    relatedPaymentIntentId: string | null;
  }
) {
  const { data, error } = await supabase.from("payments").insert({
    user_id: params.userId,
    week_start_date: params.weekStartDate,
    amount_cents: params.amountCents,
    currency: CURRENCY,
    stripe_payment_intent_id: params.stripePaymentIntentId,
    stripe_charge_id: params.stripeChargeId,
    status: params.status,
    payment_type: params.paymentType,
    related_payment_intent_id: params.relatedPaymentIntentId
  }).select();

  if (error) {
    throw new Error(`Failed to record payment: ${error.message}`);
  }

  if (!data || data.length === 0) {
    throw new Error(`Payment record was not created (no data returned)`);
  }
}

async function resolveWithRefund(
  supabase: ReturnType<typeof createClient>,
  penalty: UserWeekPenaltyRow,
  amountCents: number,
  refundId: string | null,
  refundStatus: string
) {
  const newCharged =
    Math.max(0, (penalty.charged_amount_cents ?? 0) - amountCents) || 0;
  const newRefundTotal = (penalty.refund_amount_cents ?? 0) + amountCents;
  const finalStatus = newCharged === 0 ? "refunded" : "refunded_partial";

  // Update penalty record with error handling
  const { data: updatedPenalty, error: updateError } = await supabase
    .from("user_week_penalties")
    .update({
      charged_amount_cents: newCharged,
      refund_amount_cents: newRefundTotal,
      refund_payment_intent_id: refundId ?? penalty.refund_payment_intent_id,
      refund_issued_at: new Date().toISOString(),
      settlement_status: finalStatus,
      needs_reconciliation: false,
      reconciliation_delta_cents: 0,
      reconciliation_reason: null,
      last_updated: new Date().toISOString()
    })
    .eq("user_id", penalty.user_id)
    .eq("week_start_date", penalty.week_start_date)
    .select();

  if (updateError) {
    throw new Error(
      `Failed to update penalty record after refund: ${updateError.message} (user_id: ${penalty.user_id}, week_start_date: ${penalty.week_start_date})`
    );
  }

  if (!updatedPenalty || updatedPenalty.length === 0) {
    throw new Error(
      `No penalty record updated - check user_id and week_start_date match (user_id: ${penalty.user_id}, week_start_date: ${penalty.week_start_date})`
    );
  }

  console.log(
    `✅ Updated penalty record after refund: user_id=${penalty.user_id}, week_start_date=${penalty.week_start_date}, refund_amount_cents=${newRefundTotal}, settlement_status=${finalStatus}`
  );

  // Record payment with error handling
  await recordPayment(supabase, {
    userId: penalty.user_id,
    weekStartDate: penalty.week_start_date,
    amountCents,
    paymentType: "penalty_refund",
    status: refundStatus,
    stripePaymentIntentId: penalty.charge_payment_intent_id,
    stripeChargeId: refundId,
    relatedPaymentIntentId: penalty.charge_payment_intent_id
  });
}

async function resolveWithCharge(
  supabase: ReturnType<typeof createClient>,
  penalty: UserWeekPenaltyRow,
  amountCents: number,
  paymentIntentId: string | null,
  chargeId: string | null,
  paymentStatus: string
) {
  const newCharged = (penalty.charged_amount_cents ?? 0) + amountCents;
  const finalStatus =
    newCharged === (penalty.actual_amount_cents ?? newCharged)
      ? "charged_actual_adjusted"
      : "charged_actual";

  // Update penalty record with error handling
  const { data: updatedPenalty, error: updateError } = await supabase
    .from("user_week_penalties")
    .update({
      charged_amount_cents: newCharged,
      settlement_status: finalStatus,
      charge_payment_intent_id: paymentIntentId ?? penalty.charge_payment_intent_id,
      charged_at: new Date().toISOString(),
      needs_reconciliation: false,
      reconciliation_delta_cents: 0,
      reconciliation_reason: null,
      last_updated: new Date().toISOString()
    })
    .eq("user_id", penalty.user_id)
    .eq("week_start_date", penalty.week_start_date)
    .select();

  if (updateError) {
    throw new Error(
      `Failed to update penalty record after charge: ${updateError.message} (user_id: ${penalty.user_id}, week_start_date: ${penalty.week_start_date})`
    );
  }

  if (!updatedPenalty || updatedPenalty.length === 0) {
    throw new Error(
      `No penalty record updated - check user_id and week_start_date match (user_id: ${penalty.user_id}, week_start_date: ${penalty.week_start_date})`
    );
  }

  console.log(
    `✅ Updated penalty record after charge: user_id=${penalty.user_id}, week_start_date=${penalty.week_start_date}, charged_amount_cents=${newCharged}, settlement_status=${finalStatus}`
  );

  // Record payment with error handling
  await recordPayment(supabase, {
    userId: penalty.user_id,
    weekStartDate: penalty.week_start_date,
    amountCents,
    paymentType: "penalty_adjustment",
    status: paymentStatus,
    stripePaymentIntentId: paymentIntentId,
    stripeChargeId: chargeId,
    relatedPaymentIntentId: penalty.charge_payment_intent_id
  });
}

async function processCandidate(
  supabase: ReturnType<typeof createClient>,
  stripe: Stripe | null,
  candidate: Candidate,
  dryRun: boolean
): Promise<
  | { action: "refund" | "charge"; amountCents: number; skipped?: string }
  | undefined
> {
  if (!stripe) {
    throw new Error("Stripe is not configured.");
  }

  const delta = candidate.penalty.reconciliation_delta_cents ?? 0;
  if (delta === 0) {
    return { action: "refund", amountCents: 0, skipped: "zero_delta" };
  }

  if (delta < 0) {
    // Refund path
    if (!candidate.penalty.charge_payment_intent_id) {
      return {
        action: "refund",
        amountCents: Math.abs(delta),
        skipped: "missing_charge_payment_intent_id"
      };
    }

    const amountCents = Math.abs(delta);
    if (dryRun) {
      return { action: "refund", amountCents, skipped: undefined };
    }

    // Wrap Stripe refund in try-catch to prevent uncaught exceptions
    let refund;
    try {
      refund = await stripe.refunds.create({
        payment_intent: candidate.penalty.charge_payment_intent_id,
        amount: amountCents,
        metadata: {
          supabase_user_id: candidate.penalty.user_id,
          week_start_date: candidate.penalty.week_start_date,
          reconciliation: "late_sync"
        }
      });
    } catch (stripeError) {
      const errorMessage = stripeError instanceof Error ? stripeError.message : String(stripeError);
      console.error(`Stripe refund failed for user ${candidate.penalty.user_id}, week ${candidate.penalty.week_start_date}:`, errorMessage);
      throw new Error(`Stripe refund failed: ${errorMessage}`);
    }

    // Wrap database operations in try-catch
    try {
      await resolveWithRefund(
        supabase,
        candidate.penalty,
        amountCents,
        refund.id,
        refund.status
      );
    } catch (dbError) {
      const errorMessage = dbError instanceof Error ? dbError.message : String(dbError);
      console.error(`Database update failed after refund for user ${candidate.penalty.user_id}, week ${candidate.penalty.week_start_date}:`, errorMessage);
      // Note: Refund was already issued in Stripe, so we should still return success
      // The database update failure will be logged and can be retried
      throw new Error(`Database update failed after refund: ${errorMessage}`);
    }

    return { action: "refund", amountCents };
  }

  // Positive delta => additional charge
  if (!candidate.user?.stripe_customer_id) {
    return {
      action: "charge",
      amountCents: delta,
      skipped: "missing_stripe_customer"
    };
  }
  if (!candidate.commitment?.saved_payment_method_id) {
    return {
      action: "charge",
      amountCents: delta,
      skipped: "missing_payment_method"
    };
  }

  if (dryRun) {
    return { action: "charge", amountCents: delta };
  }

  // Wrap Stripe charge in try-catch to prevent uncaught exceptions
  let paymentIntent;
  try {
    paymentIntent = await stripe.paymentIntents.create({
      amount: delta,
      currency: CURRENCY,
      customer: candidate.user.stripe_customer_id,
      payment_method: candidate.commitment.saved_payment_method_id,
      confirm: true,
      off_session: true,
      description: `PAC reconciliation ${candidate.penalty.week_start_date}`,
      metadata: {
        supabase_user_id: candidate.penalty.user_id,
        week_start_date: candidate.penalty.week_start_date,
        reconciliation: "late_sync_delta"
      }
    });
  } catch (stripeError) {
    const errorMessage = stripeError instanceof Error ? stripeError.message : String(stripeError);
    console.error(`Stripe charge failed for user ${candidate.penalty.user_id}, week ${candidate.penalty.week_start_date}:`, errorMessage);
    throw new Error(`Stripe charge failed: ${errorMessage}`);
  }

  // Wrap database operations in try-catch
  try {
    await resolveWithCharge(
      supabase,
      candidate.penalty,
      delta,
      paymentIntent.id,
      paymentIntent.charges?.data?.[0]?.id ?? null,
      paymentIntent.status
    );
  } catch (dbError) {
    const errorMessage = dbError instanceof Error ? dbError.message : String(dbError);
    console.error(`Database update failed after charge for user ${candidate.penalty.user_id}, week ${candidate.penalty.week_start_date}:`, errorMessage);
    // Note: Charge was already issued in Stripe, so we should still return success
    // The database update failure will be logged and can be retried
    throw new Error(`Database update failed after charge: ${errorMessage}`);
  }

  return { action: "charge", amountCents: delta };
}

// Global error handler to catch unhandled promise rejections
// This prevents uncaught exceptions from crashing the function
if (typeof globalThis !== "undefined") {
  globalThis.addEventListener("unhandledrejection", (event) => {
    console.error("Unhandled promise rejection in quick-handler:", event.reason);
    // Prevent the default behavior (which would crash the function)
    event.preventDefault();
  });
}

Deno.serve(async (req) => {
  // Wrap entire handler in try-catch to catch any unexpected errors
  try {
    if (req.method !== "POST") {
      return new Response("Use POST", { status: 405 });
    }

    // Read environment variables at request time (matching bright-service pattern)
    // Match the pattern used in other working functions (bright-service, rapid-service)
    // Also check SUPABASE_SERVICE_ROLE_KEY as fallback (legacy name, same value as SUPABASE_SECRET_KEY)
    const SUPABASE_URL_RUNTIME = Deno.env.get("SUPABASE_URL");
    const SUPABASE_SECRET_KEY_RUNTIME = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");
    const RECONCILIATION_SECRET = Deno.env.get("RECONCILIATION_SECRET"); // Secret for public function access

    if (!SUPABASE_URL_RUNTIME || !SUPABASE_SECRET_KEY_RUNTIME) {
      console.error("quick-handler: Missing Supabase credentials at runtime");
      console.error(`  SUPABASE_URL: ${SUPABASE_URL_RUNTIME ? 'SET' : 'MISSING'}`);
      console.error(`  STAGING_SUPABASE_SECRET_KEY: ${Deno.env.get("STAGING_SUPABASE_SECRET_KEY") ? 'SET' : 'MISSING'}`);
      console.error(`  PRODUCTION_SUPABASE_SECRET_KEY: ${Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") ? 'SET' : 'MISSING'}`);
      console.error(`  SUPABASE_SERVICE_ROLE_KEY: ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ? 'SET' : 'MISSING'}`);
      return new Response(JSON.stringify({
        error: "Supabase credentials missing",
        details: "SUPABASE_URL and either STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY must be set in Edge Function secrets."
      }), { 
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    if (!STRIPE_SECRET_KEY) {
      return new Response(JSON.stringify({
        error: "Stripe credentials missing",
        details: "STRIPE_SECRET_KEY must be set in Edge Function secrets."
      }), { 
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Security: If function is public, require secret header (works in both testing and production)
    // This allows the function to be public for testing while maintaining security
    // Similar pattern to bright-service
    if (RECONCILIATION_SECRET) {
      const providedSecret = req.headers.get("x-reconciliation-secret");
      if (providedSecret !== RECONCILIATION_SECRET) {
        console.log("quick-handler: Unauthorized - invalid or missing reconciliation secret");
        return new Response(
          JSON.stringify({ error: "Unauthorized", message: "Invalid or missing reconciliation secret" }),
          { status: 401, headers: { "Content-Type": "application/json" } }
        );
      }
      console.log("quick-handler: Authorized via reconciliation secret");
    }

    // Initialize Stripe client at runtime with error handling
    let stripe: Stripe | null = null;
    try {
      if (STRIPE_SECRET_KEY) {
        stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2023-10-16" });
      }
    } catch (stripeInitError) {
      const errorMessage = stripeInitError instanceof Error ? stripeInitError.message : String(stripeInitError);
      console.error("quick-handler: Failed to initialize Stripe client:", errorMessage);
      return new Response(JSON.stringify({
        error: "Stripe initialization failed",
        details: errorMessage
      }), { 
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Initialize Supabase client with error handling
    let supabase;
    try {
      supabase = createClient(SUPABASE_URL_RUNTIME, SUPABASE_SECRET_KEY_RUNTIME);
    } catch (supabaseInitError) {
      const errorMessage = supabaseInitError instanceof Error ? supabaseInitError.message : String(supabaseInitError);
      console.error("quick-handler: Failed to initialize Supabase client:", errorMessage);
      return new Response(JSON.stringify({
        error: "Supabase initialization failed",
        details: errorMessage
      }), { 
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    let payload: RequestPayload | undefined;
    try {
      payload = await req.json();
    } catch (jsonError) {
      // JSON parsing errors are not fatal - continue with undefined payload
      console.log("quick-handler: Could not parse request body as JSON, continuing with undefined payload");
      payload = undefined;
    }

    const limit = getLimit(payload?.limit);
    const dryRun = Boolean(payload?.dryRun);

    console.log(
      "settlement-reconcile invoked",
      JSON.stringify({
        limit,
        dryRun,
        filters: {
          week: payload?.week ?? null,
          userId: payload?.userId ?? null
        }
      })
    );

    // Main processing logic wrapped in try-catch
    let summary: Summary;
    try {
      const candidates = await fetchCandidates(supabase, {
        limit,
        userId: payload?.userId,
        week: payload?.week
      });

      summary = {
        dryRun,
        requestedLimit: limit,
        totalCandidates: candidates.length,
        processed: 0,
        refundsIssued: 0,
        chargesIssued: 0,
        skipped: {
          zeroDelta: 0,
          missingStripeCustomer: 0,
          missingPaymentMethod: 0,
          missingPaymentIntent: 0
        },
        failures: [],
        details: []
      };

      // Process each candidate with individual error handling
      for (const candidate of candidates) {
        try {
          const result = await processCandidate(supabase, stripe, candidate, dryRun);
          if (!result) continue;

          if (result.skipped === "zero_delta") {
            summary.skipped.zeroDelta += 1;
            console.log(
              "settlement-reconcile skip zero-delta",
              candidate.penalty.user_id,
              candidate.penalty.week_start_date
            );
            continue;
          }
          if (result.skipped === "missing_stripe_customer") {
            summary.skipped.missingStripeCustomer += 1;
            console.warn(
              "settlement-reconcile skip missing customer",
              candidate.penalty.user_id,
              candidate.penalty.week_start_date
            );
            continue;
          }
          if (result.skipped === "missing_payment_method") {
            summary.skipped.missingPaymentMethod += 1;
            console.warn(
              "settlement-reconcile skip missing payment method",
              candidate.penalty.user_id,
              candidate.penalty.week_start_date
            );
            continue;
          }
          if (result.skipped === "missing_charge_payment_intent_id") {
            summary.skipped.missingPaymentIntent += 1;
            console.warn(
              "settlement-reconcile skip missing payment intent",
              candidate.penalty.user_id,
              candidate.penalty.week_start_date
            );
            continue;
          }

          summary.processed += 1;
          summary.details.push({
            userId: candidate.penalty.user_id,
            weekStartDate: candidate.penalty.week_start_date,
            action: result.action,
            amountCents: result.amountCents,
            dryRun
          });

          if (result.action === "refund") {
            summary.refundsIssued += 1;
          } else {
            summary.chargesIssued += 1;
          }

          console.log(
            "settlement-reconcile action",
            JSON.stringify({
              userId: candidate.penalty.user_id,
              weekStartDate: candidate.penalty.week_start_date,
              action: result.action,
              amountCents: result.amountCents,
              dryRun
            })
          );
        } catch (err) {
          const reason = err instanceof Error ? err.message : String(err);
          const errorStack = err instanceof Error ? err.stack : undefined;
          summary.failures.push({
            userId: candidate.penalty.user_id,
            weekStartDate: candidate.penalty.week_start_date,
            reason
          });
          console.error(
            "settlement-reconcile failure",
            candidate.penalty.user_id,
            candidate.penalty.week_start_date,
            reason,
            errorStack ? `\nStack: ${errorStack}` : ""
          );
        }
      }

      console.log("settlement-reconcile summary", JSON.stringify(summary));

      // Return response - ensure this happens before any cleanup
      return new Response(JSON.stringify(summary), {
        headers: { "Content-Type": "application/json" }
      });
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      const errorStack = err instanceof Error ? err.stack : undefined;
      console.error("settlement-reconcile error", errorMessage, errorStack ? `\nStack: ${errorStack}` : "");
      
      // Return error response
      return new Response(
        JSON.stringify({
          error: "Internal server error",
          message: errorMessage
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (outerError) {
    // Catch any unexpected errors in the outer handler
    const errorMessage = outerError instanceof Error ? outerError.message : String(outerError);
    const errorStack = outerError instanceof Error ? outerError.stack : undefined;
    console.error("quick-handler: Unexpected error in handler", errorMessage, errorStack ? `\nStack: ${errorStack}` : "");
    
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: errorMessage
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

