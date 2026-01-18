-- ==============================================================================
-- RPC: rpc_validate_mode_consistency
-- ==============================================================================
-- Validates that testing mode configuration is consistent across all locations:
-- 1. app_config.testing_mode
-- 2. Edge Function secrets (via checking cron job behavior)
-- 3. Cron job schedules
-- 
-- Returns a JSON object with validation results and any mismatches found.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_validate_mode_consistency()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  app_config_mode text;
  app_config_mode_bool boolean;
  testing_settlement_cron_active boolean;
  weekly_settlement_cron_active boolean;
  validation_result jsonb;
  issues jsonb := '[]'::jsonb;
  warnings jsonb := '[]'::jsonb;
BEGIN
  -- Get testing mode from app_config
  SELECT value INTO app_config_mode
  FROM public.app_config
  WHERE key = 'testing_mode';
  
  app_config_mode_bool := COALESCE(app_config_mode = 'true', false);
  
  -- Check cron job status
  SELECT active INTO testing_settlement_cron_active
  FROM cron.job
  WHERE jobname = 'Testing-Settlement'
  LIMIT 1;
  
  SELECT active INTO weekly_settlement_cron_active
  FROM cron.job
  WHERE jobname = 'Weekly-Settlement'
  LIMIT 1;
  
  -- Validation 1: Check if PAT is configured (needed for secret updates)
  IF NOT EXISTS (
    SELECT 1 FROM public.app_config 
    WHERE key = 'supabase_access_token' 
    AND value IS NOT NULL 
    AND value != ''
  ) THEN
    issues := issues || jsonb_build_object(
      'type', 'missing_pat',
      'severity', 'medium',
      'message', 'Personal Access Token not configured in app_config',
      'impact', 'Edge Function secrets cannot be updated automatically',
      'fix', 'Store PAT in app_config with key: supabase_access_token'
    );
  END IF;
  
  -- Validation 2: Check cron job consistency
  IF app_config_mode_bool THEN
    -- Testing mode: Testing-Settlement should be active, Weekly-Settlement should be active (but will skip)
    IF NOT COALESCE(testing_settlement_cron_active, false) THEN
      issues := issues || jsonb_build_object(
        'type', 'cron_mismatch',
        'severity', 'high',
        'message', 'Testing mode is ON but Testing-Settlement cron is not active',
        'expected', 'Testing-Settlement should be active',
        'actual', 'Testing-Settlement is inactive'
      );
    END IF;
  ELSE
    -- Normal mode: Weekly-Settlement should be active, Testing-Settlement should be inactive
    IF NOT COALESCE(weekly_settlement_cron_active, false) THEN
      issues := issues || jsonb_build_object(
        'type', 'cron_mismatch',
        'severity', 'high',
        'message', 'Normal mode is ON but Weekly-Settlement cron is not active',
        'expected', 'Weekly-Settlement should be active',
        'actual', 'Weekly-Settlement is inactive'
      );
    END IF;
    
    IF COALESCE(testing_settlement_cron_active, false) THEN
      warnings := warnings || jsonb_build_object(
        'type', 'cron_warning',
        'severity', 'medium',
        'message', 'Normal mode is ON but Testing-Settlement cron is still active',
        'note', 'This is OK - the cron will skip execution when testing_mode is false'
      );
    END IF;
  END IF;
  
  -- Validation 3: Check for required app_config entries
  IF NOT EXISTS (SELECT 1 FROM public.app_config WHERE key = 'testing_mode') THEN
    issues := issues || jsonb_build_object(
      'type', 'missing_config',
      'severity', 'critical',
      'message', 'testing_mode not found in app_config',
      'fix', 'Insert testing_mode into app_config table'
    );
  END IF;
  
  -- Validation 4: Check for required secrets in app_config
  IF NOT EXISTS (SELECT 1 FROM public.app_config WHERE key = 'service_role_key') THEN
    warnings := warnings || jsonb_build_object(
      'type', 'missing_secret',
      'severity', 'low',
      'message', 'service_role_key not in app_config (may be OK if using Edge Function secrets)'
    );
  END IF;
  
  -- Build result
  validation_result := jsonb_build_object(
    'valid', jsonb_array_length(issues) = 0,
    'mode', CASE WHEN app_config_mode_bool THEN 'testing' ELSE 'normal' END,
    'app_config_mode', app_config_mode,
    'cron_jobs', jsonb_build_object(
      'testing_settlement', jsonb_build_object(
        'active', COALESCE(testing_settlement_cron_active, false),
        'jobname', 'Testing-Settlement'
      ),
      'weekly_settlement', jsonb_build_object(
        'active', COALESCE(weekly_settlement_cron_active, false),
        'jobname', 'Weekly-Settlement'
      )
    ),
    'issues', issues,
    'warnings', warnings,
    'timestamp', NOW()
  );
  
  RETURN validation_result;
END;
$$;

COMMENT ON FUNCTION public.rpc_validate_mode_consistency() IS 
'Validates that testing mode configuration is consistent across app_config, cron jobs, and expected behavior.
Returns JSON with validation results, issues, and warnings.
Use this before and after mode transitions to ensure consistency.';

