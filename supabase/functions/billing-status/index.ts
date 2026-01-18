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
// Use environment-specific secret (STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY)
const SUPABASE_SECRET_KEY = 
  Deno.env.get("STAGING_SUPABASE_SECRET_KEY") || 
  Deno.env.get("PRODUCTION_SUPABASE_SECRET_KEY");

// Validate required environment variables
if (!SUPABASE_URL) {
  console.error("ERROR: SUPABASE_URL is not set in Edge Function environment variables");
}
if (!SUPABASE_SECRET_KEY) {
  console.error("ERROR: STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY must be set in Edge Function environment variables");
}

const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: "2023-10-16"
});

Deno.serve(async (req) => {
  try {
    console.log("billing-status: Request method:", req.method);
    console.log("billing-status: Request URL:", req.url);
    console.log("billing-status: SUPABASE_URL:", SUPABASE_URL ? "✅ Set" : "❌ Missing");
    console.log("billing-status: SUPABASE_SECRET_KEY:", SUPABASE_SECRET_KEY ? "✅ Set" : "❌ Missing");
    
    // Validate environment variables
    if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
      console.error("billing-status: Missing required environment variables");
      console.error("billing-status: SUPABASE_URL:", SUPABASE_URL ? "✅" : "❌");
      console.error("billing-status: SUPABASE_SECRET_KEY:", SUPABASE_SECRET_KEY ? "✅" : "❌");
      return new Response(JSON.stringify({
        error: "Internal server error",
        details: "Missing Supabase configuration. SUPABASE_URL and either STAGING_SUPABASE_SECRET_KEY or PRODUCTION_SUPABASE_SECRET_KEY must be set in Edge Function secrets."
      }), {
        status: 500,
        headers: { "Content-Type": "application/json" }
      });
    }
    
    // 1) Auth: get user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.error("billing-status: Missing Authorization header");
      return new Response(JSON.stringify({
        error: "Missing Authorization header"
      }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Create Supabase client with user's JWT for authentication
    const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });

    // Create separate service role client (without user JWT) for admin operations
    // This bypasses RLS policies when needed
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY);

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
    let { data: dbUser, error: dbUserError } = await supabase
      .from("users")
      .select("id, email, stripe_customer_id, has_active_payment_method")
      .eq("id", userId)
      .single();

    // If user doesn't exist, create it automatically using admin client (bypasses RLS)
    if (dbUserError) {
      // Check if error is "no rows found" (PGRST116 is PostgREST error code for no rows returned)
      if (dbUserError.code === 'PGRST116' || dbUserError.message?.includes('No rows found') || dbUserError.message?.includes('not found')) {
        console.log("billing-status: User not found in public.users, creating row automatically...");
        console.log("billing-status: User ID:", userId);
        console.log("billing-status: User email:", userEmail);
        
        // Create user row in public.users using admin client (bypasses RLS)
        const { data: newUser, error: createError } = await supabaseAdmin
          .from("users")
          .insert({
            id: userId,
            email: userEmail,
            stripe_customer_id: null,
            has_active_payment_method: false
          })
          .select("id, email, stripe_customer_id, has_active_payment_method")
          .single();
        
        if (createError) {
          console.error("billing-status: Error creating user row:", createError);
          return new Response(JSON.stringify({
            error: "Failed to create user row",
            details: createError.message
          }), {
            status: 500,
            headers: { "Content-Type": "application/json" }
          });
        }
        
        dbUser = newUser;
        console.log("billing-status: ✅ User row created successfully:", dbUser.id);
      } else {
        // Other error (not "not found")
        console.error("billing-status: Error fetching user row:", dbUserError);
        return new Response(JSON.stringify({
          error: "User row not found in public.users",
          details: dbUserError.message
        }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }
    }

    let stripeCustomerId = dbUser.stripe_customer_id;
    let customerJustCreated = false; // Track if customer was just created

    // 3) Create Stripe customer if missing
    if (!stripeCustomerId) {
      console.log("billing-status: Creating new Stripe customer...");
      const customer = await stripe.customers.create({
        email: dbUser.email || userEmail,
        metadata: {
          supabase_user_id: userId
        }
      });
      stripeCustomerId = customer.id;
      customerJustCreated = true; // Mark that customer was just created
      console.log("billing-status: ✅ New Stripe customer created:", stripeCustomerId);

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

    // 4) Parse request body to get authorization amount (optional)
    let authorizationAmountCents: number | null = null;
    try {
      // Try to get from query params first (GET request)
      const url = new URL(req.url);
      const queryAmount = url.searchParams.get("authorization_amount_cents");
      if (queryAmount) {
        const parsed = parseInt(queryAmount, 10);
        if (!isNaN(parsed) && parsed > 0) {
          authorizationAmountCents = parsed;
          console.log("billing-status: Got authorization amount from query:", authorizationAmountCents);
        }
      }
      
      // If not in query, try to get from body (POST request)
      if (!authorizationAmountCents && (req.method === "POST" || req.method === "PUT" || req.method === "PATCH")) {
        const contentType = req.headers.get("content-type") || "";
        console.log("billing-status: Content-Type for body:", contentType);
        if (contentType.includes("application/json")) {
          try {
            // Read body as text first to avoid consuming the stream
            const bodyText = await req.text();
            console.log("billing-status: Body text (first 200 chars):", bodyText.substring(0, 200));
            if (bodyText && bodyText.trim().length > 0) {
              const body = JSON.parse(bodyText);
              console.log("billing-status: Parsed body:", JSON.stringify(body));
              if (body && typeof body.authorization_amount_cents === "number") {
                authorizationAmountCents = body.authorization_amount_cents;
                console.log("billing-status: Authorization amount from body:", authorizationAmountCents);
              } else if (body && body.authorization_amount_cents !== undefined) {
                console.error("billing-status: authorization_amount_cents is not a number:", typeof body.authorization_amount_cents, body.authorization_amount_cents);
              }
            } else {
              console.log("billing-status: Body is empty");
            }
          } catch (jsonError) {
            console.error("billing-status: Error parsing JSON body:", jsonError);
            console.error("billing-status: JSON error details:", jsonError.message);
            // Body might be empty or invalid - that's okay, we'll handle it below
          }
        } else {
          console.log("billing-status: Content-Type is not application/json, skipping body parse");
        }
      }
    } catch (e) {
      // If body parsing fails, log error but continue
      console.error("billing-status: Error in body parsing block:", e);
      // Continue without authorization amount - will return error later if needed
    }

    // 5) Check database flag first (source of truth)
    // IMPORTANT: We check the database flag first because it's only set to true
    // when a PaymentIntent is actually confirmed and payment method saved (via rapid-service Edge Function).
    // Just having a payment method in Stripe doesn't mean payment setup is complete.
    // If has_active_payment_method is true, user has already completed payment setup
    if (dbUser.has_active_payment_method) {
      return new Response(JSON.stringify({
        has_payment_method: true,
        needs_payment_intent: false,
        payment_intent_client_secret: null,
        stripe_customer_id: stripeCustomerId
      }), {
        headers: {
          "Content-Type": "application/json"
        },
        status: 200
      });
    }

    // 6) Database flag is false - check Stripe for payment methods
    // CRITICAL: Skip payment method check if customer was just created
    // A newly created Stripe customer cannot have payment methods, so we should
    // proceed directly to PaymentIntent creation to avoid false positives
    if (customerJustCreated) {
      console.log("billing-status: Customer was just created, skipping payment method check and proceeding to PaymentIntent creation");
    } else {
      // Check if customer has any saved payment methods (from previous PaymentIntents with setup_future_usage)
      const paymentMethods = await stripe.paymentMethods.list({
        customer: stripeCustomerId,
        limit: 10
      });

      // If we have saved payment methods, update the database flag
      if (paymentMethods.data.length > 0) {
        console.log("billing-status: Found existing payment methods, updating database flag");
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
            needs_payment_intent: false,
            payment_intent_client_secret: null,
            stripe_customer_id: stripeCustomerId
          }), {
            headers: {
              "Content-Type": "application/json"
            },
            status: 200
          });
        }
      } else {
        console.log("billing-status: No existing payment methods found, proceeding to PaymentIntent creation");
      }
    }

    // 7) Else: create PaymentIntent and return client_secret
    // Authorization amount is required - if not provided, return error
    console.log("billing-status: Checking authorization amount:", authorizationAmountCents);
    if (!authorizationAmountCents || authorizationAmountCents <= 0) {
      console.error("billing-status: Missing or invalid authorization_amount_cents");
      return new Response(JSON.stringify({
        error: "authorization_amount_cents is required and must be greater than 0"
      }), {
        status: 400,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    
    console.log("billing-status: Creating PaymentIntent with amount:", authorizationAmountCents);
    console.log("billing-status: Stripe customer ID:", stripeCustomerId);
    console.log("billing-status: Stripe key configured:", !!STRIPE_SECRET_KEY);

    let paymentIntent;
    try {
      paymentIntent = await stripe.paymentIntents.create({
      amount: authorizationAmountCents,
      currency: "usd",
      customer: stripeCustomerId,
      capture_method: "manual", // Authorization hold (not immediate charge)
      setup_future_usage: "off_session", // Save payment method for future charges
      automatic_payment_methods: {
        enabled: true,
        allow_redirects: "never" // Prevent redirect-based payment methods (we only use Apple Pay)
      },
      metadata: {
        supabase_user_id: userId,
        purpose: "authorization_and_setup"
      }
    });
      console.log("billing-status: PaymentIntent created successfully:", paymentIntent.id);
    } catch (stripeError) {
      console.error("billing-status: Stripe API error:", stripeError);
      console.error("billing-status: Stripe error type:", stripeError.type);
      console.error("billing-status: Stripe error message:", stripeError.message);
      throw new Error(`Stripe API error: ${stripeError.message || String(stripeError)}`);
    }

    return new Response(JSON.stringify({
      has_payment_method: false,
      needs_payment_intent: true,
      payment_intent_client_secret: paymentIntent.client_secret,
      stripe_customer_id: stripeCustomerId
    }), {
      headers: {
        "Content-Type": "application/json"
      },
      status: 200
    });

  } catch (err) {
    console.error("billing-status error:", err);
    console.error("billing-status error stack:", err.stack);
    return new Response(JSON.stringify({
      error: "Internal server error",
      details: err.message || String(err)
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});