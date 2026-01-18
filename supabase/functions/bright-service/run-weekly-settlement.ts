import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";
import { TESTING_MODE as ENV_TESTING_MODE, getGraceDeadline } from "../_shared/timing.ts";

/* ---------- Inline helper utilities ---------- */

const TIME_ZONE = "America/New_York";

type WeekTarget = {
  weekEndDate: string;
  graceDeadlineIso: string;
};

type CommitmentRow = {
  id: string;
  user_id: string;
  week_end_date: string;
  week_grace_expires_at: string | null;
  saved_payment_method_id: string | null;
  max_charge_cents: number | null;
  status: string | null;
};

type UserRow = {
  id: string;
  email: string | null;
  stripe_customer_id: string | null;
  has_active_payment_method: boolean | null;
};

type UserWeekPenaltyRow = {
  user_id: string;
  week_start_date: string;
  total_penalty_cents: number | null;
  settlement_status: string | null;
  charged_amount_cents: number | null;
  actual_amount_cents: number | null;
  refund_amount_cents: number | null;
  charged_at: string | null;
  refund_issued_at: string | null;
  charge_payment_intent_id: string | null;
  refund_payment_intent_id: string | null;
};

type SettlementCandidate = {
  commitment: CommitmentRow;
  user: UserRow | undefined;
  penalty: UserWeekPenaltyRow | undefined;
  reportedDays: number;
};

function toDateInTimeZone(date: Date, timeZone: string): Date {
  return new Date(date.toLocaleString("en-US", { timeZone }));
}

function formatDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
    date.getDate()
  ).padStart(2, "0")}`;
}

function resolveWeekTarget(options?: { override?: string; now?: Date; isTestingMode?: boolean }): WeekTarget {
  const override = options?.override;
  const isTestingMode = options?.isTestingMode;
  
  if (override) {
    // If override is provided, parse it as Monday 12:00 ET
    const parsed = new Date(`${override}T12:00:00`);
    const mondayET = toDateInTimeZone(parsed, TIME_ZONE);
    mondayET.setHours(12, 0, 0, 0);
    // Use timing helper to get grace deadline (handles compressed vs normal mode)
    const graceDeadline = getGraceDeadline(mondayET, isTestingMode);
    return { weekEndDate: override, graceDeadlineIso: graceDeadline.toISOString() };
  }

  // In testing mode, use today's date in UTC as the week_end_date
  // This matches how commitments are created in testing mode (they use UTC date)
  if (isTestingMode) {
    const now = options?.now ?? new Date();
    // In testing mode, commitments use today's date in UTC as week_end_date
    // (because formatDeadlineDate uses toISOString() which is UTC-based)
    // So we need to use UTC date here too
    const todayUTC = new Date(now);
    const weekEndDate = formatDate(todayUTC); // formatDate uses UTC year/month/day
    // For grace deadline calculation, we need a Date object
    // Use today at 12:00 UTC as the reference point (matches commitment creation logic)
    todayUTC.setUTCHours(12, 0, 0, 0);
    const graceDeadline = getGraceDeadline(todayUTC, isTestingMode);
    return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
  }

  // Normal mode: Calculate previous Monday
  const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE);
  const monday = new Date(reference);
  const dayOfWeek = reference.getDay(); // 0=Sun ... 6=Sat
  const daysSinceMonday = (dayOfWeek + 6) % 7;
  monday.setDate(monday.getDate() - daysSinceMonday);
  monday.setHours(12, 0, 0, 0);

  const weekEndDate = formatDate(monday);
  // Use timing helper to get grace deadline (handles compressed vs normal mode)
  const graceDeadline = getGraceDeadline(monday, isTestingMode);

  return { weekEndDate, graceDeadlineIso: graceDeadline.toISOString() };
}

async function fetchCommitmentsForWeek(
  supabase: ReturnType<typeof createClient>,
  weekEndDate: string
): Promise<CommitmentRow[]> {
  const { data, error } = await supabase
    .from("commitments")
    .select(
      [
        "id",
        "user_id",
        "week_end_date",
        "week_grace_expires_at",
        "saved_payment_method_id",
        "max_charge_cents",
        "status"
      ].join(",")
    )
    .eq("week_end_date", weekEndDate);

  if (error) throw new Error(`Failed to fetch commitments for ${weekEndDate}: ${error.message}`);
  return data ?? [];
}

async function fetchUserWeekPenalties(
  supabase: ReturnType<typeof createClient>,
  weekEndDate: string,
  userIds: string[]
): Promise<UserWeekPenaltyRow[]> {
  if (userIds.length === 0) return [];
  const { data, error } = await supabase
    .from("user_week_penalties")
    .select(
      [
        "user_id",
        "week_start_date",
        "total_penalty_cents",
        "settlement_status",
        "charged_amount_cents",
        "actual_amount_cents",
        "refund_amount_cents",
        "charged_at",
        "refund_issued_at",
        "charge_payment_intent_id",
        "refund_payment_intent_id"
      ].join(",")
    )
    .eq("week_start_date", weekEndDate)
    .in("user_id", userIds);

  if (error) throw new Error(`Failed to fetch user_week_penalties: ${error.message}`);
  return data ?? [];
}

async function fetchUsers(
  supabase: ReturnType<typeof createClient>,
  userIds: string[]
): Promise<UserRow[]> {
  if (userIds.length === 0) return [];
  const { data, error } = await supabase
    .from("users")
    .select("id,email,stripe_customer_id,has_active_payment_method")
    .in("id", userIds);

  if (error) throw new Error(`Failed to fetch users: ${error.message}`);
  return data ?? [];
}

async function fetchUsageCounts(
  supabase: ReturnType<typeof createClient>,
  commitmentIds: string[]
): Promise<Map<string, number>> {
  if (commitmentIds.length === 0) return new Map();
  const { data, error } = await supabase
    .from("daily_usage")
    .select("commitment_id")
    .in("commitment_id", commitmentIds);

  if (error) throw new Error(`Failed to fetch daily_usage rows: ${error.message}`);

  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    if (!row?.commitment_id) continue;
    counts.set(row.commitment_id, (counts.get(row.commitment_id) ?? 0) + 1);
  }
  return counts;
}

async function buildSettlementCandidates(
  supabase: ReturnType<typeof createClient>,
  weekEndDate: string
): Promise<SettlementCandidate[]> {
  const commitments = await fetchCommitmentsForWeek(supabase, weekEndDate);
  if (commitments.length === 0) return [];

  const userIds = Array.from(new Set(commitments.map((c) => c.user_id)));
  const commitmentIds = commitments.map((c) => c.id);

  const [penalties, users, usageCounts] = await Promise.all([
    fetchUserWeekPenalties(supabase, weekEndDate, userIds),
    fetchUsers(supabase, userIds),
    fetchUsageCounts(supabase, commitmentIds)
  ]);

  const penaltyMap = new Map<string, UserWeekPenaltyRow>();
  for (const penalty of penalties) penaltyMap.set(penalty.user_id, penalty);

  const userMap = new Map<string, UserRow>();
  for (const user of users) userMap.set(user.id, user);

  return commitments.map((commitment) => ({
    commitment,
    user: userMap.get(commitment.user_id),
    penalty: penaltyMap.get(commitment.user_id),
    reportedDays: usageCounts.get(commitment.id) ?? 0
  }));
}

function hasSyncedUsage(candidate: SettlementCandidate): boolean {
  return candidate.reportedDays > 0;
}

function isGracePeriodExpired(candidate: SettlementCandidate, reference: Date = new Date(), isTestingMode?: boolean): boolean {
  // If explicit grace deadline is set, use it
  const explicit = candidate.commitment.week_grace_expires_at;
  if (explicit) {
    return new Date(explicit).getTime() <= reference.getTime();
  }

  // Otherwise, derive grace deadline from week_end_date using timing helper
  // week_end_date is Monday (e.g., "2025-01-13"), need to convert to Date object
  const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
  const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
  mondayET.setHours(12, 0, 0, 0);
  
  // Use timing helper to get grace deadline (handles compressed vs normal mode)
  // Pass isTestingMode parameter to ensure correct calculation
  const graceDeadline = getGraceDeadline(mondayET, isTestingMode);
  
  return graceDeadline.getTime() <= reference.getTime();
}

function getWorstCaseAmountCents(candidate: SettlementCandidate): number {
  return candidate.commitment.max_charge_cents ?? 0;
}

function getActualPenaltyCents(candidate: SettlementCandidate): number {
  return candidate.penalty?.total_penalty_cents ?? 0;
}

/* ---------- Main settlement logic ---------- */

// Environment variables are read at runtime in the handler
// Don't read them at module level to avoid issues with Edge Function runtime

// Stripe client is created at runtime in the handler
const CURRENCY = "usd";
const SETTLED_STATUSES = new Set(["charged_actual", "charged_worst_case", "refunded", "refunded_partial"]);

type RequestPayload = { targetWeek?: string };
type ChargeType = "actual" | "worst_case";

type Summary = {
  weekEndDate: string;
  totalCommitments: number;
  candidatesWithUsage: number;
  candidatesWithoutUsage: number;
  graceNotExpired: number;
  alreadySettled: number;
  missingPaymentMethod: number;
  missingStripeCustomer: number;
  zeroAmount: number;
  chargedActual: number;
  chargedWorstCase: number;
  chargeFailures: Array<{ userId: string; message: string }>;
};

function shouldSkipBecauseSettled(candidate: SettlementCandidate): boolean {
  const status = candidate.penalty?.settlement_status;
  return status ? SETTLED_STATUSES.has(status) : false;
}

function getChargeAmount(candidate: SettlementCandidate, type: ChargeType): number {
  if (type === "actual") {
    const actual = getActualPenaltyCents(candidate);
    const maxCharge = getWorstCaseAmountCents(candidate); // This is max_charge_cents (authorization amount)
    return Math.min(actual, maxCharge); // Cap actual at authorization amount - never charge more than authorized
  }
  return getWorstCaseAmountCents(candidate);
}

async function recordPayment(
  supabase: ReturnType<typeof createClient>,
  params: {
    userId: string;
    weekEndDate: string;
    amountCents: number;
    paymentIntentId: string;
    paymentStatus: string;
    chargeType: ChargeType;
    stripeChargeId?: string | null;
  }
) {
  await supabase.from("payments").insert({
    user_id: params.userId,
    week_start_date: params.weekEndDate,
    amount_cents: params.amountCents,
    currency: CURRENCY,
    stripe_payment_intent_id: params.paymentIntentId,
    stripe_charge_id: params.stripeChargeId ?? null,
    status: params.paymentStatus,
    payment_type: params.chargeType === "actual" ? "penalty_actual" : "penalty_worst_case",
    related_payment_intent_id: null
  });
}

async function updateUserWeekPenalty(
  supabase: ReturnType<typeof createClient>,
  params: {
    userId: string;
    weekEndDate: string;
    amountCents: number;
    actualAmountCents: number;
    paymentIntentId: string;
    chargeType: ChargeType;
    status: "succeeded" | "requires_action" | "processing" | "failed";
  }
) {
  const settlementStatus =
    params.chargeType === "actual" ? "charged_actual" : "charged_worst_case";

  const updates: Record<string, unknown> = {
    settlement_status: params.status === "failed" ? "charge_failed" : settlementStatus,
    charged_amount_cents: params.amountCents,
    actual_amount_cents: params.actualAmountCents,
    charge_payment_intent_id: params.paymentIntentId,
    charged_at: params.status === "failed" ? null : new Date().toISOString(),
    last_updated: new Date().toISOString()
  };

  if (params.status === "failed") updates["charged_amount_cents"] = 0;

  await supabase
    .from("user_week_penalties")
    .update(updates)
    .eq("user_id", params.userId)
    .eq("week_start_date", params.weekEndDate);
}

async function chargeCandidate(
  candidate: SettlementCandidate,
  supabase: ReturnType<typeof createClient>,
  weekEndDate: string,
  chargeType: ChargeType,
  amountCents: number,
  stripe: Stripe | null
) {
  if (!stripe) throw new Error("Stripe client is not configured.");
  if (!candidate.user?.stripe_customer_id) throw new Error("User missing stripe_customer_id.");

  const paymentMethodId = candidate.commitment.saved_payment_method_id;
  if (!paymentMethodId) throw new Error("Commitment missing saved_payment_method_id.");

  const paymentIntent = await stripe.paymentIntents.create({
    amount: amountCents,
    currency: CURRENCY,
    customer: candidate.user.stripe_customer_id,
    payment_method: paymentMethodId,
    confirm: true,
    off_session: true,
    description: `PAC week ending ${weekEndDate} (${chargeType})`,
    metadata: {
      supabase_user_id: candidate.commitment.user_id,
      commitment_id: candidate.commitment.id,
      week_end_date: weekEndDate,
      charge_type: chargeType
    }
  });

  await recordPayment(supabase, {
    userId: candidate.commitment.user_id,
    weekEndDate,
    amountCents,
    paymentIntentId: paymentIntent.id,
    paymentStatus: paymentIntent.status,
    chargeType,
    stripeChargeId: paymentIntent.charges?.data?.[0]?.id ?? null
  });

  const mappedStatus =
    paymentIntent.status === "requires_action" ||
    paymentIntent.status === "processing" ||
    paymentIntent.status === "requires_payment_method"
      ? (paymentIntent.status as "requires_action" | "processing" | "failed")
      : paymentIntent.status === "succeeded"
        ? "succeeded"
        : "failed";

  await updateUserWeekPenalty(supabase, {
    userId: candidate.commitment.user_id,
    weekEndDate,
    amountCents,
    actualAmountCents: chargeType === "actual" ? amountCents : getActualPenaltyCents(candidate),
    paymentIntentId: paymentIntent.id,
    chargeType,
    status: mappedStatus
  });

  return paymentIntent;
}

/* ---------- Handler ---------- */

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  
  // Read environment variables at request time
  // Match the pattern used in other working functions (super-service, rapid-service)
  // Also check SUPABASE_SERVICE_ROLE_KEY as fallback (legacy name, same value as SUPABASE_SECRET_KEY)
  const SUPABASE_URL_RUNTIME = Deno.env.get("SUPABASE_URL");
  const SUPABASE_SECRET_KEY_RUNTIME = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const STRIPE_SECRET_KEY_TEST = Deno.env.get("STRIPE_SECRET_KEY_TEST");
  const STRIPE_SECRET_KEY_PROD = Deno.env.get("STRIPE_SECRET_KEY");
  const STRIPE_SECRET_KEY = STRIPE_SECRET_KEY_TEST || STRIPE_SECRET_KEY_PROD;
  
  if (!SUPABASE_URL_RUNTIME || !SUPABASE_SECRET_KEY_RUNTIME) {
    console.error("run-weekly-settlement: Missing Supabase credentials at runtime");
    console.error(`  SUPABASE_URL: ${SUPABASE_URL_RUNTIME ? 'SET' : 'MISSING'}`);
    console.error(`  STAGING_SUPABASE_SECRET_KEY: ${Deno.env.get("STAGING_SUPABASE_SECRET_KEY") ? 'SET' : 'MISSING'}`);
    console.error(`  PRODUCTION_SUPABASE_SECRET_KEY: ${Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") ? 'SET' : 'MISSING'}`);
    return new Response(JSON.stringify({
      error: "Supabase credentials missing",
      details: "SUPABASE_URL and either STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY must be set in Edge Function secrets."
    }), { 
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
  
  // Initialize Stripe client at runtime
  const stripe = STRIPE_SECRET_KEY ? new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2023-10-16" }) : null;

  // Check testing mode from both environment variable AND database config
  // Database config (app_config) is the primary source of truth
  let isTestingMode = ENV_TESTING_MODE; // Start with environment variable value

  // Create a Supabase client with service role key for app_config access
  const supabaseAdmin = createClient(SUPABASE_URL_RUNTIME, SUPABASE_SECRET_KEY_RUNTIME);

  if (!isTestingMode) {
    // Check database app_config table for testing mode
    try {
      const { data: config, error: configError } = await supabaseAdmin
        .from('app_config')
        .select('value')
        .eq('key', 'testing_mode')
        .single();

      if (!configError && config && config.value === 'true') {
        isTestingMode = true;
        console.log('run-weekly-settlement: Testing mode enabled via app_config table');
      }
    } catch (error) {
      console.log('run-weekly-settlement: Could not check app_config, using environment variable only');
    }
  }

  // In testing mode, make function public (no auth required) but require manual trigger header
  // This allows automated testing scripts to call the function without authentication
  if (isTestingMode) {
    const isManualTrigger = req.headers.get("x-manual-trigger") === "true";
    if (!isManualTrigger) {
      console.log("run-weekly-settlement: Skipped - testing mode active (use x-manual-trigger header)");
      return new Response(
        JSON.stringify({ message: "Settlement skipped - testing mode active. Use x-manual-trigger: true header to run." }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
    // In testing mode, skip authentication check - function is public
    console.log("run-weekly-settlement: Testing mode - public access allowed with x-manual-trigger header");
  } else {
    // In production mode, authentication is still required by Edge Function gateway
    // (This code path won't execute if gateway requires auth, but kept for clarity)
  }

  const supabase = createClient(SUPABASE_URL_RUNTIME, SUPABASE_SECRET_KEY_RUNTIME);

  let payload: RequestPayload | undefined;
  try {
    payload = await req.json();
  } catch (_err) {
    payload = undefined;
  }

  const target = resolveWeekTarget({ override: payload?.targetWeek, isTestingMode });
  console.log("run-weekly-settlement: target week", target.weekEndDate, `(testing mode: ${isTestingMode})`);

  try {
    const candidates = await buildSettlementCandidates(supabase, target.weekEndDate);

    const summary: Summary = {
      weekEndDate: target.weekEndDate,
      totalCommitments: candidates.length,
      candidatesWithUsage: 0,
      candidatesWithoutUsage: 0,
      graceNotExpired: 0,
      alreadySettled: 0,
      missingPaymentMethod: 0,
      missingStripeCustomer: 0,
      zeroAmount: 0,
      chargedActual: 0,
      chargedWorstCase: 0,
      chargeFailures: []
    };

    for (const candidate of candidates) {
      const hasUsage = hasSyncedUsage(candidate);
      if (hasUsage) summary.candidatesWithUsage += 1;
      else summary.candidatesWithoutUsage += 1;

      if (shouldSkipBecauseSettled(candidate)) {
        summary.alreadySettled += 1;
        continue;
      }
      // CRITICAL: Always wait for grace period to expire before settling
      // This gives users time to sync their data, regardless of whether usage exists
      // Pass isTestingMode to ensure correct grace period calculation
      if (!isGracePeriodExpired(candidate, new Date(), isTestingMode)) {
        summary.graceNotExpired += 1;
        continue;  // Skip settlement - wait for grace period to expire
      }

      const chargeType: ChargeType = hasUsage ? "actual" : "worst_case";
      const amountCents = getChargeAmount(candidate, chargeType);

      if (!candidate.user?.stripe_customer_id) {
        summary.missingStripeCustomer += 1;
        summary.chargeFailures.push({ userId: candidate.commitment.user_id, message: "Missing stripe_customer_id" });
        continue;
      }
      if (!candidate.commitment.saved_payment_method_id) {
        summary.missingPaymentMethod += 1;
        summary.chargeFailures.push({ userId: candidate.commitment.user_id, message: "Missing saved payment method" });
        continue;
      }
      if (amountCents <= 0) {
        summary.zeroAmount += 1;
        continue;
      }

      try {
        const paymentIntent = await chargeCandidate(
          candidate,
          supabase,
          target.weekEndDate,
          chargeType,
          amountCents,
          stripe
        );
        if (chargeType === "actual") summary.chargedActual += 1;
        else summary.chargedWorstCase += 1;

        console.log(
          `run-weekly-settlement: charged ${candidate.commitment.user_id} (${chargeType}) intent=${paymentIntent.id}`
        );
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error("run-weekly-settlement: charge failed", candidate.commitment.user_id, message);
        summary.chargeFailures.push({ userId: candidate.commitment.user_id, message });

        await updateUserWeekPenalty(supabase, {
          userId: candidate.commitment.user_id,
          weekEndDate: target.weekEndDate,
          amountCents: 0,
          actualAmountCents: getActualPenaltyCents(candidate),
          paymentIntentId: "failed",
          chargeType,
          status: "failed"
        });
      }
    }

    return new Response(JSON.stringify(summary), {
      headers: { "Content-Type": "application/json" }
    });
  } catch (err) {
    console.error("run-weekly-settlement error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: err instanceof Error ? err.message : String(err)
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});