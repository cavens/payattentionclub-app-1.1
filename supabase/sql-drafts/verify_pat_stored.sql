-- ==============================================================================
-- Verify PAT is stored correctly
-- ==============================================================================

SELECT 
  key,
  '***HIDDEN***' AS value_preview,
  LENGTH(value) AS token_length,
  LEFT(value, 4) || '...' || RIGHT(value, 4) AS token_preview,
  description,
  updated_at,
  CASE 
    WHEN value IS NOT NULL AND value != '' AND LENGTH(value) > 10 THEN '✅ PAT is set and looks valid'
    ELSE '❌ PAT is missing or invalid'
  END AS status
FROM app_config
WHERE key = 'supabase_access_token';

