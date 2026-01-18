/**
 * Testing Command Runner Edge Function
 * 
 * Server-side execution of all testing commands.
 * Only works when TESTING_MODE=true.
 * 
 * Commands:
 * - toggle_testing_mode: Toggle testing mode on/off in app_config table
 * - get_testing_mode: Get current testing mode status from app_config
 * - clear_data: Delete all test user data
 * - delete_test_user: Delete a specific user by email (looks up user ID automatically)
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
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";
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

  // Parse request early to check command
  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: 'Invalid JSON in request body' }),
      { status: 400, headers: corsHeaders }
    );
  }

  const { command, userId, params = {} } = body;

  if (!command) {
    return new Response(
      JSON.stringify({ error: 'Missing command parameter' }),
      { status: 400, headers: corsHeaders }
    );
  }

  // Allow these commands even without TESTING_MODE (they're legitimate admin operations)
  const allowedWithoutTestingMode = ['delete_test_user', 'toggle_testing_mode', 'get_testing_mode'];
  const requiresTestingMode = !allowedWithoutTestingMode.includes(command);

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

    // Check testing mode from both environment variable AND database config
    // This allows testing mode to work even if only database config is set
    let isTestingMode = TESTING_MODE;
    
    if (!isTestingMode && requiresTestingMode) {
      // Check database app_config table for testing mode
      try {
        const { data: config, error: configError } = await supabase
          .from('app_config')
          .select('value')
          .eq('key', 'testing_mode')
          .single();
        
        if (!configError && config && config.value === 'true') {
          isTestingMode = true;
          console.log('testing-command-runner: Testing mode enabled via app_config table');
        }
      } catch (error) {
        // If app_config table doesn't exist or query fails, continue with env var check
        console.log('testing-command-runner: Could not check app_config, using environment variable only');
      }
    }

    if (requiresTestingMode && !isTestingMode) {
      return new Response(
        JSON.stringify({ 
          error: 'Testing mode not enabled. Set TESTING_MODE=true in Supabase secrets OR enable testing_mode in app_config table.' 
        }),
        { status: 403, headers: corsHeaders }
      );
    }

    // In testing mode, allow public access (no auth required)
    // This allows the web interface and test scripts to call the function
    if (isTestingMode) {
      console.log('testing-command-runner: Testing mode - public access allowed');
    } else if (!requiresTestingMode) {
      console.log(`testing-command-runner: Command '${command}' allowed without testing mode`);
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

      case "toggle_testing_mode": {
        // Toggle testing mode in BOTH app_config table AND Edge Function secrets
        const { data: currentConfig, error: fetchError } = await supabase
          .from('app_config')
          .select('value')
          .eq('key', 'testing_mode')
          .single();

        let newValue: string;
        if (currentConfig) {
          // Toggle: if true, set to false; if false, set to true
          newValue = currentConfig.value === 'true' ? 'false' : 'true';
        } else {
          // If not exists, default to true (enable testing mode)
          newValue = 'true';
        }

        // Step 1: Update app_config table
        const { data: updatedConfig, error: updateError } = await supabase
          .from('app_config')
          .upsert({
            key: 'testing_mode',
            value: newValue,
            description: newValue === 'true' 
              ? 'Enable compressed timeline testing (3 min week, 1 min grace)'
              : 'Normal timeline (7 day week, 24 hour grace)',
            updated_at: new Date().toISOString()
          }, {
            onConflict: 'key'
          })
          .select()
          .single();

        if (updateError) {
          return new Response(
            JSON.stringify({ error: 'Failed to toggle testing mode in app_config', details: updateError.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        // Step 2: Update TESTING_MODE Edge Function secret
        let secretUpdateSuccess = false;
        let secretUpdateError: string | null = null;
        
        try {
          const updateSecretUrl = `${supabaseUrl}/functions/v1/update-secret`;
          const secretResponse = await fetch(updateSecretUrl, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${supabaseSecretKey}`,
            },
            body: JSON.stringify({
              secretName: 'TESTING_MODE',
              secretValue: newValue,
            }),
          });

          if (secretResponse.ok) {
            secretUpdateSuccess = true;
            console.log('toggle_testing_mode: Successfully updated TESTING_MODE Edge Function secret');
          } else {
            const errorData = await secretResponse.json();
            secretUpdateError = errorData.error || `HTTP ${secretResponse.status}`;
            console.warn('toggle_testing_mode: Failed to update TESTING_MODE secret:', secretUpdateError);
          }
        } catch (error) {
          secretUpdateError = error instanceof Error ? error.message : String(error);
          console.error('toggle_testing_mode: Error calling update-secret:', secretUpdateError);
        }

        // Return result with status of both updates
        const isEnabled = updatedConfig.value === 'true';
        result = {
          success: true,
          testing_mode: isEnabled,
          message: `Testing mode ${isEnabled ? 'enabled' : 'disabled'}`,
          app_config_updated: true,
          secret_updated: secretUpdateSuccess,
          secret_update_error: secretUpdateError || null,
          warning: secretUpdateError 
            ? `⚠️ Testing mode updated in database, but Edge Function secret update failed. Please update TESTING_MODE manually in Supabase Dashboard → Edge Functions → Settings → Secrets to: ${newValue}`
            : null
        };
        break;
      }

      case "get_testing_mode": {
        // Get current testing mode status from app_config
        const { data: config, error: configError } = await supabase
          .from('app_config')
          .select('value, description, updated_at')
          .eq('key', 'testing_mode')
          .single();

        if (configError && configError.code !== 'PGRST116') {
          return new Response(
            JSON.stringify({ error: 'Failed to get testing mode', details: configError.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = {
          success: true,
          testing_mode: config?.value === 'true' || false,
          description: config?.description || null,
          updated_at: config?.updated_at || null
        };
        break;
      }

      case "delete_test_user": {
        // Delete a user by email address (looks up user ID automatically)
        const email = params.email;
        if (!email) {
          return new Response(
            JSON.stringify({ error: 'email parameter required for delete_test_user command' }),
            { status: 400, headers: corsHeaders }
          );
        }

        console.log(`delete_test_user: Deleting user with email: ${email}`);

        // Step 1: Look up user by email to get userId and stripe_customer_id
        const { data: users, error: lookupError } = await supabase
          .from('users')
          .select('id, stripe_customer_id')
          .eq('email', email)
          .limit(1);

        if (lookupError) {
          return new Response(
            JSON.stringify({ error: 'Failed to lookup user', details: lookupError.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        if (!users || users.length === 0) {
          return new Response(
            JSON.stringify({ error: `User with email ${email} not found` }),
            { status: 404, headers: corsHeaders }
          );
        }

        const user = users[0];
        const stripeCustomerId = user.stripe_customer_id;
        console.log(`delete_test_user: Found user ID: ${user.id}, Stripe customer: ${stripeCustomerId || 'none'}`);

        // Step 2: Delete Stripe customer and payment methods (if exists)
        let stripeDeleted = false;
        if (stripeCustomerId && !stripeCustomerId.startsWith('cus_test_')) {
          try {
            const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY_TEST') || Deno.env.get('STRIPE_SECRET_KEY');
            if (STRIPE_SECRET_KEY) {
              const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2023-10-16' });

              // Delete payment methods
              const paymentMethods = await stripe.paymentMethods.list({
                customer: stripeCustomerId,
                limit: 100,
              });

              let deletedPaymentMethods = 0;
              for (const pm of paymentMethods.data) {
                try {
                  await stripe.paymentMethods.detach(pm.id);
                  deletedPaymentMethods++;
                } catch (error: any) {
                  console.error(`Failed to detach payment method ${pm.id}: ${error.message}`);
                }
              }

              // Delete customer
              try {
                await stripe.customers.del(stripeCustomerId);
                stripeDeleted = true;
                console.log(`delete_test_user: Deleted ${deletedPaymentMethods} payment method(s) and Stripe customer`);
              } catch (error: any) {
                if (error.code !== 'resource_missing') {
                  throw error;
                }
                console.log(`delete_test_user: Stripe customer ${stripeCustomerId} not found (may already be deleted)`);
              }
            } else {
              console.log('delete_test_user: Stripe key not configured - skipping Stripe deletion');
            }
          } catch (error: any) {
            console.error(`delete_test_user: Warning - Failed to delete Stripe customer: ${error.message}`);
            console.error('Continuing with database deletion...');
          }
        } else if (stripeCustomerId?.startsWith('cus_test_')) {
          console.log('delete_test_user: Skipping fake test customer ID');
        } else {
          console.log('delete_test_user: No Stripe customer to delete');
        }

        // Step 3: Delete user from database using RPC
        const { data: deleteResult, error: deleteError } = await supabase.rpc('rpc_delete_user_completely', {
          p_email: email,
        });

        if (deleteError) {
          return new Response(
            JSON.stringify({ error: 'Failed to delete user from database', details: deleteError.message }),
            { status: 500, headers: corsHeaders }
          );
        }

        result = {
          success: true,
          email: email,
          userId: user.id,
          stripeDeleted: stripeDeleted,
          stripeCustomerId: stripeCustomerId || null,
          databaseDeleted: deleteResult || {},
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

