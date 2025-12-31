/**
 * Rate Limiting Utility for Edge Functions
 * 
 * Implements rate limiting using a sliding window algorithm with database storage.
 * Tracks requests per user in a database table to persist across Edge Function invocations.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface RateLimitConfig {
  /** Maximum number of requests allowed */
  maxRequests: number;
  /** Time window in milliseconds */
  windowMs: number;
  /** Unique identifier for this rate limit (e.g., 'billing-status', 'rapid-service') */
  keyPrefix: string;
}

export interface RateLimitResult {
  /** Whether the request is allowed */
  allowed: boolean;
  /** Number of requests remaining in the current window */
  remaining: number;
  /** Timestamp when the rate limit resets (milliseconds since epoch) */
  resetAt: number;
  /** Total limit for this window */
  limit: number;
}

/**
 * Check rate limit for a user
 * 
 * @param supabase - Supabase client (with service role key)
 * @param userId - User ID to check rate limit for
 * @param config - Rate limit configuration
 * @returns Rate limit result with headers
 */
export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  config: RateLimitConfig
): Promise<RateLimitResult> {
  const now = Date.now();
  const windowStart = now - config.windowMs;
  const rateLimitKey = `${config.keyPrefix}:${userId}`;
  
  // Clean up old entries (older than 2x window to be safe)
  const cleanupThreshold = now - (config.windowMs * 2);
  
  try {
    // Clean up old rate limit entries
    await supabase
      .from("rate_limits")
      .delete()
      .lt("timestamp", new Date(cleanupThreshold).toISOString());
    
    // Count requests in current window
    const { count, error: countError } = await supabase
      .from("rate_limits")
      .select("*", { count: "exact", head: true })
      .eq("key", rateLimitKey)
      .gte("timestamp", new Date(windowStart).toISOString());
    
    if (countError) {
      console.error("rateLimit: Error counting requests:", countError);
      // On error, allow the request (fail open for availability)
      return {
        allowed: true,
        remaining: config.maxRequests,
        resetAt: now + config.windowMs,
        limit: config.maxRequests,
      };
    }
    
    const currentCount = count || 0;
    const allowed = currentCount < config.maxRequests;
    const remaining = Math.max(0, config.maxRequests - currentCount);
    const resetAt = now + config.windowMs;
    
    if (allowed) {
      // Record this request
      await supabase.from("rate_limits").insert({
        key: rateLimitKey,
        user_id: userId,
        timestamp: new Date(now).toISOString(),
      });
    }
    
    return {
      allowed,
      remaining,
      resetAt,
      limit: config.maxRequests,
    };
  } catch (error) {
    console.error("rateLimit: Unexpected error:", error);
    // Fail open - allow request if rate limiting fails
    return {
      allowed: true,
      remaining: config.maxRequests,
      resetAt: now + config.windowMs,
      limit: config.maxRequests,
    };
  }
}

/**
 * Create rate limit response headers
 * 
 * @param result - Rate limit result
 * @returns Headers object with rate limit information
 */
export function createRateLimitHeaders(result: RateLimitResult): Record<string, string> {
  return {
    "X-RateLimit-Limit": result.limit.toString(),
    "X-RateLimit-Remaining": result.remaining.toString(),
    "X-RateLimit-Reset": Math.floor(result.resetAt / 1000).toString(), // Unix timestamp in seconds
  };
}

/**
 * Create a 429 Too Many Requests response with rate limit headers
 * 
 * @param result - Rate limit result
 * @param corsHeaders - Optional CORS headers to include
 * @returns Response object
 */
export function createRateLimitResponse(
  result: RateLimitResult,
  corsHeaders: Record<string, string> = {}
): Response {
  const headers = {
    ...corsHeaders,
    ...createRateLimitHeaders(result),
    "Content-Type": "application/json",
  };
  
  return new Response(
    JSON.stringify({
      error: "Rate limit exceeded",
      message: `Too many requests. Limit: ${result.limit} requests per ${result.limit}ms. Try again after ${new Date(result.resetAt).toISOString()}`,
      retry_after: Math.ceil((result.resetAt - Date.now()) / 1000), // Seconds until reset
    }),
    {
      status: 429,
      headers,
    }
  );
}

