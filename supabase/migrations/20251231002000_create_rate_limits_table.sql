-- ==============================================================================
-- Migration: Create rate_limits table for Edge Function rate limiting
-- Date: 2025-12-31
-- Purpose: Track rate limits per user per endpoint
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL, -- Format: "endpoint:user_id"
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  timestamp timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_rate_limits_key_timestamp ON public.rate_limits(key, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_rate_limits_user_id ON public.rate_limits(user_id);
CREATE INDEX IF NOT EXISTS idx_rate_limits_timestamp ON public.rate_limits(timestamp);

-- Enable RLS
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own rate limit entries (for debugging)
CREATE POLICY "Users can view their own rate limits"
  ON public.rate_limits
  FOR SELECT
  USING (auth.uid() = user_id);

-- RLS Policy: Service role can insert/delete (for Edge Functions)
-- Note: Edge Functions use service role key, so they can insert/delete
-- We don't need explicit policies for service role (it bypasses RLS)

-- Add comment
COMMENT ON TABLE public.rate_limits IS 
'Stores rate limit tracking data for Edge Functions.
Used to implement per-user rate limiting with sliding window algorithm.
Entries are automatically cleaned up after 2x the rate limit window.';

COMMENT ON COLUMN public.rate_limits.key IS 
'Rate limit key in format "endpoint:user_id" (e.g., "billing-status:uuid")';

COMMENT ON COLUMN public.rate_limits.user_id IS 
'User ID this rate limit entry belongs to';

COMMENT ON COLUMN public.rate_limits.timestamp IS 
'Timestamp when this request was made (used for sliding window calculation)';
