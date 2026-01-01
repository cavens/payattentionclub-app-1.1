/**
 * Reset My User - Completely delete a user from Supabase
 * 
 * This script deletes a user and ALL their data, allowing you to 
 * start fresh with Apple Sign-In on your device.
 * 
 * Usage:
 *   deno run --allow-all reset_my_user.ts                    # Interactive
 *   deno run --allow-all reset_my_user.ts --force            # Skip confirmation
 *   deno run --allow-all reset_my_user.ts other@email.com    # Different email
 */

import "https://deno.land/std@0.177.0/dotenv/load.ts";
import Stripe from "https://esm.sh/stripe@14.5.0";

// Default email - your Apple Sign-In relay email
const DEFAULT_EMAIL = "jef@cavens.io";

async function main() {
  // Check for --force flag
  const forceMode = Deno.args.includes("--force");
  
  // Get email from command line (ignore --force flag) or use default
  const emailArg = Deno.args.find(arg => !arg.startsWith("--"));
  const email = emailArg || DEFAULT_EMAIL;
  
  console.log("🗑️  Reset My User");
  console.log("================");
  console.log(`Email: ${email}`);
  console.log("");

  // Load environment variables
  // Support environment-specific variables with fallback
  const env = Deno.env.get("TEST_ENVIRONMENT") || "staging";
  const isStaging = env === "staging";
  
  const supabaseUrl = isStaging
    ? Deno.env.get("STAGING_SUPABASE_URL") || Deno.env.get("SUPABASE_URL")
    : Deno.env.get("PRODUCTION_SUPABASE_URL") || Deno.env.get("SUPABASE_URL");
    
  const serviceRoleKey = isStaging
    ? Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    : Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // Get Stripe key (test key preferred, fallback to production)
  const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY_TEST") || Deno.env.get("STRIPE_SECRET_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("❌ Missing environment variables!");
    console.error("   Make sure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set in .env");
    Deno.exit(1);
  }

  // Initialize Stripe client if key is available
  const stripe = stripeSecretKey ? new Stripe(stripeSecretKey, {
    apiVersion: "2023-10-16",
  }) : null;

  // Confirm before proceeding (skip if --force)
  console.log("⚠️  WARNING: This will PERMANENTLY delete:");
  console.log("   - Stripe customer and all payment methods");
  console.log("   - User from auth.users (Apple Sign-In will create new user)");
  console.log("   - User from public.users");
  console.log("   - All commitments");
  console.log("   - All daily_usage records");
  console.log("   - All user_week_penalties");
  console.log("   - All payments");
  console.log("");
  
  if (!forceMode) {
    const confirm = prompt("Type 'DELETE' to confirm: ");
    if (confirm !== "DELETE") {
      console.log("❌ Cancelled");
      Deno.exit(0);
    }
  } else {
    console.log("🔓 Force mode - skipping confirmation");
  }

  console.log("");
  console.log("🔄 Deleting user...");

  try {
    // Step 1: Get user's stripe_customer_id before deletion
    console.log("Step 1: Looking up user's Stripe customer ID...");
    const userLookupResponse = await fetch(`${supabaseUrl}/rest/v1/users?email=eq.${encodeURIComponent(email)}&select=id,stripe_customer_id`, {
      method: "GET",
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
    });

    let stripeCustomerId: string | null = null;
    let userId: string | null = null;

    if (userLookupResponse.ok) {
      const users = await userLookupResponse.json();
      if (users && users.length > 0) {
        userId = users[0].id;
        stripeCustomerId = users[0].stripe_customer_id;
        if (stripeCustomerId) {
          console.log(`   Found Stripe customer ID: ${stripeCustomerId}`);
        } else {
          console.log("   No Stripe customer ID found");
        }
      }
    }

    // Step 2: Delete Stripe customer and payment methods (if exists)
    if (stripeCustomerId && !stripeCustomerId.startsWith("cus_test_")) {
      if (!stripe) {
        console.log("Step 2: ⚠️  Stripe key not configured - skipping Stripe deletion");
        console.log("   (Set STRIPE_SECRET_KEY_TEST or STRIPE_SECRET_KEY in .env to enable)");
      } else {
        console.log("Step 2: Deleting Stripe customer and payment methods...");
        try {
          // 2a. Delete all payment methods
          const paymentMethods = await stripe.paymentMethods.list({
            customer: stripeCustomerId,
            limit: 100,
          });

          let deletedPaymentMethods = 0;
          for (const pm of paymentMethods.data) {
            try {
              await stripe.paymentMethods.detach(pm.id);
              deletedPaymentMethods++;
            } catch (error: any) {
              console.error(`   ⚠️  Warning: Failed to detach payment method ${pm.id}: ${error.message}`);
            }
          }

          // 2b. Cancel any pending SetupIntents (optional cleanup)
          try {
            const setupIntents = await stripe.setupIntents.list({
              customer: stripeCustomerId,
              limit: 100,
            });
            for (const si of setupIntents.data) {
              if (si.status === "requires_payment_method" || si.status === "requires_confirmation") {
                try {
                  await stripe.setupIntents.cancel(si.id);
                } catch {
                  // Ignore - SetupIntent might already be cancelled
                }
              }
            }
          } catch (error) {
            // Ignore SetupIntent cleanup errors
          }

          // 2c. Delete the Stripe customer
          try {
            await stripe.customers.del(stripeCustomerId);
            console.log(`   ✅ Deleted ${deletedPaymentMethods} payment method(s)`);
            console.log(`   ✅ Deleted Stripe customer: ${stripeCustomerId}`);
          } catch (error: any) {
            if (error.code === "resource_missing") {
              console.log(`   ⚠️  Stripe customer ${stripeCustomerId} not found (may already be deleted)`);
            } else {
              throw error;
            }
          }
        } catch (error: any) {
          console.error(`   ⚠️  Warning: Failed to delete Stripe customer: ${error.message}`);
          console.error("   Continuing with database deletion...");
        }
      }
    } else if (stripeCustomerId?.startsWith("cus_test_")) {
      console.log("Step 2: Skipping fake test customer ID");
    } else {
      console.log("Step 2: No Stripe customer to delete");
    }

    // Step 3: Delete user from database
    console.log("Step 3: Deleting user from database...");
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/rpc_delete_user_completely`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        p_email: email,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`❌ HTTP Error ${response.status}: ${errorText}`);
      Deno.exit(1);
    }

    const result = await response.json();
    
    if (result.success) {
      console.log("✅ User deleted successfully!");
      console.log("");
      console.log("Deleted from database:");
      console.log(`   - Payments: ${result.deleted.payments}`);
      console.log(`   - Daily usage: ${result.deleted.daily_usage}`);
      console.log(`   - Week penalties: ${result.deleted.user_week_penalties}`);
      console.log(`   - Commitments: ${result.deleted.commitments}`);
      console.log(`   - Public user: ${result.deleted.public_users}`);
      console.log(`   - Auth user: ${result.deleted.auth_users}`);
      if (stripeCustomerId && !stripeCustomerId.startsWith("cus_test_")) {
        console.log(`   - Stripe customer: ${stripeCustomerId}`);
      }
      console.log("");
      console.log("🎉 You can now sign in fresh with Apple Sign-In!");
    } else {
      console.error(`❌ Error: ${result.error}`);
      Deno.exit(1);
    }
  } catch (error) {
    console.error(`❌ Error: ${error.message}`);
    Deno.exit(1);
  }
}

main();

