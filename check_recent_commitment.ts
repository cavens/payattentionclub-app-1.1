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

console.log("🔍 Checking most recent commitment...\n");

const { data: commitments, error } = await supabase
  .from("commitments")
  .select("*")
  .order("created_at", { ascending: false })
  .limit(1);

if (error) {
  console.error("❌ Error:", error);
  Deno.exit(1);
}

if (!commitments || commitments.length === 0) {
  console.log("ℹ️  No commitments found");
  Deno.exit(0);
}

const commitment = commitments[0];

console.log("📝 Most Recent Commitment:");
console.log("=" .repeat(60));
console.log(`ID: ${commitment.id}`);
console.log(`User ID: ${commitment.user_id}`);
console.log(`Created: ${commitment.created_at}`);
console.log(`Status: ${commitment.status}`);
console.log(`Week End Date: ${commitment.week_start_date || "NULL"}`);
console.log(`Week End Timestamp: ${commitment.week_end_timestamp || "NULL"}`);
console.log(`Week Grace Expires At: ${commitment.week_grace_expires_at || "NULL"}`);
console.log(`Limit Minutes: ${commitment.limit_minutes || "NULL"}`);
console.log(`Penalty Per Minute Cents: ${commitment.penalty_per_minute_cents || "NULL"}`);
console.log(`Max Charge Cents: ${commitment.max_charge_cents || "NULL"}`);
console.log("");

// Check what rpc_get_week_status would return
console.log("🔍 Checking what rpc_get_week_status would return...\n");

const weekStartDate = commitment.week_start_date || new Date(commitment.created_at).toISOString().split("T")[0];

const { data: weekStatus, error: statusError } = await supabase.rpc("rpc_get_week_status", {
  p_week_start_date: weekStartDate
});

if (statusError) {
  console.error("❌ Error calling rpc_get_week_status:", statusError);
} else if (weekStatus && weekStatus.length > 0) {
  const status = weekStatus[0];
  console.log("📊 Week Status Response:");
  console.log("=" .repeat(60));
  console.log(`Limit Minutes: ${status.limit_minutes || "NULL"}`);
  console.log(`Penalty Per Minute Cents: ${status.penalty_per_minute_cents || "NULL"}`);
  console.log(`User Max Charge Cents: ${status.user_max_charge_cents || "NULL"}`);
  console.log(`Week End Date (timestamp): ${status.week_end_date || "NULL"}`);
  console.log(`Week Grace Expires At: ${status.week_grace_expires_at || "NULL"}`);
} else {
  console.log("ℹ️  No week status returned");
}
