#!/bin/bash
# ==============================================================================
# Set Stripe Webhook Secrets in Supabase
# ==============================================================================
# Sets the STRIPE_WEBHOOK_SECRET for staging or production environment
# 
# Usage:
#   ./scripts/set_webhook_secrets.sh staging whsec_xxx
#   ./scripts/set_webhook_secrets.sh production whsec_xxx
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1}"
WEBHOOK_SECRET="${2}"

if [ -z "$ENVIRONMENT" ] || [ -z "$WEBHOOK_SECRET" ]; then
    echo "Error: Missing arguments"
    echo ""
    echo "Usage:"
    echo "  ./scripts/set_webhook_secrets.sh [staging|production] [webhook_secret]"
    echo ""
    echo "Example:"
    echo "  ./scripts/set_webhook_secrets.sh staging whsec_1234567890abcdef"
    exit 1
fi

if [ "$ENVIRONMENT" = "staging" ]; then
    PROJECT_REF="auqujbppoytkeqdsgrbl"
    echo "Setting webhook secret for STAGING..."
elif [ "$ENVIRONMENT" = "production" ]; then
    PROJECT_REF="whdftvcrtrsnefhprebj"
    echo "Setting webhook secret for PRODUCTION..."
else
    echo "Error: Environment must be 'staging' or 'production'"
    exit 1
fi

# Link to the correct project
echo "Linking to $ENVIRONMENT project..."
cd "$PROJECT_ROOT"
supabase link --project-ref "$PROJECT_REF" > /dev/null 2>&1

# Set the secret
echo "Setting STRIPE_WEBHOOK_SECRET..."
supabase secrets set STRIPE_WEBHOOK_SECRET="$WEBHOOK_SECRET"

echo ""
echo "✅ Webhook secret set successfully for $ENVIRONMENT!"
echo ""
echo "Verify with:"
echo "  supabase secrets list --project-ref $PROJECT_REF"

