-- ==============================================================================
-- Verification Query for Case 1_A_A: Sync Before Grace Begins + 0 Usage + 0 Penalty
-- Expected: No charge, status remains pending, no payments
-- ==============================================================================

-- Replace '<your-user-id>' with your test user ID

WITH latest_commitment AS (
  SELECT * FROM public.commitments
  WHERE user_id = '<your-user-id>'
  ORDER BY created_at DESC
  LIMIT 1
),
latest_penalty AS (
  SELECT * FROM public.user_week_penalties
  WHERE user_id = '<your-user-id>'
  ORDER BY week_start_date DESC
  LIMIT 1
),
payment_count AS (
  SELECT COUNT(*) as count
  FROM public.payments
  WHERE user_id = '<your-user-id>'
    AND created_at >= (SELECT created_at FROM latest_commitment)
),
usage_summary AS (
  SELECT 
    COUNT(*) as entry_count,
    SUM(penalty_cents) as total_penalty_cents
  FROM public.daily_usage
  WHERE user_id = '<your-user-id>'
)
SELECT 
  'Case 1_A_A Verification' as test_case,
  json_build_object(
    'commitment', (
      SELECT json_build_object(
        'id', c.id,
        'week_end_date', c.week_end_date,
        'week_grace_expires_at', c.week_grace_expires_at,
        'max_charge_cents', c.max_charge_cents,
        'status', c.status
      ) FROM latest_commitment c
    ),
    'penalty', (
      SELECT json_build_object(
        'settlement_status', p.settlement_status,
        'total_penalty_cents', p.total_penalty_cents,
        'charged_amount_cents', p.charged_amount_cents,
        'actual_amount_cents', p.actual_amount_cents,
        'needs_reconciliation', p.needs_reconciliation,
        'week_start_date', p.week_start_date
      ) FROM latest_penalty p
    ),
    'payments', (
      SELECT json_build_object(
        'count', pc.count,
        'expected', 0,
        'match', CASE WHEN pc.count = 0 THEN '✅ PASS' ELSE '❌ FAIL' END
      ) FROM payment_count pc
    ),
    'usage', (
      SELECT json_build_object(
        'entry_count', us.entry_count,
        'total_penalty_cents', us.total_penalty_cents,
        'expected_penalty', 0,
        'match', CASE WHEN COALESCE(us.total_penalty_cents, 0) = 0 THEN '✅ PASS' ELSE '❌ FAIL' END
      ) FROM usage_summary us
    ),
    'verification_checks', json_build_array(
      json_build_object(
        'check', 'Settlement status should be pending',
        'expected', 'pending',
        'actual', (SELECT settlement_status FROM latest_penalty),
        'pass', CASE WHEN (SELECT settlement_status FROM latest_penalty) = 'pending' THEN true ELSE false END
      ),
      json_build_object(
        'check', 'Charged amount should be 0 or null',
        'expected', 0,
        'actual', (SELECT COALESCE(charged_amount_cents, 0) FROM latest_penalty),
        'pass', CASE WHEN COALESCE((SELECT charged_amount_cents FROM latest_penalty), 0) = 0 THEN true ELSE false END
      ),
      json_build_object(
        'check', 'Total penalty should be 0',
        'expected', 0,
        'actual', (SELECT COALESCE(total_penalty_cents, 0) FROM latest_penalty),
        'pass', CASE WHEN COALESCE((SELECT total_penalty_cents FROM latest_penalty), 0) = 0 THEN true ELSE false END
      ),
      json_build_object(
        'check', 'No payments should be created',
        'expected', 0,
        'actual', (SELECT count FROM payment_count),
        'pass', CASE WHEN (SELECT count FROM payment_count) = 0 THEN true ELSE false END
      )
    ),
    'verification_time', NOW()
  ) as verification_result;

-- Quick summary query (easier to read)
SELECT 
  '=== Case 1_A_A Verification Summary ===' as section,
  '' as spacer1,
  'Commitment:' as label1,
  (SELECT 'Deadline: ' || week_end_date || ', Max Charge: ' || max_charge_cents || ' cents' 
   FROM latest_commitment) as commitment_info,
  '' as spacer2,
  'Penalty Record:' as label2,
  (SELECT 
    'Status: ' || COALESCE(settlement_status, 'NULL') || 
    ', Total Penalty: ' || COALESCE(total_penalty_cents::text, 'NULL') || ' cents' ||
    ', Charged: ' || COALESCE(charged_amount_cents::text, 'NULL') || ' cents'
   FROM latest_penalty) as penalty_info,
  '' as spacer3,
  'Payments:' as label3,
  (SELECT CASE 
    WHEN count = 0 THEN '✅ PASS: No payments created (expected)'
    ELSE '❌ FAIL: ' || count || ' payment(s) found (expected 0)'
   END FROM payment_count) as payment_check,
  '' as spacer4,
  'Usage:' as label4,
  (SELECT 
    CASE 
      WHEN COALESCE(total_penalty_cents, 0) = 0 THEN '✅ PASS: Total penalty is 0 cents (expected)'
      ELSE '❌ FAIL: Total penalty is ' || total_penalty_cents || ' cents (expected 0)'
    END
   FROM usage_summary) as usage_check,
  '' as spacer5,
  'Overall Result:' as label5,
  CASE 
    WHEN (SELECT settlement_status FROM latest_penalty) = 'pending' 
     AND COALESCE((SELECT charged_amount_cents FROM latest_penalty), 0) = 0
     AND COALESCE((SELECT total_penalty_cents FROM latest_penalty), 0) = 0
     AND (SELECT count FROM payment_count) = 0
    THEN '✅ ALL CHECKS PASSED'
    ELSE '❌ SOME CHECKS FAILED - Review details above'
  END as overall_result;

