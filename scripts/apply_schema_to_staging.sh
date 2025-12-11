#!/bin/bash

# Script to apply schema to staging environment using psql
# Usage: ./scripts/apply_schema_to_staging.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_FILE="$PROJECT_ROOT/supabase/remote_schema_staging.sql"

# Load environment variables from .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a  # Auto-export all variables
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Check if schema file exists
if [ ! -f "$SCHEMA_FILE" ]; then
    echo "Error: Schema file not found: $SCHEMA_FILE"
    exit 1
fi

# Check for required environment variables
if [ -z "$STAGING_DB_URL" ]; then
    echo "Error: STAGING_DB_URL not set"
    echo ""
    echo "Please set it in your .env file or export it:"
    echo "  export STAGING_DB_URL='postgresql://postgres:[PASSWORD]@db.auqujbppoytkeqdsgrbl.supabase.co:5432/postgres'"
    echo ""
    echo "You can find the connection string in:"
    echo "  Staging Supabase → Settings → Database → Connection string → URI"
    exit 1
fi

# Add PostgreSQL to PATH if installed via Homebrew
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

# Check if psql is installed
PSQL_CMD=$(command -v psql || echo "/opt/homebrew/opt/postgresql@17/bin/psql")
if [ ! -f "$PSQL_CMD" ]; then
    echo "Error: psql is not installed"
    echo ""
    echo "Install PostgreSQL client tools:"
    echo "  macOS: brew install postgresql@17"
    echo "  Or apply schema manually via Supabase SQL Editor"
    exit 1
fi

echo "Applying schema to staging environment..."
echo "File: $SCHEMA_FILE"
echo ""

# Apply schema using psql (password should already be URL-encoded in .env if needed)
"$PSQL_CMD" "$STAGING_DB_URL" -f "$SCHEMA_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Schema applied successfully!"
else
    echo ""
    echo "❌ Schema application failed"
    exit 1
fi
