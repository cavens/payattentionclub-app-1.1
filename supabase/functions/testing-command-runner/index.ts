/**
 * Testing Command Runner Edge Function
 * 
 * Server-side execution of all testing commands.
 * Only works when TESTING_MODE=true.
 * 
 * Commands:
 * - clear_data: Delete all test user data
 * - trigger_settlement: Trigger settlement with manual header
 * - trigger_reconciliation: Trigger reconciliation (if available)
 * - verify_results: Get complete verification for a user
 * - get_commitment: Get latest commitment for a user
 * - get_usage: Get usage entries for a user
 * - get_penalty: Get penalty record for a user
 * - get_payments: Get payment records for a user
 * - sql_query: Execute safe SQL query (read-only, user-scoped)
 * 
 * Usage:
 *   POST /functions/v1/testing-command-runner
 *   Body: { command: "verify_results", userId: "user-id", params: {} }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { TESTING_MODE } from "../_shared/timing.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // Check testing mode
  if (!TESTING_MODE) {
    return new Response(
      JSON.stringify({ error: 'Testing mode not enabled. Set TESTING_MODE=true in Supabase secrets.' }),
      { status: 403, headers: corsHeaders }
    );
  }

  // In testing mode, allow public access (no auth required)
  // This allows the web interface and test scripts to call the function
  console.log('testing-command-runner: Testing mode - public access allowed');

  try {
    // Get Supabase client with service role (for full database access)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY');

    if (!supabaseUrl || !supabaseSecretKey) {
      return new Response(
        JSON.stringify({ error: 'Supabase credentials missing' }),
        { status: 500, headers: corsHeaders }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseSecretKey);

    // Parse request
    const body = await req.json();
    const { command, userId, params = {} } = body;

    if (!command) {
      return new Response(
        JSON.stringify({ error: 'Missing command parameter' }),
        { status: 400, headers: corsHeaders }
      );
    }

    console.log(`TESTING_COMMAND: Executing command: ${command}, userId: ${userId || 'N/A'}`);

    let result: any;

    switch (command) {
      case "clear_data": {
        // Delete all test user data
        const { data, error } = await supabase.rpc('rpc_cleanup_test_data', {
          p_delete_test_users: params.deleteTestUsers || false,
          p_real_user_email: params.realUserEmail || "",
        });

        if (error) {
          return new Response(
            JSON.stringify({ error: 'Cleanup failed', details: error.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = data;
        break;
      }

      case "trigger_settlement": {
        // Trigger settlement with manual trigger header
        const settlementUrl = `${supabaseUrl}/functions/v1/bright-service`;
        const settlementResponse = await fetch(settlementUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-manual-trigger': 'true',
          },
          body: JSON.stringify(params.options || {}),
        });

        if (!settlementResponse.ok) {
          const errorText = await settlementResponse.text();
          return new Response(
            JSON.stringify({ error: 'Settlement trigger failed', details: errorText }),
            { status: settlementResponse.status, headers: corsHeaders }
          );
        }

        result = await settlementResponse.json();
        break;
      }

      case "trigger_reconciliation": {
        // Trigger reconciliation via quick-handler function
        const reconciliationUrl = `${supabaseUrl}/functions/v1/quick-handler`;
        const reconciliationResponse = await fetch(reconciliationUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${supabaseSecretKey}`,
          },
          body: JSON.stringify(params.options || {}),
        });

        if (!reconciliationResponse.ok) {
          const errorText = await reconciliationResponse.text();
          return new Response(
            JSON.stringify({ error: 'Reconciliation trigger failed', details: errorText }),
            { status: reconciliationResponse.status, headers: corsHeaders }
          );
        }

        result = await reconciliationResponse.json();
        break;
      }

      case "verify_results": {
        // Get complete verification for a user
        if (!userId) {
          return new Response(
            JSON.stringify({ error: 'userId required for verify_results command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        const { data, error } = await supabase.rpc('rpc_verify_test_settlement', {
          p_user_id: userId,
        });

        if (error) {
          return new Response(
            JSON.stringify({ error: 'Verification failed', details: error.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = data;
        break;
      }

      case "get_commitment": {
        // Get latest commitment for a user
        if (!userId) {
          return new Response(
            JSON.stringify({ error: 'userId required for get_commitment command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        const { data, error } = await supabase
          .from('commitments')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', { ascending: false })
          .limit(1)
          .single();

        if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
          return new Response(
            JSON.stringify({ error: 'Failed to get commitment', details: error.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = data || null;
        break;
      }

      case "get_usage": {
        // Get usage entries for a user
        if (!userId) {
          return new Response(
            JSON.stringify({ error: 'userId required for get_usage command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        const { data, error } = await supabase
          .from('daily_usage')
          .select('*')
          .eq('user_id', userId)
          .order('date', { ascending: false });

        if (error) {
          return new Response(
            JSON.stringify({ error: 'Failed to get usage', details: error.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = {
          count: data?.length || 0,
          entries: data || [],
        };
        break;
      }

      case "get_penalty": {
        // Get penalty record for a user
        if (!userId) {
          return new Response(
            JSON.stringify({ error: 'userId required for get_penalty command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        const { data, error } = await supabase
          .from('user_week_penalties')
          .select('*')
          .eq('user_id', userId)
          .order('week_start_date', { ascending: false })
          .limit(1)
          .single();

        if (error && error.code !== 'PGRST116') {
          return new Response(
            JSON.stringify({ error: 'Failed to get penalty', details: error.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = data || null;
        break;
      }

      case "get_payments": {
        // Get payment records for a user
        if (!userId) {
          return new Response(
            JSON.stringify({ error: 'userId required for get_payments command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        const { data, error } = await supabase
          .from('payments')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', { ascending: false });

        if (error) {
          return new Response(
            JSON.stringify({ error: 'Failed to get payments', details: error.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = {
          count: data?.length || 0,
          payments: data || [],
        };
        break;
      }

      case "sql_query": {
        // Execute safe SQL query (read-only, user-scoped)
        // SECURITY: Only allow SELECT queries, and only for the specified user
        if (!userId) {
          return new Response(
            JSON.stringify({ error: 'userId required for sql_query command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        const sql = params.sql;
        if (!sql) {
          return new Response(
            JSON.stringify({ error: 'sql parameter required' }),
            { status: 400, headers: corsHeaders }
          );
        }

        // Security: Only allow SELECT statements
        const trimmedSql = sql.trim().toUpperCase();
        if (!trimmedSql.startsWith('SELECT')) {
          return new Response(
            JSON.stringify({ error: 'Only SELECT queries are allowed for security' }),
            { status: 400, headers: corsHeaders }
          );
        }

        // Note: Supabase REST API doesn't support arbitrary SQL execution
        // This would need to be implemented via a custom RPC function
        // For now, return an error suggesting to use specific commands instead
        return new Response(
          JSON.stringify({ 
            error: 'Direct SQL execution not available via REST API',
            suggestion: 'Use specific commands (get_commitment, get_usage, etc.) or create a custom RPC function',
          }),
          { status: 501, headers: corsHeaders }
        );
      }

      default:
        return new Response(
          JSON.stringify({ error: `Unknown command: ${command}` }),
          { status: 400, headers: corsHeaders }
        );
    }

    return new Response(
      JSON.stringify({ success: true, command, result }),
      { status: 200, headers: corsHeaders }
    );

  } catch (error) {
    console.error('TESTING_COMMAND: Error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        details: error instanceof Error ? error.message : String(error) 
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

