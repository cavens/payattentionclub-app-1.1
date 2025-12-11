#!/bin/bash
# ==============================================================================
# Send Test Stripe Webhook to Supabase
# ==============================================================================
# Sends a properly signed test webhook event to the stripe-webhook Edge Function
# 
# Usage:
#   ./scripts/send_test_webhook.sh [staging|production] [event_type]
#   ./scripts/send_test_webhook.sh staging payment_intent.succeeded
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-staging}"
EVENT_TYPE="${2:-payment_intent.succeeded}"

if [ "$ENVIRONMENT" = "staging" ]; then
    PROJECT_REF="auqujbppoytkeqdsgrbl"
    WEBHOOK_URL="https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook"
    echo "Sending test webhook to STAGING..."
elif [ "$ENVIRONMENT" = "production" ]; then
    PROJECT_REF="whdftvcrtrsnefhprebj"
    WEBHOOK_URL="https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook"
    echo "Sending test webhook to PRODUCTION..."
else
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Get webhook secret
if [ "$ENVIRONMENT" = "staging" ]; then
    WEBHOOK_SECRET="$STAGING_STRIPE_WEBHOOK_SECRET"
else
    WEBHOOK_SECRET="$PRODUCTION_STRIPE_WEBHOOK_SECRET"
fi

if [ -z "$WEBHOOK_SECRET" ]; then
    echo "❌ Error: Webhook secret not found in .env"
    exit 1
fi

echo "Event type: $EVENT_TYPE"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# Use Stripe CLI to generate a test event and get the payload
echo "Generating test event payload..."
PAYLOAD=$(stripe trigger "$EVENT_TYPE" --api-key "$STAGING_STRIPE_SECRET_KEY" 2>&1 | grep -A 100 "event:" | head -50 || echo "")

if [ -z "$PAYLOAD" ]; then
    echo "⚠️  Could not generate payload via Stripe CLI"
    echo ""
    echo "Alternative: Use Stripe Dashboard to send test webhook:"
    if [ "$ENVIRONMENT" = "staging" ]; then
        echo "  https://dashboard.stripe.com/test/webhooks"
    else
        echo "  https://dashboard.stripe.com/webhooks"
    fi
    exit 1
fi

echo "✅ Test webhook sent!"
echo ""
echo "Check Supabase logs:"
echo "  https://supabase.com/dashboard/project/$PROJECT_REF/functions/stripe-webhook/logs"

