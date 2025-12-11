#!/bin/bash
# ==============================================================================
# Set Staging Webhook Secret from .env file
# ==============================================================================
# Reads STAGING_STRIPE_WEBHOOK_SECRET from .env and sets it in Supabase
# 
# Usage:
#   1. Uncomment and set STAGING_STRIPE_WEBHOOK_SECRET in .env
#   2. Run: ./scripts/set_staging_webhook_from_env.sh
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Check if secret is set
if [ -z "$STAGING_STRIPE_WEBHOOK_SECRET" ]; then
    echo "❌ Error: STAGING_STRIPE_WEBHOOK_SECRET not found in .env"
    echo ""
    echo "Please:"
    echo "  1. Open .env file"
    echo "  2. Find the line: # STAGING_STRIPE_WEBHOOK_SECRET=whsec_..."
    echo "  3. Uncomment it and set your actual secret:"
    echo "     STAGING_STRIPE_WEBHOOK_SECRET=whsec_your_actual_secret"
    echo "  4. Run this script again"
    exit 1
fi

# Validate format (should start with whsec_)
if [[ ! "$STAGING_STRIPE_WEBHOOK_SECRET" =~ ^whsec_ ]]; then
    echo "⚠️  Warning: Secret doesn't start with 'whsec_'"
    echo "   Value: ${STAGING_STRIPE_WEBHOOK_SECRET:0:20}..."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Setting staging webhook secret in Supabase..."
echo "Secret: ${STAGING_STRIPE_WEBHOOK_SECRET:0:20}..."

# Link to staging
cd "$PROJECT_ROOT"
supabase link --project-ref auqujbppoytkeqdsgrbl > /dev/null 2>&1

# Set the secret
supabase secrets set STRIPE_WEBHOOK_SECRET="$STAGING_STRIPE_WEBHOOK_SECRET"

echo ""
echo "✅ Staging webhook secret set successfully!"
echo ""
echo "Verify with:"
echo "  supabase secrets list --project-ref auqujbppoytkeqdsgrbl | grep WEBHOOK"

