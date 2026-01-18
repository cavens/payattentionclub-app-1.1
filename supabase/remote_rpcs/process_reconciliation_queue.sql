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
  reconciliation_secret text;
  function_url text;
  request_id bigint;
  max_retries integer := 3;
  testing_mode boolean;
  v_refund_issued boolean;
  v_refund_amount integer;
  request_headers jsonb;
  request_body jsonb;
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
  
  SELECT value INTO reconciliation_secret
  FROM public.app_config
  WHERE key = 'reconciliation_secret';

  IF svc_key IS NULL OR supabase_url IS NULL THEN
    RAISE WARNING 'Cannot process reconciliation queue: app_config not configured. Run scripts/setup_app_config.sh';
    RETURN;
  END IF;
  
  -- Note: reconciliation_secret is optional - if not set, quick-handler must be private or use different auth

  -- Build the Edge Function URL
  function_url := supabase_url || '/functions/v1/quick-handler';
  
  -- Log which mode we're in (for debugging)
  IF testing_mode THEN
    RAISE NOTICE 'Processing reconciliation queue in TESTING MODE (1-minute schedule)';
  ELSE
    RAISE NOTICE 'Processing reconciliation queue in NORMAL MODE (10-minute schedule)';
  END IF;

  -- Process pending reconciliation requests (oldest first, limit to 10 per run)
  -- Also check for 'processing' entries that have been processing for > 5 minutes (likely failed)
  FOR queue_entry IN
    SELECT id, user_id, week_start_date, reconciliation_delta_cents, retry_count
    FROM public.reconciliation_queue
    WHERE status = 'pending'
       OR (status = 'processing' AND processed_at < NOW() - INTERVAL '5 minutes')
    ORDER BY 
      CASE WHEN status = 'pending' THEN 0 ELSE 1 END,  -- Process pending first
      created_at ASC
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
      -- Correct signature: net.http_post(url := ..., headers := ..., body := ...)
      -- FIXED: Match exact working pattern from settlement cron (call_settlement function)
      -- Build headers and body as variables first to avoid CASE statement evaluation issues
      -- NOTE: net.http_post is asynchronous - it returns a request_id immediately but the HTTP request
      -- is queued and executed later. We cannot mark as 'completed' here because we don't know if it succeeded.
      -- Instead, we keep it as 'processing' and verify the refund was issued by checking the penalty record.
      -- 
      -- Authentication: Use ONLY x-reconciliation-secret header (function must be PUBLIC)
      -- Match the working pattern from settlement cron (bright-service) which uses ONLY x-settlement-secret
      -- The Supabase gateway rejects sb_secret_... keys in Authorization header (they're not JWT tokens)
      -- Solution: Make quick-handler PUBLIC and use only custom secret header for authentication
      IF reconciliation_secret IS NOT NULL THEN
        request_headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-reconciliation-secret', reconciliation_secret
        );
      ELSE
        -- Fallback: If no secret, function must be private and use service role key
        -- But service_role_key is now sb_secret_... format, not JWT, so this won't work
        -- Function should always have reconciliation_secret set
        RAISE WARNING 'reconciliation_secret not set in app_config - quick-handler must be public with x-reconciliation-secret';
        request_headers := jsonb_build_object(
          'Content-Type', 'application/json'
        );
      END IF;
      
      -- Build request body
      request_body := jsonb_build_object('userId', queue_entry.user_id::text);
      
      -- Call quick-handler (matches exact pattern from working settlement cron)
      SELECT net.http_post(
        url := function_url,
        headers := request_headers,
        body := request_body
      ) INTO request_id;

      -- Log the request_id for debugging
      RAISE NOTICE '🔍 DEBUG: net.http_post returned request_id: %', request_id;
      RAISE NOTICE '🔍 DEBUG: function_url: %', function_url;
      RAISE NOTICE '🔍 DEBUG: headers: %', request_headers;

      -- Keep status as 'processing' - we'll verify completion by checking if refund was issued
      -- Check if refund was already issued (in case quick-handler already processed it)
      SELECT 
        COALESCE(refund_amount_cents, 0) > 0,
        COALESCE(refund_amount_cents, 0)
      INTO v_refund_issued, v_refund_amount
      FROM public.user_week_penalties
      WHERE user_id = queue_entry.user_id
        AND week_start_date = queue_entry.week_start_date;
      
      IF v_refund_issued AND v_refund_amount >= ABS(queue_entry.reconciliation_delta_cents) THEN
        -- Refund was already issued, mark as completed
        UPDATE public.reconciliation_queue
        SET status = 'completed',
            processed_at = NOW()
        WHERE id = queue_entry.id;
        
        RAISE NOTICE '✅ Reconciliation already completed for user % week % (Refund: % cents)', 
          queue_entry.user_id, queue_entry.week_start_date, v_refund_amount;
      ELSE
        -- Keep as processing, will be checked again on next run
        -- If it's been processing for > 5 minutes, it will be retried on next run
        RAISE NOTICE '✅ Queued reconciliation request for user % week % (Request ID: %, Status: processing, will verify on next run)', 
          queue_entry.user_id, queue_entry.week_start_date, request_id;
      END IF;

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

