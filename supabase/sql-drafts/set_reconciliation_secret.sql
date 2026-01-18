-- ==============================================================================
-- Set Reconciliation Secret in app_config
-- ==============================================================================
-- This sets the reconciliation_secret that will be used by process_reconciliation_queue
-- to authenticate with the quick-handler Edge Function
-- ==============================================================================

INSERT INTO public.app_config (key, value, description) 
VALUES (
  'reconciliation_secret', 
  'fa9c58888f388864814114b81de1f12f30188eb3aa258c85b9ba9e57d06e69c4',
  'Secret for authenticating reconciliation cron job calls to quick-handler Edge Function'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Verify it was set
SELECT key, 
       CASE WHEN key = 'reconciliation_secret' THEN '***SET***' ELSE value END AS value,
       description
FROM app_config 
WHERE key = 'reconciliation_secret';

