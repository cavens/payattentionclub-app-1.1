-- Adds the columns needed for the weekly settlement flow
-- (Setup Intent + fixed Monday/Tuesday cadence).
-- This migration is Step 1 of Phase 6.

BEGIN;

-- Commitments now track the payment method we saved via SetupIntent
-- and the grace-period deadline applied to that record.
ALTER TABLE public.commitments
    ADD COLUMN IF NOT EXISTS saved_payment_method_id text,
    ADD COLUMN IF NOT EXISTS week_grace_expires_at timestamp with time zone;

-- Backfill existing commitments with a grace period that ends
-- 24 hours after the recorded week_end_date (Monday deadline).
UPDATE public.commitments
SET week_grace_expires_at = (week_end_date + INTERVAL '1 day')
WHERE week_grace_expires_at IS NULL;

-- User-week penalty rows keep richer bookkeeping so we can differentiate
-- between “charged worst-case”, “actual settled”, and “refunded”.
ALTER TABLE public.user_week_penalties
    ADD COLUMN IF NOT EXISTS charge_payment_intent_id text,
    ADD COLUMN IF NOT EXISTS charged_amount_cents integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS charged_at timestamp with time zone,
    ADD COLUMN IF NOT EXISTS actual_amount_cents integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS refund_amount_cents integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS refund_payment_intent_id text,
    ADD COLUMN IF NOT EXISTS refund_issued_at timestamp with time zone,
    ADD COLUMN IF NOT EXISTS settlement_status text NOT NULL DEFAULT 'pending';

-- Mirror existing totals/statuses into the new columns so historical data stays coherent.
UPDATE public.user_week_penalties
SET settlement_status      = COALESCE(settlement_status, status),
    charged_amount_cents   = COALESCE(charged_amount_cents, total_penalty_cents),
    actual_amount_cents    = COALESCE(actual_amount_cents, total_penalty_cents),
    refund_amount_cents    = COALESCE(refund_amount_cents, 0)
WHERE settlement_status IS NULL
   OR charged_amount_cents IS NULL
   OR actual_amount_cents IS NULL
   OR refund_amount_cents IS NULL;

-- Payments table needs to differentiate between penalty charges and refunds,
-- and optionally link a refund to the original PaymentIntent.
ALTER TABLE public.payments
    ADD COLUMN IF NOT EXISTS payment_type text NOT NULL DEFAULT 'penalty',
    ADD COLUMN IF NOT EXISTS related_payment_intent_id text;

COMMIT;







