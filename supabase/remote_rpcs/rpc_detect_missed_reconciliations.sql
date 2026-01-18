-- ==============================================================================
-- Function: rpc_detect_missed_reconciliations
-- Purpose: Detect and queue reconciliations that were missed during sync
-- 
-- This function finds penalty records where:
-- 1. Settlement has occurred (settlement_status is settled)
-- 2. Actual amount is set and differs from charged amount
-- 3. But needs_reconciliation is false (missed detection)
--
-- It then:
-- 1. Updates the penalty record with reconciliation flags
-- 2. Creates a queue entry if one doesn't exist
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rpc_detect_missed_reconciliations(
  p_limit integer DEFAULT 50
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER AS $$
DECLARE
  V_SETTLED_STATUSES CONSTANT text[] := ARRAY['charged_actual', 'charged_worst_case', 'refunded', 'refunded_partial'];
  V_STRIPE_MINIMUM_CENTS CONSTANT integer := 60;
  
  v_missed RECORD;
  v_reconciliation_delta integer;
  v_capped_actual integer;
  v_max_charge_cents integer;
  v_needs_reconciliation boolean;
  v_updated_count integer := 0;
  v_queued_count integer := 0;
  v_errors integer := 0;
  v_error_messages text[] := ARRAY[]::text[];
BEGIN
  -- Find penalty records that need reconciliation but weren't flagged
  FOR v_missed IN
    SELECT 
      uwp.user_id,
      uwp.week_start_date,
      uwp.settlement_status,
      uwp.charged_amount_cents,
      uwp.actual_amount_cents,
      uwp.needs_reconciliation,
      uwp.reconciliation_delta_cents,
      c.max_charge_cents
    FROM public.user_week_penalties uwp
    LEFT JOIN public.commitments c 
      ON c.user_id = uwp.user_id 
      AND c.week_end_date = uwp.week_start_date
    WHERE uwp.settlement_status = ANY(V_SETTLED_STATUSES)
      AND uwp.actual_amount_cents IS NOT NULL
      AND uwp.charged_amount_cents IS NOT NULL
      AND uwp.actual_amount_cents != uwp.charged_amount_cents
      AND COALESCE(uwp.needs_reconciliation, false) = false
    ORDER BY uwp.last_updated DESC
    LIMIT p_limit
  LOOP
    BEGIN
      -- Calculate capped actual (same logic as settlement)
      v_max_charge_cents := COALESCE(v_missed.max_charge_cents, v_missed.actual_amount_cents);
      v_capped_actual := LEAST(v_missed.actual_amount_cents, v_max_charge_cents);
      
      -- Calculate reconciliation delta
      v_reconciliation_delta := v_capped_actual - COALESCE(v_missed.charged_amount_cents, 0);
      
      -- Check if reconciliation is needed
      v_needs_reconciliation := false;
      IF v_reconciliation_delta != 0 THEN
        -- Special case: If previous charge was 0 due to below-minimum, and current actual is also below minimum,
        -- skip reconciliation (we can't charge the actual amount anyway, so no change is needed)
        IF v_missed.charged_amount_cents = 0 
           AND v_capped_actual < V_STRIPE_MINIMUM_CENTS THEN
          -- Both previous charge and current actual are below minimum - no reconciliation needed
          v_needs_reconciliation := false;
        ELSE
          v_needs_reconciliation := true;
        END IF;
      END IF;
      
      -- Update penalty record if reconciliation is needed
      IF v_needs_reconciliation THEN
        UPDATE public.user_week_penalties
        SET 
          needs_reconciliation = true,
          reconciliation_delta_cents = v_reconciliation_delta,
          reconciliation_reason = 'late_sync_delta',
          reconciliation_detected_at = COALESCE(reconciliation_detected_at, NOW()),
          last_updated = NOW()
        WHERE user_id = v_missed.user_id
          AND week_start_date = v_missed.week_start_date;
        
        v_updated_count := v_updated_count + 1;
        
        -- Check if queue entry already exists
        IF NOT EXISTS (
          SELECT 1 
          FROM public.reconciliation_queue
          WHERE user_id = v_missed.user_id
            AND week_start_date = v_missed.week_start_date
            AND status IN ('pending', 'processing')
        ) THEN
          -- Insert into reconciliation queue
          BEGIN
            INSERT INTO public.reconciliation_queue (
              user_id,
              week_start_date,
              reconciliation_delta_cents,
              status,
              created_at
            )
            VALUES (
              v_missed.user_id,
              v_missed.week_start_date,
              v_reconciliation_delta,
              'pending',
              NOW()
            )
            ON CONFLICT (user_id, week_start_date) 
            WHERE status = 'pending'
            DO UPDATE SET
              reconciliation_delta_cents = EXCLUDED.reconciliation_delta_cents,
              created_at = EXCLUDED.created_at,
              retry_count = 0;
            
            v_queued_count := v_queued_count + 1;
            
            RAISE NOTICE '✅ Detected and queued missed reconciliation: user % week % (delta: % cents)', 
              v_missed.user_id, v_missed.week_start_date, v_reconciliation_delta;
          EXCEPTION
            WHEN OTHERS THEN
              v_errors := v_errors + 1;
              v_error_messages := array_append(v_error_messages, 
                format('Failed to queue reconciliation for user %s week %s: %s', 
                  v_missed.user_id, v_missed.week_start_date, SQLERRM));
              RAISE WARNING '❌ Failed to queue reconciliation for user % week %: %', 
                v_missed.user_id, v_missed.week_start_date, SQLERRM;
          END;
        ELSE
          RAISE NOTICE '⚠️ Queue entry already exists for user % week %', 
            v_missed.user_id, v_missed.week_start_date;
        END IF;
      END IF;
      
    EXCEPTION
      WHEN OTHERS THEN
        v_errors := v_errors + 1;
        v_error_messages := array_append(v_error_messages, 
          format('Error processing user %s week %s: %s', 
            v_missed.user_id, v_missed.week_start_date, SQLERRM));
        RAISE WARNING '❌ Error processing missed reconciliation for user % week %: %', 
          v_missed.user_id, v_missed.week_start_date, SQLERRM;
    END;
  END LOOP;
  
  -- Return summary
  RETURN json_build_object(
    'success', true,
    'updated_count', v_updated_count,
    'queued_count', v_queued_count,
    'errors', v_errors,
    'error_messages', v_error_messages
  );
END;
$$;

