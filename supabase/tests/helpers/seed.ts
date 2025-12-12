/**
 * Test Data Seeding
 * 
 * Functions to set up test data before running tests.
 * Uses rpc_setup_test_data from the database.
 */

import { callRpc } from "./client.ts";
import { TEST_USER_IDS } from "../config.ts";

// MARK: - Types

export interface SeedResult {
  success: boolean;
  message: string;
  deadline_date: string;
  real_user_id: string | null;
  real_user_stripe_customer: string | null;
  test_users_created: number;
  commitments_created: number;
  daily_usage_entries: number;
}

export interface SeedOptions {
  /** Email for the real user (default: jef+stripe@cavens.io) */
  realUserEmail?: string;
  /** Stripe customer ID for the real user */
  realUserStripeCustomer?: string;
}

// MARK: - Seeding Functions

/**
 * Seed the database with test data.
 * 
 * Creates:
 * - 3 test users (test_user_1, test_user_2, test_user_3)
 * - 1 real user (looked up by email or created with seed ID)
 * - Active commitments for each user
 * - Sample daily_usage entries with penalties
 * - A weekly_pool for the current week
 * 
 * @param options Optional configuration for seeding
 * @returns Seed result with IDs and counts
 */
export async function seedTestData(options: SeedOptions = {}): Promise<SeedResult> {
  console.log("SEED 🌱 Setting up test data...");
  
  const result = await callRpc<SeedResult>("rpc_setup_test_data", {
    p_real_user_email: options.realUserEmail ?? "",
    p_real_user_stripe_customer: options.realUserStripeCustomer ?? "",
  });
  
  console.log(`SEED ✅ Created ${result.test_users_created} test users`);
  console.log(`SEED ✅ Created ${result.commitments_created} commitments`);
  console.log(`SEED ✅ Created ${result.daily_usage_entries} daily usage entries`);
  console.log(`SEED ✅ Deadline date: ${result.deadline_date}`);
  
  if (result.real_user_id) {
    console.log(`SEED ✅ Real user ID: ${result.real_user_id}`);
  }
  
  return result;
}

/**
 * Get the test user IDs for use in tests.
 */
export function getTestUserIds() {
  return {
    testUser1: TEST_USER_IDS.testUser1,
    testUser2: TEST_USER_IDS.testUser2,
    testUser3: TEST_USER_IDS.testUser3,
  };
}

/**
 * Calculate the current week's deadline date (next Monday).
 * Matches the logic in rpc_setup_test_data.
 */
export function getCurrentDeadlineDate(): string {
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0 = Sunday, 1 = Monday, ...
  
  let deadlineDate: Date;
  
  if (dayOfWeek === 1) {
    // Monday - deadline is today
    deadlineDate = now;
  } else if (dayOfWeek === 0) {
    // Sunday - deadline is tomorrow (Monday)
    deadlineDate = new Date(now);
    deadlineDate.setDate(now.getDate() + 1);
  } else {
    // Tuesday-Saturday - deadline is previous Monday
    // This matches the SQL logic: CURRENT_DATE - (DOW - 1)
    deadlineDate = new Date(now);
    deadlineDate.setDate(now.getDate() - (dayOfWeek - 1));
  }
  
  // Format as YYYY-MM-DD
  return deadlineDate.toISOString().split("T")[0];
}




