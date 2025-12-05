-- Adds reconciliation tracking columns for late-sync settlements (Phase 6 - Step 4A)
-- Ensures we can flag weeks that were already charged but now have updated totals.

BEGIN;

ALTER TABLE public.user_week_penalties
    ADD COLUMN IF NOT EXISTS needs_reconciliation boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS reconciliation_delta_cents integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS reconciliation_reason text,
    ADD COLUMN IF NOT EXISTS reconciliation_detected_at timestamp with time zone;

COMMIT;
