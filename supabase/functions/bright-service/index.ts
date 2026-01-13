import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";
import { TESTING_MODE, getGraceDeadline, getNextDeadline } from "../_shared/timing.ts";

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
  created_at: string | null;
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
  last_updated: string | null;
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

function resolveWeekTarget(options?: { override?: string; now?: Date }): WeekTarget {
  const override = options?.override;
  if (override) {
    // If override is provided, parse it as Monday 12:00 ET
    const parsed = new Date(`${override}T12:00:00`);
    const mondayET = toDateInTimeZone(parsed, TIME_ZONE);
    mondayET.setHours(12, 0, 0, 0);
    // Use timing helper to get grace deadline (handles compressed vs normal mode)
    const graceDeadline = getGraceDeadline(mondayET);
    return { weekEndDate: override, graceDeadlineIso: graceDeadline.toISOString() };
  }

  // In testing mode, use today's date in UTC as the week_end_date
  // This matches how commitments are created in testing mode (they use UTC date)
  if (TESTING_MODE) {
    const now = options?.now ?? new Date();
    // In testing mode, commitments use today's date in UTC as week_end_date
    // (because formatDeadlineDate uses toISOString() which is UTC-based)
    // So we need to use UTC date here too
    const todayUTC = new Date(now);
    const weekEndDate = formatDate(todayUTC); // formatDate uses UTC year/month/day
    // For grace deadline calculation, we need a Date object
    // Use today at 12:00 UTC as the reference point (matches commitment creation logic)
    todayUTC.setUTCHours(12, 0, 0, 0);
    const graceDeadline = getGraceDeadline(todayUTC);
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
  const graceDeadline = getGraceDeadline(monday);

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
        "status",
        "created_at"
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
        "refund_payment_intent_id",
        "last_updated"
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

function getCommitmentDeadline(candidate: SettlementCandidate): Date {
  // In testing mode, calculate deadline from created_at
  if (TESTING_MODE && candidate.commitment.created_at) {
    const createdAt = new Date(candidate.commitment.created_at);
    return new Date(createdAt.getTime() + (3 * 60 * 1000)); // 3 minutes after creation
  }
  
  // Normal mode: deadline is Monday 12:00 ET (week_end_date)
  const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
  const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
  mondayET.setHours(12, 0, 0, 0);
  return mondayET;
}

function hasSyncedUsage(candidate: SettlementCandidate): boolean {
  // Check if usage was synced after the deadline
  // This ensures we only count usage synced AFTER the deadline, not before
  // Note: actual_amount_cents can be 0 (no penalty), but we still want to charge actual if synced
  const penalty = candidate.penalty;
  if (!penalty) {
    return false; // No penalty record means no usage synced
  }
  
  // Calculate the deadline for this commitment
  const deadline = getCommitmentDeadline(candidate);
  
  // If last_updated is available, check if it's after the deadline
  if (penalty.last_updated) {
    const lastUpdated = new Date(penalty.last_updated);
    return lastUpdated.getTime() > deadline.getTime();
  }
  
  // If last_updated is not available, check if actual_amount_cents is set (even if 0)
  // This handles cases where usage was synced but resulted in 0 penalty
  // For backward compatibility: if actual_amount_cents exists (even as 0), assume synced
  // This is conservative - it may charge actual when it should charge worst case
  if (penalty.actual_amount_cents !== null && penalty.actual_amount_cents !== undefined) {
    return true; // actual_amount_cents is set (even if 0), so usage was synced
  }
  
  return false; // No indication that usage was synced
}

function isGracePeriodExpired(candidate: SettlementCandidate, reference: Date = new Date()): boolean {
  // If explicit grace deadline is set, use it
  const explicit = candidate.commitment.week_grace_expires_at;
  if (explicit) {
    const expired = new Date(explicit).getTime() <= reference.getTime();
    console.log(`isGracePeriodExpired: Using explicit grace deadline ${explicit}, expired: ${expired}`);
    return expired;
  }

  // In testing mode, calculate grace period from created_at timestamp
  // Deadline is 3 minutes after creation, grace expires 1 minute after deadline (4 minutes total)
  if (TESTING_MODE && candidate.commitment.created_at) {
    const createdAt = new Date(candidate.commitment.created_at);
    const deadline = new Date(createdAt.getTime() + (3 * 60 * 1000)); // 3 minutes
    const graceDeadline = new Date(deadline.getTime() + (1 * 60 * 1000)); // 1 minute after deadline
    const expired = graceDeadline.getTime() <= reference.getTime();
    const timeUntilGrace = graceDeadline.getTime() - reference.getTime();
    console.log(`isGracePeriodExpired (testing mode): created_at=${createdAt.toISOString()}, deadline=${deadline.toISOString()}, graceDeadline=${graceDeadline.toISOString()}, now=${reference.toISOString()}, expired=${expired}, timeUntilGrace=${timeUntilGrace}ms (${Math.round(timeUntilGrace / 1000)}s)`);
    return expired;
  }

  // Normal mode: derive grace deadline from week_end_date using timing helper
  // week_end_date is Monday (e.g., "2025-01-13"), need to convert to Date object
  const mondayDate = new Date(`${candidate.commitment.week_end_date}T12:00:00`);
  const mondayET = toDateInTimeZone(mondayDate, TIME_ZONE);
  mondayET.setHours(12, 0, 0, 0);
  
  // Use timing helper to get grace deadline (handles compressed vs normal mode)
  const graceDeadline = getGraceDeadline(mondayET);
  const expired = graceDeadline.getTime() <= reference.getTime();
  console.log(`isGracePeriodExpired (normal mode): week_end_date=${candidate.commitment.week_end_date}, graceDeadline=${graceDeadline.toISOString()}, now=${reference.toISOString()}, expired=${expired}`);
  
  return expired;
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

  // Use upsert to create record if it doesn't exist, or update if it does
  await supabase
    .from("user_week_penalties")
    .upsert({
      user_id: params.userId,
      week_start_date: params.weekEndDate,
      ...updates
    }, {
      onConflict: "user_id,week_start_date"
    });
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
    console.error(`  SUPABASE_SERVICE_ROLE_KEY: ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ? 'SET' : 'MISSING'}`);
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

  // In testing mode, make function public (no auth required) but require manual trigger header
  // This allows automated testing scripts to call the function without authentication
  if (TESTING_MODE) {
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

  const target = resolveWeekTarget({ override: payload?.targetWeek });
  console.log("run-weekly-settlement: target week", target.weekEndDate);

  try {
    // Step 1: Insert estimated rows for commitments with revoked monitoring
    // This handles cases where users revoked monitoring mid-week - we estimate their usage
    // FIXED: Use week_end_date (deadline) to identify commitments for this week
    // week_end_date stores the deadline (next Monday), which groups commitments by week
    console.log("run-weekly-settlement: Checking for revoked monitoring commitments...");
    const { data: revokedCommitments, error: revokedError } = await supabase
      .from("commitments")
      .select("id, user_id, week_start_date, week_end_date, limit_minutes, penalty_per_minute_cents, monitoring_status, monitoring_revoked_at")
      .eq("week_end_date", target.weekEndDate)
      .eq("monitoring_status", "revoked");
    
    if (revokedError) {
      console.error("Error fetching revoked commitments:", revokedError);
      return new Response(
        JSON.stringify({ error: "Error fetching revoked commitments", details: revokedError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    if (revokedCommitments && revokedCommitments.length > 0) {
      console.log(`run-weekly-settlement: Found ${revokedCommitments.length} revoked commitment(s) for estimation`);
      
      for (const c of revokedCommitments) {
        if (!c.monitoring_revoked_at) continue;
        const revDate = new Date(c.monitoring_revoked_at);
        // Start from the date of revocation (date-only)
        let d = new Date(formatDate(revDate));
        const commitmentEnd = new Date(c.week_end_date || target.weekEndDate);
        
        while (d < commitmentEnd) {
          const dayStr = formatDate(d);
          // Check if there's already a daily_usage row for this day
          const { data: existing, error: existingErr } = await supabase
            .from("daily_usage")
            .select("id")
            .eq("user_id", c.user_id)
            .eq("commitment_id", c.id)
            .eq("date", dayStr)
            .maybeSingle();
          
          if (existingErr) {
            console.error("Error checking existing daily_usage:", existingErr);
            break;
          }
          
          if (!existing) {
            // Simple estimation rule: assume double usage → full limit exceeded
            const usedMinutes = c.limit_minutes * 2;
            const exceededMinutes = c.limit_minutes; // "extra" over the limit
            const penaltyCents = exceededMinutes * c.penalty_per_minute_cents;
            
            const { error: insertEstErr } = await supabase
              .from("daily_usage")
              .insert({
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
      
      console.log(`run-weekly-settlement: Completed revoked monitoring estimation for ${revokedCommitments.length} commitment(s)`);
    } else {
      console.log("run-weekly-settlement: No revoked commitments found for this week");
    }

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
      if (!isGracePeriodExpired(candidate)) {
        summary.graceNotExpired += 1;
        continue;  // Skip settlement - wait for grace period to expire
      }

      // Grace period has expired - now check usage and charge accordingly
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
        // Zero amount - mark as settled with 0 charged
        console.log(`run-weekly-settlement: Amount is 0 cents. Marking as settled with 0 charged.`);
        
        const settlementStatus = chargeType === "actual" ? "charged_actual" : "charged_worst_case";
        await updateUserWeekPenalty(supabase, {
          userId: candidate.commitment.user_id,
          weekEndDate: target.weekEndDate,
          amountCents: 0, // No charge for zero amount
          actualAmountCents: chargeType === "actual" ? amountCents : getActualPenaltyCents(candidate),
          paymentIntentId: "zero_amount",
          chargeType,
          status: "succeeded" // Mark as succeeded since we're intentionally not charging
        });

        // Record a payment entry noting the amount was zero
        await recordPayment(supabase, {
          userId: candidate.commitment.user_id,
          weekEndDate: target.weekEndDate,
          amountCents: 0,
          paymentIntentId: "zero_amount",
          paymentStatus: "succeeded",
          chargeType,
          stripeChargeId: null
        });

        if (chargeType === "actual") {
          summary.chargedActual += 1;
        } else {
          summary.chargedWorstCase += 1;
        }
        continue;
      }

      // Stripe minimum charge is 50 cents (or equivalent in other currencies)
      // Note: If Stripe account uses EUR, USD amounts are converted
      // At current rates, €0.50 ≈ $0.55 USD, so we use 60 cents USD as a safe minimum
      // to account for currency conversion and exchange rate fluctuations
      const STRIPE_MINIMUM_CENTS = 60; // Increased from 50 to account for EUR conversion
      if (amountCents < STRIPE_MINIMUM_CENTS) {
        // Amount is too small to charge via Stripe
        // Mark as settled with 0 charged, but record the actual amount for reference
        console.log(`run-weekly-settlement: Amount ${amountCents} cents is below Stripe minimum ${STRIPE_MINIMUM_CENTS} cents. Marking as settled with 0 charged.`);
        
        const settlementStatus = chargeType === "actual" ? "charged_actual" : "charged_worst_case";
        await updateUserWeekPenalty(supabase, {
          userId: candidate.commitment.user_id,
          weekEndDate: target.weekEndDate,
          amountCents: 0, // No charge due to minimum
          actualAmountCents: chargeType === "actual" ? amountCents : getActualPenaltyCents(candidate),
          paymentIntentId: "below_minimum",
          chargeType,
          status: "succeeded" // Mark as succeeded since we're intentionally not charging
        });

        // Record a payment entry noting the amount was too small
        await recordPayment(supabase, {
          userId: candidate.commitment.user_id,
          weekEndDate: target.weekEndDate,
          amountCents: 0,
          paymentIntentId: "below_minimum",
          paymentStatus: "succeeded",
          chargeType,
          stripeChargeId: null
        });

        if (chargeType === "actual") {
          summary.chargedActual += 1;
        } else {
          summary.chargedWorstCase += 1;
        }
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
        
        // Check if this is a "below minimum" error (currency conversion issue)
        const isBelowMinimum = message.includes("Amount must convert to at least") || 
                               message.includes("below minimum") ||
                               message.includes("minimum charge");
        
        if (isBelowMinimum) {
          // Handle as "below minimum" - mark as settled with 0 charged
          console.log(`run-weekly-settlement: Amount ${amountCents} cents is below Stripe minimum after currency conversion. Marking as settled with 0 charged.`);
          
          const settlementStatus = chargeType === "actual" ? "charged_actual" : "charged_worst_case";
          await updateUserWeekPenalty(supabase, {
            userId: candidate.commitment.user_id,
            weekEndDate: target.weekEndDate,
            amountCents: 0, // No charge due to minimum
            actualAmountCents: chargeType === "actual" ? amountCents : getActualPenaltyCents(candidate),
            paymentIntentId: "below_minimum",
            chargeType,
            status: "succeeded" // Mark as succeeded since we're intentionally not charging
          });

          // Record a payment entry noting the amount was too small
          await recordPayment(supabase, {
            userId: candidate.commitment.user_id,
            weekEndDate: target.weekEndDate,
            amountCents: 0,
            paymentIntentId: "below_minimum",
            paymentStatus: "succeeded",
            chargeType,
            stripeChargeId: null
          });

          if (chargeType === "actual") {
            summary.chargedActual += 1;
          } else {
            summary.chargedWorstCase += 1;
          }
        } else {
          // Other error - mark as failed
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
    }

    // Step 2: Close weekly_pools for this week
    // Note: weekly_pools.week_start_date stores the deadline (legacy naming)
    // All users with the same deadline share the same pool
    console.log("run-weekly-settlement: Closing weekly_pools for week", target.weekEndDate);
    const { error: closePoolErr } = await supabase
      .from("weekly_pools")
      .update({
        status: "closed",
        closed_at: new Date().toISOString()
      })
      .eq("week_start_date", target.weekEndDate); // Uses deadline as identifier
    
    if (closePoolErr) {
      console.error("run-weekly-settlement: Error closing weekly_pools:", closePoolErr);
      // Don't fail the entire settlement if pool closing fails - log and continue
    } else {
      console.log("run-weekly-settlement: Successfully closed weekly_pools for week", target.weekEndDate);
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
