/**
 * Test Assertions
 * 
 * Reusable assertion functions for PAC backend tests.
 * Each function queries the database and asserts expected state.
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { supabase } from "./client.ts";

// MARK: - Commitment Assertions

/**
 * Assert that a commitment exists for a user on a specific week.
 */
export async function assertCommitmentExists(
  userId: string,
  weekEndDate: string,
  options?: {
    status?: string;
    limitMinutes?: number;
    penaltyPerMinuteCents?: number;
  }
): Promise<string> {
  const { data, error } = await supabase
    .from("commitments")
    .select("*")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate)
    .single();

  if (error) {
    throw new Error(`Commitment not found for user ${userId} week ${weekEndDate}: ${error.message}`);
  }

  assertExists(data, `Commitment should exist for user ${userId}`);

  if (options?.status) {
    assertEquals(data.status, options.status, `Commitment status should be ${options.status}`);
  }
  if (options?.limitMinutes !== undefined) {
    assertEquals(data.limit_minutes, options.limitMinutes, `Limit minutes should be ${options.limitMinutes}`);
  }
  if (options?.penaltyPerMinuteCents !== undefined) {
    assertEquals(
      data.penalty_per_minute_cents,
      options.penaltyPerMinuteCents,
      `Penalty per minute should be ${options.penaltyPerMinuteCents} cents`
    );
  }

  return data.id;
}

/**
 * Assert that NO commitment exists for a user on a specific week.
 */
export async function assertCommitmentNotExists(
  userId: string,
  weekEndDate: string
): Promise<void> {
  const { data, error } = await supabase
    .from("commitments")
    .select("id")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate);

  if (error) {
    throw new Error(`Error checking commitment: ${error.message}`);
  }

  assertEquals(data?.length ?? 0, 0, `Commitment should NOT exist for user ${userId} week ${weekEndDate}`);
}

// MARK: - Penalty Assertions

/**
 * Assert that a user's week penalty matches expected value.
 */
export async function assertPenaltyEquals(
  userId: string,
  weekEndDate: string,
  expectedCents: number
): Promise<void> {
  const { data, error } = await supabase
    .from("user_week_penalties")
    .select("total_penalty_cents")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate)
    .single();

  if (error && error.code !== "PGRST116") {
    // PGRST116 = not found, which is valid (means 0 penalty)
    throw new Error(`Error fetching penalty: ${error.message}`);
  }

  const actualCents = data?.total_penalty_cents ?? 0;
  assertEquals(
    actualCents,
    expectedCents,
    `Penalty for user ${userId} week ${weekEndDate} should be ${expectedCents} cents, got ${actualCents}`
  );
}

/**
 * Assert that daily usage penalty calculation is correct.
 */
export async function assertDailyUsagePenalty(
  userId: string,
  date: string,
  expectedExceededMinutes: number,
  expectedPenaltyCents: number
): Promise<void> {
  const { data, error } = await supabase
    .from("daily_usage")
    .select("exceeded_minutes, penalty_cents")
    .eq("user_id", userId)
    .eq("date", date)
    .single();

  if (error) {
    throw new Error(`Daily usage not found for user ${userId} date ${date}: ${error.message}`);
  }

  assertEquals(
    data.exceeded_minutes,
    expectedExceededMinutes,
    `Exceeded minutes should be ${expectedExceededMinutes}`
  );
  assertEquals(
    data.penalty_cents,
    expectedPenaltyCents,
    `Penalty should be ${expectedPenaltyCents} cents`
  );
}

// MARK: - Payment Assertions

/**
 * Assert that a payment exists with expected status.
 */
export async function assertPaymentStatus(
  userId: string,
  weekEndDate: string,
  expectedStatus: string
): Promise<string> {
  const { data, error } = await supabase
    .from("payments")
    .select("*")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate)
    .single();

  if (error) {
    throw new Error(`Payment not found for user ${userId} week ${weekEndDate}: ${error.message}`);
  }

  assertEquals(
    data.status,
    expectedStatus,
    `Payment status should be ${expectedStatus}, got ${data.status}`
  );

  return data.id;
}

/**
 * Assert that a payment amount matches expected value.
 */
export async function assertPaymentAmount(
  userId: string,
  weekEndDate: string,
  expectedAmountCents: number
): Promise<void> {
  const { data, error } = await supabase
    .from("payments")
    .select("amount_cents")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate)
    .single();

  if (error) {
    throw new Error(`Payment not found for user ${userId} week ${weekEndDate}: ${error.message}`);
  }

  assertEquals(
    data.amount_cents,
    expectedAmountCents,
    `Payment amount should be ${expectedAmountCents} cents`
  );
}

// MARK: - Weekly Pool Assertions

/**
 * Assert that a weekly pool exists with expected status.
 */
export async function assertWeeklyPoolStatus(
  weekEndDate: string,
  expectedStatus: string
): Promise<void> {
  const { data, error } = await supabase
    .from("weekly_pools")
    .select("status")
    .eq("week_end_date", weekEndDate)
    .single();

  if (error) {
    throw new Error(`Weekly pool not found for week ${weekEndDate}: ${error.message}`);
  }

  assertEquals(
    data.status,
    expectedStatus,
    `Weekly pool status should be ${expectedStatus}`
  );
}

// MARK: - Reconciliation Assertions

/**
 * Assert that a commitment is flagged for reconciliation.
 */
export async function assertReconciliationFlagged(
  userId: string,
  weekEndDate: string
): Promise<void> {
  const { data, error } = await supabase
    .from("user_week_penalties")
    .select("needs_reconciliation, reconciliation_delta_cents")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate)
    .single();

  if (error) {
    throw new Error(`Week penalty not found for user ${userId} week ${weekEndDate}: ${error.message}`);
  }

  assertEquals(
    data.needs_reconciliation,
    true,
    `User ${userId} should be flagged for reconciliation`
  );
}

/**
 * Assert the reconciliation delta (refund/charge adjustment).
 */
export async function assertReconciliationDelta(
  userId: string,
  weekEndDate: string,
  expectedDeltaCents: number
): Promise<void> {
  const { data, error } = await supabase
    .from("user_week_penalties")
    .select("reconciliation_delta_cents")
    .eq("user_id", userId)
    .eq("week_end_date", weekEndDate)
    .single();

  if (error) {
    throw new Error(`Week penalty not found for user ${userId} week ${weekEndDate}: ${error.message}`);
  }

  assertEquals(
    data.reconciliation_delta_cents,
    expectedDeltaCents,
    `Reconciliation delta should be ${expectedDeltaCents} cents`
  );
}

// MARK: - User Assertions

/**
 * Assert that a user has an active payment method.
 */
export async function assertUserHasPaymentMethod(userId: string): Promise<void> {
  const { data, error } = await supabase
    .from("users")
    .select("has_active_payment_method, stripe_customer_id")
    .eq("id", userId)
    .single();

  if (error) {
    throw new Error(`User not found: ${userId}: ${error.message}`);
  }

  assertEquals(
    data.has_active_payment_method,
    true,
    `User ${userId} should have active payment method`
  );
  assertExists(
    data.stripe_customer_id,
    `User ${userId} should have Stripe customer ID`
  );
}

