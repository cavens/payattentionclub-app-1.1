#!/bin/bash
# ==============================================================================
# Copy Secrets from bright-service to quick-handler
# ==============================================================================
# This script helps copy Stripe secrets from bright-service to quick-handler
# Since we can't read secrets via CLI, this provides instructions
# ==============================================================================

PROJECT_REF="${SUPABASE_PROJECT_REF:-auqujbppoytkeqdsgrbl}"

echo "=========================================="
echo "Copy Secrets from bright-service"
echo "=========================================="
echo ""
echo "Since Supabase CLI cannot read secrets, you need to:"
echo ""
echo "Option 1: Copy from Dashboard (Recommended)"
echo "  1. Go to: https://supabase.com/dashboard/project/$PROJECT_REF/functions/bright-service/settings"
echo "  2. Find STRIPE_SECRET_KEY_TEST or STRIPE_SECRET_KEY"
echo "  3. Copy the value"
echo "  4. Go to: https://supabase.com/dashboard/project/$PROJECT_REF/functions/quick-handler/settings"
echo "  5. Add the same secret with the same name"
echo ""
echo "Option 2: Set via CLI (if you know the value)"
echo "  supabase secrets set STRIPE_SECRET_KEY_TEST=\"YOUR_KEY_HERE\" --project-ref $PROJECT_REF"
echo ""
echo "The quick-handler function needs:"
echo "  - STRIPE_SECRET_KEY_TEST (preferred)"
echo "  - OR STRIPE_SECRET_KEY (fallback)"
echo ""
echo "This should match what bright-service has set."
echo ""

