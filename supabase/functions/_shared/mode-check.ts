/**
 * Shared Mode Checking Helper
 * 
 * Provides consistent way to check testing mode across all Edge Functions.
 * Database (app_config) is the primary source of truth, env var is fallback.
 * 
 * This ensures all functions use the same logic and avoid stale constants.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Get testing mode status
 * 
 * Checks database (app_config) first, then falls back to environment variable.
 * Database is the primary source of truth.
 * 
 * @param supabase Supabase client (with service role key for admin access)
 * @returns Promise<boolean> - true if testing mode is enabled
 */
export async function getTestingMode(supabase: SupabaseClient): Promise<boolean> {
  // First, try to check database (primary source of truth)
  try {
    const { data: config, error: configError } = await supabase
      .from('app_config')
      .select('value')
      .eq('key', 'testing_mode')
      .single();
    
    if (!configError && config && config.value === 'true') {
      return true;
    }
    
    // If database says false or doesn't exist, that's fine - continue to env var check
    if (configError) {
      console.log(`getTestingMode: Could not read app_config: ${configError.message}, falling back to env var`);
    }
  } catch (error) {
    // If app_config table doesn't exist or query fails, continue with env var check
    console.log(`getTestingMode: Could not check app_config: ${error instanceof Error ? error.message : String(error)}, falling back to env var`);
  }
  
  // Fallback to environment variable
  const envMode = Deno.env.get("TESTING_MODE") === "true";
  return envMode;
}

/**
 * Get testing mode status synchronously (from env var only)
 * 
 * Use this only when you can't make async calls (e.g., module-level constants).
 * Prefer getTestingMode() for runtime checks.
 * 
 * @returns boolean - true if TESTING_MODE env var is "true"
 */
export function getTestingModeSync(): boolean {
  return Deno.env.get("TESTING_MODE") === "true";
}

