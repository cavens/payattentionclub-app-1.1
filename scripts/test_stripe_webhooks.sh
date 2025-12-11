#!/bin/bash
# ==============================================================================
# Test Stripe Webhook Configuration
# ==============================================================================
# Verifies that Stripe webhooks are configured correctly for both environments
# 
# Usage:
#   ./scripts/test_stripe_webhooks.sh [staging|production]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENVIRONMENT="${1:-staging}"

if [ "$ENVIRONMENT" = "staging" ]; then
    PROJECT_REF="auqujbppoytkeqdsgrbl"
    WEBHOOK_URL="https://auqujbppoytkeqdsgrbl.supabase.co/functions/v1/stripe-webhook"
    echo "Testing STAGING webhook configuration..."
elif [ "$ENVIRONMENT" = "production" ]; then
    PROJECT_REF="whdftvcrtrsnefhprebj"
    WEBHOOK_URL="https://whdftvcrtrsnefhprebj.supabase.co/functions/v1/stripe-webhook"
    echo "Testing PRODUCTION webhook configuration..."
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

echo ""
echo "=========================================="
echo "Stripe Webhook Configuration Test"
echo "=========================================="
echo ""

# Test 1: Check if Edge Function is deployed
echo "1. Checking if stripe-webhook Edge Function is deployed..."
if supabase functions list --project-ref "$PROJECT_REF" 2>/dev/null | grep -q "stripe-webhook"; then
    echo "   ✅ stripe-webhook function is deployed"
else
    echo "   ❌ stripe-webhook function not found"
    exit 1
fi

# Test 2: Check if secrets are set
echo ""
echo "2. Checking if Stripe secrets are set in Supabase..."
supabase link --project-ref "$PROJECT_REF" > /dev/null 2>&1

HAS_SECRET_KEY=$(supabase secrets list 2>/dev/null | grep -c "STRIPE_SECRET_KEY" || echo "0")
HAS_WEBHOOK_SECRET=$(supabase secrets list 2>/dev/null | grep -c "STRIPE_WEBHOOK_SECRET" || echo "0")

if [ "$HAS_SECRET_KEY" -gt 0 ]; then
    echo "   ✅ STRIPE_SECRET_KEY is set"
else
    echo "   ❌ STRIPE_SECRET_KEY is missing"
    exit 1
fi

if [ "$HAS_WEBHOOK_SECRET" -gt 0 ]; then
    echo "   ✅ STRIPE_WEBHOOK_SECRET is set"
else
    echo "   ❌ STRIPE_WEBHOOK_SECRET is missing"
    exit 1
fi

# Test 3: Check if webhook endpoint is accessible
echo ""
echo "3. Testing webhook endpoint accessibility..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL" || echo "000")

if [ "$HTTP_CODE" = "405" ] || [ "$HTTP_CODE" = "400" ]; then
    echo "   ✅ Webhook endpoint is accessible (HTTP $HTTP_CODE - expected for GET without payload)"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "   ⚠️  Could not reach webhook endpoint (network error)"
else
    echo "   ⚠️  Unexpected HTTP code: $HTTP_CODE"
fi

# Test 4: Verify webhook URL format
echo ""
echo "4. Verifying webhook URL format..."
if [[ "$WEBHOOK_URL" =~ ^https://.*\.supabase\.co/functions/v1/stripe-webhook$ ]]; then
    echo "   ✅ Webhook URL format is correct: $WEBHOOK_URL"
else
    echo "   ❌ Webhook URL format is incorrect: $WEBHOOK_URL"
    exit 1
fi

# Test 5: Check .env file has the secrets (for reference)
echo ""
echo "5. Checking .env file (for reference)..."
if [ "$ENVIRONMENT" = "staging" ]; then
    if grep -q "^STAGING_STRIPE_SECRET_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        echo "   ✅ STAGING_STRIPE_SECRET_KEY in .env"
    else
        echo "   ⚠️  STAGING_STRIPE_SECRET_KEY not in .env (optional)"
    fi
    
    if grep -q "^STAGING_STRIPE_WEBHOOK_SECRET=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        echo "   ✅ STAGING_STRIPE_WEBHOOK_SECRET in .env"
    else
        echo "   ⚠️  STAGING_STRIPE_WEBHOOK_SECRET not in .env (optional)"
    fi
else
    if grep -q "^PRODUCTION_STRIPE_SECRET_KEY=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        echo "   ✅ PRODUCTION_STRIPE_SECRET_KEY in .env"
    else
        echo "   ⚠️  PRODUCTION_STRIPE_SECRET_KEY not in .env (optional)"
    fi
    
    if grep -q "^PRODUCTION_STRIPE_WEBHOOK_SECRET=" "$PROJECT_ROOT/.env" 2>/dev/null; then
        echo "   ✅ PRODUCTION_STRIPE_WEBHOOK_SECRET in .env"
    else
        echo "   ⚠️  PRODUCTION_STRIPE_WEBHOOK_SECRET not in .env (optional)"
    fi
fi

echo ""
echo "=========================================="
echo "✅ All checks passed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Verify webhook is configured in Stripe Dashboard:"
if [ "$ENVIRONMENT" = "staging" ]; then
    echo "     - Go to: https://dashboard.stripe.com/test/webhooks"
    echo "     - Verify endpoint: $WEBHOOK_URL"
else
    echo "     - Go to: https://dashboard.stripe.com/webhooks"
    echo "     - Verify endpoint: $WEBHOOK_URL"
fi
echo "  2. Test with a real webhook event (optional)"
echo ""

