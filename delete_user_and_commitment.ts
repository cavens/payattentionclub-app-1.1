#!/usr/bin/env -S deno run --allow-net --allow-env --allow-read
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { load } from "https://deno.land/std@0.208.0/dotenv/mod.ts";

// Load .env file
const env = await load();
for (const [key, value] of Object.entries(env)) {
  Deno.env.set(key, value);
}

const SUPABASE_URL = Deno.env.get("STAGING_SUPABASE_URL") || "";
const SUPABASE_SERVICE_KEY = Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("STAGING_SUPABASE_SERVICE_ROLE_KEY") || "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("❌ Missing environment variables");
  Deno.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

const email = "jef@cavens.io";

console.log(`🗑️  Deleting user and commitments for: ${email}\n`);

// 1. Find the user in auth.users
const { data: authUsers, error: authError } = await supabase.auth.admin.listUsers();
if (authError) {
  console.error("❌ Error fetching auth users:", authError);
  Deno.exit(1);
}

const authUser = authUsers.users.find(u => u.email === email);
if (!authUser) {
  console.log(`ℹ️  User not found in auth.users: ${email}`);
} else {
  console.log(`✅ Found user in auth.users: ${authUser.id}`);
  
  // 2. Delete commitments for this user
  const { data: commitments, error: commitError } = await supabase
    .from("commitments")
    .select("id, created_at, status")
    .eq("user_id", authUser.id);
  
  if (commitError) {
    console.error("❌ Error fetching commitments:", commitError);
  } else if (commitments && commitments.length > 0) {
    console.log(`📝 Found ${commitments.length} commitment(s) to delete`);
    
    const { error: deleteCommitError } = await supabase
      .from("commitments")
      .delete()
      .eq("user_id", authUser.id);
    
    if (deleteCommitError) {
      console.error("❌ Error deleting commitments:", deleteCommitError);
    } else {
      console.log(`✅ Deleted ${commitments.length} commitment(s)`);
    }
  } else {
    console.log("ℹ️  No commitments found for this user");
  }
  
  // 3. Delete from public.users
  const { error: deletePublicUserError } = await supabase
    .from("users")
    .delete()
    .eq("id", authUser.id);
  
  if (deletePublicUserError) {
    console.error("❌ Error deleting from public.users:", deletePublicUserError);
  } else {
    console.log(`✅ Deleted user from public.users`);
  }
  
  // 4. Delete from auth.users (requires admin)
  const { error: deleteAuthUserError } = await supabase.auth.admin.deleteUser(authUser.id);
  
  if (deleteAuthUserError) {
    console.error("❌ Error deleting from auth.users:", deleteAuthUserError);
  } else {
    console.log(`✅ Deleted user from auth.users`);
  }
  
  console.log(`\n✅ Successfully deleted user and all related data for: ${email}`);
}
