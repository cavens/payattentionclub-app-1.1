-- ==============================================================================
-- Function: Process reconciliation queue
-- Purpose: Poll reconciliation_queue and trigger quick-handler for pending requests
-- Called by: pg_cron (every minute)
-- ==============================================================================
-- 
-- This function processes pending reconciliation requests from the queue.
-- It uses pg_net.http_post() which works in cron context (but not in PostgREST context).
-- 
-- Flow:
-- 1. Find pending reconciliation requests (oldest first)
-- 2. Mark as 'processing'
-- 3. Call quick-handler Edge Function via pg_net
-- 4. Mark as 'completed' or 'failed' based on result
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.process_reconciliation_queue()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  queue_entry RECORD;
  svc_key text;
  supabase_url text;
  function_url text;
  request_id bigint;
  max_retries integer := 3;
  testing_mode boolean;
BEGIN
  -- Explicitly set search_path to include net schema
  -- This ensures net.http_post is accessible in cron context
  PERFORM set_config('search_path', 'public, net, extensions', true);

  -- Check TESTING_MODE from app_config (if not set, default to false for normal mode)
  -- Note: TESTING_MODE should be stored as 'true' or 'false' string in app_config
  SELECT COALESCE(
    (SELECT CASE WHEN value = 'true' THEN true ELSE false END 
     FROM public.app_config WHERE key = 'testing_mode'),
    false
  ) INTO testing_mode;

  -- Get settings from app_config table
  SELECT value INTO svc_key
  FROM public.app_config
  WHERE key = 'service_role_key';
  
  SELECT value INTO supabase_url
  FROM public.app_config
  WHERE key = 'supabase_url';

  IF svc_key IS NULL OR supabase_url IS NULL THEN
    RAISE WARNING 'Cannot process reconciliation queue: app_config not configured. Run scripts/setup_app_config.sh';
    RETURN;
  END IF;

  -- Build the Edge Function URL
  function_url := supabase_url || '/functions/v1/quick-handler';
  
  -- Log which mode we're in (for debugging)
  IF testing_mode THEN
    RAISE NOTICE 'Processing reconciliation queue in TESTING MODE (1-minute schedule)';
  ELSE
    RAISE NOTICE 'Processing reconciliation queue in NORMAL MODE (10-minute schedule)';
  END IF;

  -- Process pending reconciliation requests (oldest first, limit to 10 per run)
  FOR queue_entry IN
    SELECT id, user_id, week_start_date, reconciliation_delta_cents, retry_count
    FROM public.reconciliation_queue
    WHERE status = 'pending'
    ORDER BY created_at ASC
    LIMIT 10
    FOR UPDATE SKIP LOCKED  -- Prevent concurrent processing of same entry
  LOOP
    BEGIN
      -- Mark as processing
      UPDATE public.reconciliation_queue
      SET status = 'processing',
          processed_at = NOW()
      WHERE id = queue_entry.id;

      -- Call quick-handler Edge Function via pg_net (works in cron context)
      -- pg_net creates functions in the 'net' schema (regardless of extension location)
      -- Correct signature: net.http_post(url, body, params, headers, timeout_milliseconds)
      SELECT net.http_post(
        function_url,                                    -- url
        jsonb_build_object('userId', queue_entry.user_id::text), -- body
        '{}'::jsonb,                                          -- params
        jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || svc_key
        ),                                                     -- headers
        30000                                                  -- timeout_milliseconds (30 seconds)
      ) INTO request_id;

      -- Mark as completed
      UPDATE public.reconciliation_queue
      SET status = 'completed',
          processed_at = NOW()
      WHERE id = queue_entry.id;

      RAISE NOTICE '✅ Processed reconciliation queue entry % for user % week % (Request ID: %)', 
        queue_entry.id, queue_entry.user_id, queue_entry.week_start_date, request_id;

    EXCEPTION
      WHEN OTHERS THEN
        -- Mark as failed, increment retry count
        UPDATE public.reconciliation_queue
        SET status = CASE 
            WHEN queue_entry.retry_count >= max_retries THEN 'failed'
            ELSE 'pending'  -- Retry if under max retries
          END,
          error_message = SQLERRM,
          retry_count = queue_entry.retry_count + 1,
          processed_at = NOW()
        WHERE id = queue_entry.id;

        IF queue_entry.retry_count >= max_retries THEN
          RAISE WARNING '❌ Failed to process reconciliation queue entry % for user % week % (max retries reached): %', 
            queue_entry.id, queue_entry.user_id, queue_entry.week_start_date, SQLERRM;
        ELSE
          RAISE WARNING '⚠️ Failed to process reconciliation queue entry % for user % week % (retry %/%): %', 
            queue_entry.id, queue_entry.user_id, queue_entry.week_start_date, 
            queue_entry.retry_count + 1, max_retries, SQLERRM;
        END IF;
    END;
  END LOOP;
END;
$$;

