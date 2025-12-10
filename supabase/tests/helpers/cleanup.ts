/**
 * Test Data Cleanup
 * 
 * Functions to tear down test data after tests complete.
 * Uses rpc_cleanup_test_data from the database.
 */

import { callRpc } from "./client.ts";

// MARK: - Types

export interface CleanupResult {
  success: boolean;
  message: string;
  deleted: {
    payments: number;
    daily_usage: number;
    user_week_penalties: number;
    commitments: number;
    weekly_pools: number;
    users: number;
  };
  test_user_ids_cleaned: string[];
}

export interface CleanupOptions {
  /** Also delete the test user records (default: false) */
  deleteTestUsers?: boolean;
  /** Email for the real test user to include in cleanup */
  realUserEmail?: string;
}

// MARK: - Cleanup Functions

/**
 * Clean up all test data from the database.
 * 
 * Deletes in FK-safe order:
 * 1. payments
 * 2. daily_usage
 * 3. user_week_penalties
 * 4. commitments
 * 5. weekly_pools (orphaned only)
 * 6. users (optional)
 * 
 * @param options Optional cleanup configuration
 * @returns Cleanup result with deletion counts
 */
export async function cleanupTestData(options: CleanupOptions = {}): Promise<CleanupResult> {
  console.log("CLEANUP 🧹 Removing test data...");
  
  const result = await callRpc<CleanupResult>("rpc_cleanup_test_data", {
    p_delete_test_users: options.deleteTestUsers ?? false,
    p_real_user_email: options.realUserEmail ?? "",
  });
  
  const d = result.deleted;
  console.log(`CLEANUP ✅ Deleted: ${d.payments} payments, ${d.daily_usage} daily_usage, ${d.user_week_penalties} week_penalties`);
  console.log(`CLEANUP ✅ Deleted: ${d.commitments} commitments, ${d.weekly_pools} pools, ${d.users} users`);
  
  return result;
}

/**
 * Clean up test data, ignoring errors.
 * Useful in test teardown where cleanup failure shouldn't fail the test.
 */
export async function cleanupTestDataSafe(options: CleanupOptions = {}): Promise<CleanupResult | null> {
  try {
    return await cleanupTestData(options);
  } catch (error) {
    console.warn(`CLEANUP ⚠️ Cleanup failed (ignoring): ${error}`);
    return null;
  }
}

/**
 * Run cleanup before AND after a test function.
 * Ensures clean state even if previous test failed mid-run.
 * 
 * @param testFn The test function to wrap
 * @param options Cleanup options
 */
export async function withCleanup<T>(
  testFn: () => Promise<T>,
  options: CleanupOptions = {}
): Promise<T> {
  // Clean before
  await cleanupTestDataSafe(options);
  
  try {
    // Run test
    return await testFn();
  } finally {
    // Clean after (always runs)
    await cleanupTestDataSafe(options);
  }
}

