-- ==============================================================================
-- Check pg_net Extension Dependencies
-- ==============================================================================
-- Run this BEFORE dropping the extension to see what depends on it
-- ==============================================================================

-- Step 1: Check what functions/tables depend on pg_net extension
SELECT 
  'Dependencies' AS check_type,
  CASE 
    WHEN classid::regclass::text = 'pg_proc' THEN 'Function'
    WHEN classid::regclass::text = 'pg_class' THEN 'Table/View'
    ELSE 'Other'
  END AS object_type,
  CASE 
    WHEN classid::regclass::text = 'pg_proc' THEN 
      (SELECT proname || '(' || pg_get_function_arguments(oid) || ')' 
       FROM pg_proc WHERE oid = objid)
    WHEN classid::regclass::text = 'pg_class' THEN 
      (SELECT relname FROM pg_class WHERE oid = objid)
    ELSE objid::text
  END AS object_name,
  CASE 
    WHEN classid::regclass::text = 'pg_proc' THEN
      (SELECT nspname::text || '.' || proname 
       FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.oid = objid)
    ELSE 'N/A'
  END AS full_name
FROM pg_depend
WHERE refclassid = 'pg_extension'::regclass
  AND refobjid = (SELECT oid FROM pg_extension WHERE extname = 'pg_net')
ORDER BY classid::regclass::text, object_name;

-- Step 2: Check if any of YOUR functions depend on pg_net
SELECT 
  'Your Functions Using pg_net' AS check_type,
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.prosrc LIKE '%net.http_post%'
  OR p.prosrc LIKE '%pg_net%'
ORDER BY n.nspname, p.proname;

-- Step 3: Summary - Count dependencies
SELECT 
  'Summary' AS check_type,
  COUNT(*) AS total_dependencies,
  COUNT(*) FILTER (WHERE classid::regclass::text = 'pg_proc') AS function_dependencies,
  COUNT(*) FILTER (WHERE classid::regclass::text = 'pg_class') AS table_dependencies
FROM pg_depend
WHERE refclassid = 'pg_extension'::regclass
  AND refobjid = (SELECT oid FROM pg_extension WHERE extname = 'pg_net');

-- Step 4: If you see functions you created (like process_reconciliation_queue, call_settlement),
-- those will need to be recreated after dropping/recreating the extension.
-- The functions themselves won't be dropped, but they might break if they reference net.http_post
-- and the extension is moved.

