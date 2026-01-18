-- ==============================================================================
-- Migration: Create reconciliation_queue table for automatic reconciliation triggers
-- Date: 2026-01-11
-- Purpose: Queue reconciliation requests when pg_net is not available in PostgREST context
-- ==============================================================================
-- 
-- Problem: rpc_sync_daily_usage runs in PostgREST context where pg_net functions
-- are not available. Manual triggers work (use fetch() from Deno), but automatic
-- triggers fail.
-- 
-- Solution: Insert reconciliation requests into a queue table, then have a cron
-- job poll the queue and trigger reconciliation using pg_net (which works in cron context).
-- 
-- Flow:
-- 1. rpc_sync_daily_usage detects reconciliation needed → inserts into queue
-- 2. Cron job (every minute) polls queue → calls quick-handler via pg_net
-- 3. Queue entry marked as processed
-- ==============================================================================

-- Create reconciliation_queue table
CREATE TABLE IF NOT EXISTS public.reconciliation_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  week_start_date date NOT NULL,
  reconciliation_delta_cents integer NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  error_message text,
  retry_count integer NOT NULL DEFAULT 0
);

-- Index for fast queue polling
CREATE INDEX IF NOT EXISTS idx_reconciliation_queue_pending 
  ON public.reconciliation_queue(status, created_at) 
  WHERE status = 'pending';

-- Index for user/week lookups
CREATE INDEX IF NOT EXISTS idx_reconciliation_queue_user_week 
  ON public.reconciliation_queue(user_id, week_start_date);

-- Partial unique index: Ensure only one pending request per user/week
-- This allows multiple entries with different statuses, but only one 'pending' at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_reconciliation_queue_unique_pending
  ON public.reconciliation_queue(user_id, week_start_date)
  WHERE status = 'pending';

-- Enable RLS
ALTER TABLE public.reconciliation_queue ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own queue entries
-- Drop policy if it exists (for idempotency)
DROP POLICY IF EXISTS "Users can view own reconciliation queue entries" ON public.reconciliation_queue;

CREATE POLICY "Users can view own reconciliation queue entries"
  ON public.reconciliation_queue
  FOR SELECT
  USING (auth.uid() = user_id);

-- Add comments
COMMENT ON TABLE public.reconciliation_queue IS 
'Queue for automatic reconciliation triggers. Entries are created by rpc_sync_daily_usage 
when reconciliation is needed, and processed by a cron job that calls quick-handler.';

COMMENT ON COLUMN public.reconciliation_queue.status IS 
'pending: waiting to be processed
processing: currently being processed
completed: successfully processed
failed: processing failed (will retry up to max retries)';

