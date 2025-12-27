import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";

// Determine which Stripe key to use (test or production)
// Priority: STRIPE_SECRET_KEY_TEST (if exists) → STRIPE_SECRET_KEY (fallback)
const STRIPE_SECRET_KEY_TEST = Deno.env.get("STRIPE_SECRET_KEY_TEST");
const STRIPE_SECRET_KEY_PROD = Deno.env.get("STRIPE_SECRET_KEY");

const STRIPE_SECRET_KEY = STRIPE_SECRET_KEY_TEST || STRIPE_SECRET_KEY_PROD;

if (!STRIPE_SECRET_KEY) {
  console.error("ERROR: No Stripe secret key found. Please set STRIPE_SECRET_KEY_TEST or STRIPE_SECRET_KEY in Supabase secrets.");
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY");

const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: "2023-10-16"
});

Deno.serve(async (req) => {
  try {
    // 1) Auth: get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({
        error: "Missing Authorization header"
      }), {
        status: 401
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });

    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({
        error: "Not authenticated"
      }), {
        status: 401
      });
    }

    const userId = user.id;
    const userEmail = user.email ?? undefined;

    // 2) Fetch user row from public.users
    const { data: dbUser, error: dbUserError } = await supabase
      .from("users")
      .select("id, email, stripe_customer_id, has_active_payment_method")
      .eq("id", userId)
      .single();

    if (dbUserError) {
      console.error("Error fetching user row:", dbUserError);
      return new Response(JSON.stringify({
        error: "User row not found in public.users"
      }), {
        status: 400
      });
    }

    let stripeCustomerId = dbUser.stripe_customer_id;

    // 3) Create Stripe customer if missing
    if (!stripeCustomerId) {
      const customer = await stripe.customers.create({
        email: dbUser.email || userEmail,
        metadata: {
          supabase_user_id: userId
        }
      });
      stripeCustomerId = customer.id;

      const { error: updateCustomerError } = await supabase
        .from("users")
        .update({
          stripe_customer_id: stripeCustomerId
        })
        .eq("id", userId);

      if (updateCustomerError) {
        console.error("Error updating stripe_customer_id:", updateCustomerError);
        return new Response(JSON.stringify({
          error: "Failed to link Stripe customer"
        }), {
          status: 500
        });
      }
    }

    // 4) Check database flag first (source of truth)
    // IMPORTANT: We check the database flag first because it's only set to true
    // when a SetupIntent is actually confirmed (via rapid-service Edge Function).
    // Just having a payment method in Stripe doesn't mean payment setup is complete.
    // If has_active_payment_method is true, user has already completed payment setup
    if (dbUser.has_active_payment_method) {
      return new Response(JSON.stringify({
        has_payment_method: true,
        needs_setup_intent: false,
        setup_intent_client_secret: null,
        stripe_customer_id: stripeCustomerId
      }), {
        headers: {
          "Content-Type": "application/json"
        },
        status: 200
      });
    }

    // 5) Database flag is false - check Stripe for confirmed SetupIntents
    // Only consider payment setup complete if there's a confirmed SetupIntent.
    // This handles edge cases where the database flag might be out of sync.
    const setupIntents = await stripe.setupIntents.list({
      customer: stripeCustomerId,
      limit: 10
    });

    // Find a confirmed (succeeded) SetupIntent with a payment method attached
    const confirmedSetupIntent = setupIntents.data.find(
      (si) => si.status === "succeeded" && si.payment_method
    );

    // If we have a confirmed SetupIntent, update the database flag
    if (confirmedSetupIntent) {
      const { error: updatePmFlagError } = await supabase
        .from("users")
        .update({
          has_active_payment_method: true
        })
        .eq("id", userId);

      if (updatePmFlagError) {
        console.error("Error updating has_active_payment_method:", updatePmFlagError);
      } else {
        // Return that payment is set up
        return new Response(JSON.stringify({
          has_payment_method: true,
          needs_setup_intent: false,
          setup_intent_client_secret: null,
          stripe_customer_id: stripeCustomerId
        }), {
          headers: {
            "Content-Type": "application/json"
          },
          status: 200
        });
      }
    }

    // 6) Else: create SetupIntent and return client_secret
    const setupIntent = await stripe.setupIntents.create({
      customer: stripeCustomerId,
      automatic_payment_methods: {
        enabled: true
      }
    });

    return new Response(JSON.stringify({
      has_payment_method: false,
      needs_setup_intent: true,
      setup_intent_client_secret: setupIntent.client_secret,
      stripe_customer_id: stripeCustomerId
    }), {
      headers: {
        "Content-Type": "application/json"
      },
      status: 200
    });

  } catch (err) {
    console.error("billing-status error:", err);
    return new Response(JSON.stringify({
      error: "Internal server error"
    }), {
      status: 500
    });
  }
});