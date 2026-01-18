/**
 * Apply migration: Add week_end_timestamp column to commitments
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('STAGING_SUPABASE_URL');
const supabaseKey = Deno.env.get('STAGING_SUPABASE_SECRET_KEY');

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing environment variables');
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

// Read migration SQL
const migrationSQL = await Deno.readTextFile('supabase/migrations/20260115220000_add_week_end_timestamp_to_commitments.sql');

console.log('🔄 Applying migration: Add week_end_timestamp column');
console.log('');

// Split SQL into statements
const statements = migrationSQL
  .split(';')
  .map(s => s.trim())
  .filter(s => s.length > 0 && !s.startsWith('--'));

// Execute each statement
for (const statement of statements) {
  if (statement.length < 10) continue;
  
  try {
    // Use RPC to execute SQL (if available) or direct query
    // Note: Supabase REST API doesn't support DDL directly
    // We'll need to use the Management API or provide manual instructions
    
    console.log(`Executing: ${statement.substring(0, 60)}...`);
    
    // Try using a direct SQL execution if available
    // For now, we'll output the SQL for manual execution
    console.log('⚠️  Direct SQL execution via REST API is limited.');
    console.log('Please apply this migration via Supabase Dashboard SQL Editor:');
    console.log('');
    console.log('1. Go to: https://supabase.com/dashboard/project/auqujbppoytkeqdsgrbl/sql/new');
    console.log('2. Copy and paste the SQL below');
    console.log('3. Click "Run"');
    console.log('');
    console.log('--- SQL to Execute ---');
    console.log(migrationSQL);
    console.log('--- End SQL ---');
    
    Deno.exit(0);
  } catch (error) {
    console.error('Error:', error);
  }
}



