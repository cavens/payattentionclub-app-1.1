#!/bin/bash

# Script to download Supabase Edge Functions after Docker is installed

set -e

echo "🚀 Downloading Supabase Edge Functions..."
echo ""

# Check if Docker is running
if ! docker ps > /dev/null 2>&1; then
    echo "❌ Docker is not running!"
    echo "Please start Docker Desktop and wait for it to be ready, then run this script again."
    exit 1
fi

echo "✅ Docker is running"
echo ""

cd "$(dirname "$0")"

# Create functions directory if it doesn't exist
mkdir -p supabase/functions

# Download each function
echo "📥 Downloading weekly-close..."
supabase functions download weekly-close || echo "⚠️  Failed to download weekly-close"

echo "📥 Downloading billing-status..."
supabase functions download billing-status || echo "⚠️  Failed to download billing-status"

echo "📥 Downloading stripe-webhook..."
supabase functions download stripe-webhook || echo "⚠️  Failed to download stripe-webhook"

echo "📥 Downloading admin-close-week-now..."
supabase functions download admin-close-week-now || echo "⚠️  Failed to download admin-close-week-now"

echo ""
echo "✅ Download complete!"
echo ""
echo "Downloaded functions:"
ls -la supabase/functions/ 2>/dev/null || echo "No functions directory found"




