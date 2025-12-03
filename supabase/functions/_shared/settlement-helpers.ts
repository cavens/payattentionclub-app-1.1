import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const TIME_ZONE = "America/New_York";

export type WeekTarget = {
  weekEndDate: string;
  graceDeadlineIso: string;
};

export type CommitmentRow = {
  id: string;
  user_id: string;
  week_end_date: string;
  week_grace_expires_at: string | null;
  saved_payment_method_id: string | null;
  max_charge_cents: number | null;
  status: string | null;
};

export type UserRow = {
  id: string;
  email: string | null;
  stripe_customer_id: string | null;
  has_active_payment_method: boolean | null;
};

export type UserWeekPenaltyRow = {
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

export type SettlementCandidate = {
  commitment: CommitmentRow;
  user: UserRow | undefined;
  penalty: UserWeekPenaltyRow | undefined;
  reportedDays: number;
};

function toDateInTimeZone(date: Date, timeZone: string): Date {
  return new Date(date.toLocaleString("en-US", { timeZone }));
}

function formatDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function resolveWeekTarget(options?: {
  override?: string;
  now?: Date;
}): WeekTarget {
  const override = options?.override;
  if (override) {
    const parsed = new Date(`${override}T12:00:00Z`);
    const grace = new Date(parsed);
    grace.setUTCDate(grace.getUTCDate() + 1);
    return {
      weekEndDate: override,
      graceDeadlineIso: grace.toISOString()
    };
  }

  const reference = toDateInTimeZone(options?.now ?? new Date(), TIME_ZONE);
  const monday = new Date(reference);
  const dayOfWeek = reference.getDay();
  const daysSinceMonday = (dayOfWeek + 6) % 7;
  monday.setDate(monday.getDate() - daysSinceMonday);
  monday.setHours(12, 0, 0, 0);

  const weekEndDate = formatDate(monday);
  const graceDeadline = new Date(monday);
  graceDeadline.setDate(graceDeadline.getDate() + 1);

  return {
    weekEndDate,
    graceDeadlineIso: graceDeadline.toISOString()
  };
}

async function fetchCommitmentsForWeek(
  supabase: SupabaseClient,
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

  if (error) {
    throw new Error(`Failed to fetch commitments for ${weekEndDate}: ${error.message}`);
  }

  return data ?? [];
}

async function fetchUserWeekPenalties(
  supabase: SupabaseClient,
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

  if (error) {
    throw new Error(`Failed to fetch user_week_penalties: ${error.message}`);
  }

  return data ?? [];
}

async function fetchUsers(
  supabase: SupabaseClient,
  userIds: string[]
): Promise<UserRow[]> {
  if (userIds.length === 0) return [];

  const { data, error } = await supabase
    .from("users")
    .select("id,email,stripe_customer_id,has_active_payment_method")
    .in("id", userIds);

  if (error) {
    throw new Error(`Failed to fetch users: ${error.message}`);
  }

  return data ?? [];
}

async function fetchUsageCounts(
  supabase: SupabaseClient,
  commitmentIds: string[]
): Promise<Map<string, number>> {
  if (commitmentIds.length === 0) {
    return new Map();
  }

  const { data, error } = await supabase
    .from("daily_usage")
    .select("commitment_id")
    .in("commitment_id", commitmentIds);

  if (error) {
    throw new Error(`Failed to fetch daily_usage rows: ${error.message}`);
  }

  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    if (!row?.commitment_id) continue;
    counts.set(row.commitment_id, (counts.get(row.commitment_id) ?? 0) + 1);
  }

  return counts;
}

export async function buildSettlementCandidates(
  supabase: SupabaseClient,
  weekEndDate: string
): Promise<SettlementCandidate[]> {
  const commitments = await fetchCommitmentsForWeek(supabase, weekEndDate);
  if (commitments.length === 0) {
    return [];
  }

  const userIds = Array.from(new Set(commitments.map((c) => c.user_id)));
  const commitmentIds = commitments.map((c) => c.id);

  const [penalties, users, usageCounts] = await Promise.all([
    fetchUserWeekPenalties(supabase, weekEndDate, userIds),
    fetchUsers(supabase, userIds),
    fetchUsageCounts(supabase, commitmentIds)
  ]);

  const penaltyMap = new Map<string, UserWeekPenaltyRow>();
  for (const penalty of penalties) {
    penaltyMap.set(penalty.user_id, penalty);
  }

  const userMap = new Map<string, UserRow>();
  for (const user of users) {
    userMap.set(user.id, user);
  }

  return commitments.map((commitment) => ({
    commitment,
    user: userMap.get(commitment.user_id),
    penalty: penaltyMap.get(commitment.user_id),
    reportedDays: usageCounts.get(commitment.id) ?? 0
  }));
}

export function hasSyncedUsage(candidate: SettlementCandidate): boolean {
  return candidate.reportedDays > 0;
}

export function isGracePeriodExpired(
  candidate: SettlementCandidate,
  reference: Date = new Date()
): boolean {
  const explicit = candidate.commitment.week_grace_expires_at;
  if (explicit) {
    return new Date(explicit).getTime() <= reference.getTime();
  }

  const derived = new Date(`${candidate.commitment.week_end_date}T00:00:00Z`);
  derived.setUTCDate(derived.getUTCDate() + 1);
  return derived.getTime() <= reference.getTime();
}

export function getWorstCaseAmountCents(candidate: SettlementCandidate): number {
  return candidate.commitment.max_charge_cents ?? 0;
}

export function getActualPenaltyCents(candidate: SettlementCandidate): number {
  return candidate.penalty?.total_penalty_cents ?? 0;
}
