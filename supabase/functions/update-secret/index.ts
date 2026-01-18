/**
 * Update Secret Edge Function
 * 
 * Admin-only function to update Edge Function secrets via Supabase Management API.
 * Used by testing-command-runner to update TESTING_MODE secret when toggling mode.
 * 
 * Usage:
 *   POST /functions/v1/update-secret
 *   Headers: Authorization: Bearer <service_role_key>
 *   Body: { secretName: "TESTING_MODE", secretValue: "true" }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed. Use POST.' }),
      { status: 405, headers: corsHeaders }
    );
  }

  try {
    // Get Supabase credentials
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseSecretKey = 
      Deno.env.get('STAGING_SUPABASE_SECRET_KEY') || 
      Deno.env.get('PRODUCTION_SUPABASE_SECRET_KEY');
    const UPDATE_SECRET_KEY = Deno.env.get('UPDATE_SECRET_KEY'); // Secret for authentication

    if (!supabaseUrl || !supabaseSecretKey) {
      return new Response(
        JSON.stringify({ error: 'Supabase credentials missing' }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Security: Require secret header for authentication (allows function to be public)
    if (UPDATE_SECRET_KEY) {
      const providedSecret = req.headers.get('x-update-secret-key');
      if (providedSecret !== UPDATE_SECRET_KEY) {
        console.log('update-secret: Unauthorized - invalid or missing secret');
        return new Response(
          JSON.stringify({ error: 'Unauthorized', message: 'Invalid or missing x-update-secret-key header' }),
          { status: 401, headers: corsHeaders }
        );
      }
      console.log('update-secret: Authorized via secret header');
    } else {
      // If no secret configured, allow service role key in Authorization header
      const authHeader = req.headers.get('Authorization');
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized', message: 'Missing Authorization header or UPDATE_SECRET_KEY not configured' }),
          { status: 401, headers: corsHeaders }
        );
      }
      // Verify it's the service role key (basic check)
      const token = authHeader.replace('Bearer ', '');
      if (token !== supabaseSecretKey) {
        return new Response(
          JSON.stringify({ error: 'Unauthorized', message: 'Invalid authorization token' }),
          { status: 401, headers: corsHeaders }
        );
      }
      console.log('update-secret: Authorized via service role key');
    }

    // Parse request body
    const body = await req.json();
    const { secretName, secretValue } = body;

    if (!secretName || secretValue === undefined) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: secretName, secretValue' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Extract project ref from SUPABASE_URL
    // Format: https://<project_ref>.supabase.co
    const urlMatch = supabaseUrl.match(/https:\/\/([^.]+)\.supabase\.co/);
    if (!urlMatch) {
      return new Response(
        JSON.stringify({ error: 'Could not extract project ref from SUPABASE_URL' }),
        { status: 500, headers: corsHeaders }
      );
    }
    const projectRef = urlMatch[1];

    // Get Supabase access token from app_config (if available)
    // Otherwise, we'll need to use Management API with service role key
    const supabase = createClient(supabaseUrl, supabaseSecretKey);
    
    // Try to get access token from app_config
    let accessToken: string | null = null;
    try {
      const { data: tokenConfig } = await supabase
        .from('app_config')
        .select('value')
        .eq('key', 'supabase_access_token')
        .single();
      
      if (tokenConfig) {
        accessToken = tokenConfig.value;
      }
    } catch (error) {
      console.log('update-secret: No access token in app_config, will try Management API with service role key');
    }

    // Use Supabase Management API to update secret
    // NOTE: Management API requires a Personal Access Token (PAT), not service role key
    // API endpoint: https://api.supabase.com/v1/projects/{project_ref}/secrets
    const managementApiUrl = `https://api.supabase.com/v1/projects/${projectRef}/secrets`;
    
    // Management API requires Personal Access Token (PAT) - service role key won't work
    // Try with access token from app_config (should be a PAT)
    if (!accessToken) {
      console.warn('update-secret: No Personal Access Token found in app_config.supabase_access_token');
      console.warn('update-secret: Management API requires PAT, not service role key');
      
      return new Response(
        JSON.stringify({ 
          error: 'Personal Access Token required',
          details: 'Supabase Management API requires a Personal Access Token (PAT) to update secrets. Service role key cannot be used.',
          suggestion: `To enable automatic secret updates:
1. Generate a Personal Access Token: https://supabase.com/dashboard/account/tokens
2. Store it in app_config: INSERT INTO app_config (key, value) VALUES ('supabase_access_token', 'your-pat-here')
3. Or update TESTING_MODE manually in Supabase Dashboard → Edge Functions → Settings → Secrets`,
          manualUpdate: `Manual update required:
1. Go to: https://supabase.com/dashboard/project/${projectRef}/settings/functions
2. Find secret: ${secretName}
3. Update value to: ${secretValue}`
        }),
        { status: 400, headers: corsHeaders }
      );
    }

    console.log(`update-secret: Attempting to update secret ${secretName} for project ${projectRef} via Management API`);

    // Management API expects an array of secrets, even for a single update
    const apiResponse = await fetch(managementApiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify([
        {
          name: secretName,
          value: secretValue,
        }
      ]),
    });

    if (!apiResponse.ok) {
      const errorText = await apiResponse.text();
      let errorData: any;
      try {
        errorData = JSON.parse(errorText);
      } catch {
        errorData = { message: errorText || 'Empty response' };
      }
      
      console.error(`update-secret: Management API error: ${apiResponse.status}`, errorData);
      console.error(`update-secret: Response headers:`, Object.fromEntries(apiResponse.headers.entries()));
      
      // If Management API doesn't work, return error with instructions
      return new Response(
        JSON.stringify({ 
          error: 'Failed to update secret via Management API',
          details: errorData.message || errorText || 'Unknown error',
          statusCode: apiResponse.status,
          responseText: errorText.substring(0, 500), // First 500 chars for debugging
          suggestion: `Management API update failed. Please update manually:
1. Go to: https://supabase.com/dashboard/project/${projectRef}/settings/functions
2. Find secret: ${secretName}
3. Update value to: ${secretValue}`,
          alternative: 'Or set supabase_access_token in app_config with a Personal Access Token from https://supabase.com/dashboard/account/tokens'
        }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Try to parse response, but handle empty responses
    let result: any;
    const responseText = await apiResponse.text();
    if (responseText) {
      try {
        result = JSON.parse(responseText);
      } catch (e) {
        console.warn('update-secret: Response is not JSON, treating as success');
        result = { message: responseText || 'Secret updated successfully' };
      }
    } else {
      result = { message: 'Secret updated successfully (empty response)' };
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: `Secret ${secretName} updated successfully via Management API`,
        secretName,
        projectRef
      }),
      { status: 200, headers: corsHeaders }
    );

  } catch (error) {
    console.error('update-secret: Error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        details: error instanceof Error ? error.message : String(error) 
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

