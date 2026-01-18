-- ==============================================================================
-- Check pg_net Table Structure
-- ==============================================================================

-- First, check what columns exist in net.http_request_queue
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'net'
  AND table_name = 'http_request_queue'
ORDER BY ordinal_position;

-- Then check what columns exist in net.http_request
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'net'
  AND table_name = 'http_request'
ORDER BY ordinal_position;

-- Check all tables in net schema
SELECT 
  table_name
FROM information_schema.tables
WHERE table_schema = 'net'
ORDER BY table_name;

