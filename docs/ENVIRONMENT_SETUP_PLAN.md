# PAC Environment Setup Plan — Staging & Production

---

## Overview

| Environment | Purpose | Supabase | Stripe | iOS Build |
|-------------|---------|----------|--------|-----------|
| **Staging** | Development & Testing | Separate project | Test mode (`sk_test_`) | Debug / TestFlight |
| **Production** | Real users | Separate project | Live mode (`sk_live_`) | App Store |

---

## Phase 1: Create Staging Supabase Project

**Time: ~15 minutes**

### Step 1.1: Create New Supabase Project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. Click **"New Project"**
3. Settings:
   - Name: `payattentionclub-staging` (or `pac-staging`)
   - Database password: Generate strong password, save it
   - Region: Same as production (for consistency)
4. Click **"Create new project"**
5. Wait for project to initialize (~2 minutes)

### Step 1.2: Note Down Staging Credentials

From the new project's **Settings → API**:

| Key | Where to Find | Save As |
|-----|---------------|---------|
| Project URL | `https://xxxxx.supabase.co` | `STAGING_SUPABASE_URL` |
| `anon` public key | API Keys section | `STAGING_SUPABASE_ANON_KEY` |
| `service_role` secret | API Keys section | `STAGING_SUPABASE_SERVICE_ROLE_KEY` |

Save these in a secure location (1Password, etc.)

---

## Phase 2: Clone Schema to Staging

**Time: ~30 minutes**

### Step 2.1: Export Production Schema

```bash
# From project root
supabase db dump --db-url "postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres" > schema_dump.sql
```

Or manually from Supabase Dashboard:
1. Go to **Production project → SQL Editor**
2. Run: `pg_dump` or export via **Database → Backups**

### Step 2.2: Apply Schema to Staging

1. Go to **Staging project → SQL Editor**
2. Paste and run the schema SQL
3. Verify tables exist: `commitments`, `daily_usage`, `user_week_penalties`, `weekly_pools`, `payments`, `users`

### Step 2.3: Deploy RPC Functions to Staging

For each file in `supabase/remote_rpcs/`:

1. Open the SQL file
2. Go to **Staging → SQL Editor**
3. Paste and run

Files to deploy:
- [ ] `rpc_create_commitment.sql`
- [ ] `rpc_sync_daily_usage.sql`
- [ ] `rpc_report_usage.sql`
- [ ] `rpc_get_week_status.sql`
- [ ] `rpc_setup_test_data.sql`
- [ ] `rpc_cleanup_test_data.sql`
- [ ] Any other RPCs

### Step 2.4: Deploy Edge Functions to Staging

```bash
# Link to staging project
supabase link --project-ref [STAGING_PROJECT_REF]

# Deploy all functions
supabase functions deploy billing-status
supabase functions deploy weekly-close
supabase functions deploy stripe-webhook
supabase functions deploy super-service
supabase functions deploy rapid-service
# ... any others
```

### Step 2.5: Set Edge Function Secrets (Staging)

```bash
supabase secrets set STRIPE_SECRET_KEY=sk_test_xxxxx
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_xxxxx
# ... any other secrets
```

---

## Phase 3: Update iOS Configuration

**Time: ~15 minutes**

### Step 3.1: Update `Config.swift`

**File:** `payattentionclub-app-1.1/Utilities/Config.swift`

```swift
// MARK: - Supabase Configuration
struct SupabaseConfig {
    
    // Staging (Development)
    private static let stagingURL = "https://[STAGING_REF].supabase.co"
    private static let stagingAnonKey = "eyJ..."
    
    // Production
    private static let productionURL = "https://[PRODUCTION_REF].supabase.co"
    private static let productionAnonKey = "eyJ..."
    
    static var projectURL: String {
        switch AppConfig.environment {
        case .staging: return stagingURL
        case .production: return productionURL
        }
    }
    
    static var anonKey: String {
        switch AppConfig.environment {
        case .staging: return stagingAnonKey
        case .production: return productionAnonKey
        }
    }
}

// MARK: - Stripe Configuration  
struct StripeConfig {
    
    private static let testPublishableKey = "pk_test_..."
    private static let livePublishableKey = "pk_live_..."
    
    static var publishableKey: String {
        switch AppConfig.environment {
        case .staging: return testPublishableKey
        case .production: return livePublishableKey
        }
    }
}
```

### Step 3.2: Create Xcode Build Configurations (Optional but Recommended)

1. In Xcode, select the project
2. Go to **Info** tab
3. Under **Configurations**, click **+**
4. Duplicate "Debug" → name it "Staging"
5. Duplicate "Release" → name it "Production"

Then in `Config.swift`:

```swift
enum Environment {
    case staging
    case production
    
    static var current: Environment {
        #if STAGING
        return .staging
        #elseif PRODUCTION
        return .production
        #else
        // Default: staging for debug, production for release
        #if DEBUG
        return .staging
        #else
        return .production
        #endif
        #endif
    }
}
```

---

## Phase 4: Update Environment Files

**Time: ~10 minutes**

### Step 4.1: Create `.env.staging`

```env
# Staging Environment
SUPABASE_URL=https://[STAGING_REF].supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...staging...
SUPABASE_ANON_KEY=eyJ...staging...
STRIPE_SECRET_KEY_TEST=sk_test_...
```

### Step 4.2: Create `.env.production`

```env
# Production Environment
SUPABASE_URL=https://[PRODUCTION_REF].supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...production...
SUPABASE_ANON_KEY=eyJ...production...
STRIPE_SECRET_KEY_TEST=sk_live_...
```

### Step 4.3: Update `.gitignore`

```gitignore
# Environment files
.env
.env.staging
.env.production
.env.local
```

### Step 4.4: Update Test Scripts

Modify `run_backend_tests.sh` to use staging by default:

```bash
# Default to staging for tests
ENV_FILE="${ENV_FILE:-.env.staging}"
source "$PROJECT_ROOT/$ENV_FILE"
```

---

## Phase 5: Stripe Webhook Configuration

**Time: ~15 minutes**

### Step 5.1: Create Staging Webhook

1. Go to [Stripe Dashboard → Webhooks](https://dashboard.stripe.com/webhooks)
2. Make sure you're in **Test Mode**
3. Click **"Add endpoint"**
4. URL: `https://[STAGING_REF].supabase.co/functions/v1/stripe-webhook`
5. Select events: `payment_intent.succeeded`, `payment_intent.failed`, etc.
6. Copy the **Signing secret** → save as `STAGING_STRIPE_WEBHOOK_SECRET`

### Step 5.2: Create Production Webhook

1. Switch to **Live Mode** in Stripe
2. Click **"Add endpoint"**
3. URL: `https://[PRODUCTION_REF].supabase.co/functions/v1/stripe-webhook`
4. Select same events
5. Copy the **Signing secret** → save as `PRODUCTION_STRIPE_WEBHOOK_SECRET`

### Step 5.3: Set Webhook Secrets in Supabase

**Staging:**
```bash
supabase link --project-ref [STAGING_REF]
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_staging_xxx
```

**Production:**
```bash
supabase link --project-ref [PRODUCTION_REF]
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_production_xxx
```

---

## Phase 6: Cron Jobs (Weekly Close)

**Time: ~10 minutes**

### Step 6.1: Set Up Cron in Staging

1. Go to **Staging Supabase → Database → Extensions**
2. Enable `pg_cron` if not enabled
3. Go to **SQL Editor** and create the cron job:

```sql
SELECT cron.schedule(
  'weekly-close-staging',
  '0 12 * * 1',  -- Every Monday at 12:00 PM UTC
  $$SELECT net.http_post(
    url := 'https://[STAGING_REF].supabase.co/functions/v1/weekly-close',
    headers := '{"Authorization": "Bearer [STAGING_SERVICE_ROLE_KEY]"}'::jsonb
  )$$
);
```

### Step 6.2: Set Up Cron in Production

Same as above, but with production URL and key.

---

## Phase 7: Verification Checklist

### Staging Environment

- [ ] Supabase project created
- [ ] Schema deployed (all tables)
- [ ] RPC functions deployed
- [ ] Edge functions deployed
- [ ] Edge function secrets set
- [ ] Stripe webhook configured (test mode)
- [ ] Cron job configured
- [ ] iOS app connects in Debug mode
- [ ] Test payment works

### Production Environment

- [ ] Using existing Supabase project
- [ ] Stripe webhook configured (live mode)
- [ ] Cron job configured
- [ ] iOS app connects in Release mode
- [ ] **DO NOT TEST WITH REAL MONEY UNTIL READY**

---

## Quick Reference: Switching Environments

### For Backend Tests

```bash
# Run against staging (default)
./run_all_tests.sh

# Run against production (careful!)
ENV_FILE=.env.production ./supabase/tests/run_backend_tests.sh
```

### For iOS Development

| Build | Environment | How |
|-------|-------------|-----|
| Debug (⌘R) | Staging | Automatic |
| Release (Archive) | Production | Automatic |

### For Supabase CLI

```bash
# Switch to staging
supabase link --project-ref [STAGING_REF]

# Switch to production
supabase link --project-ref [PRODUCTION_REF]
```

---

## Timeline Summary

| Phase | Task | Time |
|-------|------|------|
| 1 | Create Staging Supabase | 15 min |
| 2 | Clone Schema & Deploy | 30 min |
| 3 | Update iOS Config | 15 min |
| 4 | Environment Files | 10 min |
| 5 | Stripe Webhooks | 15 min |
| 6 | Cron Jobs | 10 min |
| 7 | Verification | 15 min |
| **Total** | | **~2 hours** |

---

## Notes

- **Never commit** `.env` files with real credentials
- **Test thoroughly** in staging before deploying to production
- **Keep schema in sync** — use migrations for changes
- **Document** any differences between environments

