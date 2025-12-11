// supabase/functions/stripe-webhook/index.ts

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@12.8.0?target=deno";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const stripe = new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: "2023-10-16" as any,
});

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  let event;

  try {
    // 1) Stripe sends raw body + signature header
    const signature = req.headers.get("stripe-signature");
    if (!signature) {
      console.error("Missing stripe-signature header");
      return new Response("Missing stripe-signature", { status: 400 });
    }

    const body = await req.text();

    try {
      event = stripe.webhooks.constructEvent(
        body,
        signature,
        STRIPE_WEBHOOK_SECRET
      );
    } catch (err) {
      console.error("Webhook signature verification failed:", err);
      return new Response("Invalid signature", { status: 400 });
    }

    // 2) Handle different event types
    const eventType = event.type;
    console.log("Stripe webhook event:", eventType);

    if (eventType === "payment_intent.succeeded") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      const paymentIntentId = paymentIntent.id;

      // Find the matching payments row
      const { data: paymentRow, error: paymentErr } = await supabase
        .from("payments")
        .select("id, user_id, week_start_date")
        .eq("stripe_payment_intent_id", paymentIntentId)
        .maybeSingle();

      if (paymentErr) {
        console.error("Error fetching payment row:", paymentErr);
        // We still return 200 so Stripe doesn't keep retrying forever.
        return new Response("OK", { status: 200 });
      }

      if (!paymentRow) {
        console.warn(
          "No matching payment row found for payment_intent:",
          paymentIntentId
        );
        return new Response("OK", { status: 200 });
      }

      // Update payment status
      const { error: updatePaymentErr } = await supabase
        .from("payments")
        .update({ status: "succeeded" })
        .eq("id", paymentRow.id);

      if (updatePaymentErr) {
        console.error("Error updating payment status:", updatePaymentErr);
      }

      // Update user_week_penalties status
      const { error: updatePenaltyErr } = await supabase
        .from("user_week_penalties")
        .update({ status: "paid" })
        .eq("user_id", paymentRow.user_id)
        .eq("week_start_date", paymentRow.week_start_date);

      if (updatePenaltyErr) {
        console.error("Error updating user_week_penalties status:", updatePenaltyErr);
      }

    } else if (eventType === "payment_intent.payment_failed") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      const paymentIntentId = paymentIntent.id;

      const { data: paymentRow, error: paymentErr } = await supabase
        .from("payments")
        .select("id, user_id, week_start_date")
        .eq("stripe_payment_intent_id", paymentIntentId)
        .maybeSingle();

      if (paymentErr) {
        console.error("Error fetching payment row (failed):", paymentErr);
        return new Response("OK", { status: 200 });
      }

      if (!paymentRow) {
        console.warn(
          "No matching payment row found for failed payment_intent:",
          paymentIntentId
        );
        return new Response("OK", { status: 200 });
      }

      // Update payment status
      const { error: updatePaymentErr } = await supabase
        .from("payments")
        .update({ status: "failed" })
        .eq("id", paymentRow.id);

      if (updatePaymentErr) {
        console.error("Error updating failed payment status:", updatePaymentErr);
      }

      // Update user_week_penalties status
      const { error: updatePenaltyErr } = await supabase
        .from("user_week_penalties")
        .update({ status: "failed" })
        .eq("user_id", paymentRow.user_id)
        .eq("week_start_date", paymentRow.week_start_date);

      if (updatePenaltyErr) {
        console.error("Error updating user_week_penalties status to failed:", updatePenaltyErr);
      }
    } else {
      // For now, ignore all other event types
      console.log("Unhandled Stripe event type:", eventType);
    }

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("Unhandled error in stripe-webhook:", err);
    return new Response("Webhook handler error", { status: 500 });
  }
});