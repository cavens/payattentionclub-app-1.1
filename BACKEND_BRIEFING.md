# **PAC Backend – Step-by-Step Implementation Guide**

A complete, structured plan for implementing the PayAttentionClub backend.

---

## **Assumptions**

* **Backend:** Supabase (Postgres + Auth + Edge Functions)
* **Payments:** Stripe
* **App:** iOS PAC app

This plan is optimized for getting **v1 live as fast as possible**.

---

# **Phase 0 – Prerequisites**

### **0.1 Accounts & Access**

* Supabase account created
* Stripe account (Test Mode enabled)
* Apple Developer account (Sign in with Apple + App Store)

### **0.2 Environments**

* Start with **one Supabase project → staging**
* Later, clone to production

---

# **Phase 1 – Create Supabase Project**

### **1.1 Create Project**

* Supabase dashboard → **New project**
* Choose region (US recommended)
* Save:
  * **Project URL**
  * **anon key** (iOS app)
  * **service_role key** (Edge Functions only)

### **1.2 Basic Settings**

* Auth enabled (default)
* Row Level Security enabled (default)

---

# **Phase 2 – Create Database Schema**

Use Supabase SQL Editor.

### **2.1 Create Tables**

* `users`
* `commitments`
* `daily_usage`
* `user_week_penalties`
* `weekly_pools`
* `payments`
* `usage_adjustments`

**Structural notes:**

* **users:** identity + Stripe customer ID + flags
* **commitments:** weekly limits, penalties, apps, monitoring state
* **daily_usage:** daily reports
* **user_week_penalties:** weekly totals per user
* **weekly_pools:** global totals + Instagram info
* **payments:** Stripe mapping table
* **usage_adjustments:** future feature (bonus time, etc.)

### **2.2 Indexes & Constraints**

* Unique: `(user_id, date, commitment_id)` on `daily_usage`
* Unique: `(user_id, week_start_date)` on `user_week_penalties`
* Unique: `week_start_date` on `weekly_pools`

---

# **Phase 3 – Supabase Auth (Sign in with Apple)**

### **3.1 Configure Apple Provider**

In Supabase → Authentication → Providers → Apple:

* Team ID
* Services ID
* Key ID
* Private Key (.p8)
* Redirect URL (Supabase shows this)

### **3.2 Mirror auth.users → users**

Create a trigger:

* On insert into `auth.users` → insert into `public.users`
  * `id = auth.users.id`
  * `email = metadata`

Gives you one unified `user_id` to use across the backend.

---

# **Phase 4 – Stripe Setup & Secrets**

### **4.1 Get Stripe Keys**

From Stripe → Developers → API Keys:

* Publishable key (`pk_...`)
* Secret key (`sk_...`)

### **4.2 Store in Supabase**

Supabase → Project Settings → Secrets:

* `STRIPE_SECRET_KEY`
* (Later) `STRIPE_WEBHOOK_SECRET`
* Optional: `STRIPE_PUBLISHABLE_KEY`

### **4.3 Prepare Webhook Endpoint**

Plan URL:

```
https://<project>.functions.supabase.co/stripe-webhook
```

In Stripe:

* Add webhook
* Events:
  * `payment_intent.succeeded`
  * `payment_intent.payment_failed`
* Save webhook secret into Supabase as `STRIPE_WEBHOOK_SECRET`

---

# **Phase 5 – Core RPC Functions (DB Layer)**

## **5.1 `rpc_create_commitment`**

**Purpose:** Create weekly commitment.

**Inputs:**

* `week_start_date`
* `limit_minutes`
* `penalty_per_minute_cents`
* `apps_to_limit`

**Process:**

1. Validate `auth.uid()`
2. Require `has_active_payment_method = true`
3. Compute:
   * days remaining
   * risk factor
   * `max_charge_cents`
4. Insert into `commitments`
5. Ensure `weekly_pools` exists
6. Return commitment

---

## **5.2 `rpc_report_usage`**

**Purpose:** Store daily usage and recompute penalties.

**Inputs:**

* `date`
* `week_start_date`
* `used_minutes`

**Process:**

* Resolve `auth.uid()` and commitment
* Compute exceeded + penalty
* Upsert into `daily_usage`
* Recompute `user_week_penalties`
* Recompute `weekly_pools`

Returns:

* daily penalty
* weekly total
* pool total

---

## **5.3 `rpc_update_monitoring_status`**

**Purpose:** Update Screen Time monitoring state.

**Inputs:**

* `commitment_id`
* `monitoring_status` (`ok` or `revoked`)

**Process:**

* Check user ownership
* Update
* If revoked → set `monitoring_revoked_at`

---

## **5.4 `rpc_get_week_status`**

**Purpose:** Provide weekly bulletin data.

**Returns:**

* User totals
* Max charge
* Weekly pool totals
* Instagram URL + image

---

# **Phase 6 – Edge Functions (Billing & Cron)**

## **6.1 billing-status**

Use when user presses **Commit**.

**Process:**

* Auth → get user
* If missing → create Stripe customer
* Check for payment method
* If none → create SetupIntent and return `client_secret`
* After iOS completes, mark `has_active_payment_method = true`

---

## **6.2 weekly-close**

Runs **every Monday 12:00 EST**.

**Process:**

1. Determine last week
2. Insert estimated rows for revoked monitoring
3. Recompute all totals
4. For each user with balance:
   * Create Stripe PaymentIntent (off‑session)
   * Insert into `payments`
   * Mark status = `charge_initiated`
5. Close weekly pool

---

## **6.3 Cron Setup**

* Configure a Supabase Scheduled Function to run `weekly-close` weekly at **12:00 EST**.

---

# **Phase 7 – Stripe Webhook**

## **7.1 stripe-webhook**

**Process:**

* Verify `STRIPE_WEBHOOK_SECRET`
* On `payment_intent.succeeded`:
  * Mark payment = succeeded
  * Mark user penalties = paid
* On `payment_intent.payment_failed`:
  * Mark payment = failed
  * Mark user penalties = failed

---

# **Phase 8 – Security & RLS**

## **8.1 RLS Policies**

For user-owned tables:

* SELECT → `auth.uid() = user_id`
* INSERT/UPDATE → `auth.uid() = user_id`

For `weekly_pools`:

* Allow SELECT for all authenticated users

## **8.2 Test Isolation**

* Create second test account
* Ensure no cross-user visibility

---

# **Phase 9 – Testing & Fast-Forward Tools**

## **9.1 is_test_user**

* Mark your staging user as `is_test_user = true`

## **9.2 admin_close_week_now**

* Staging-only Edge Function
* Runs weekly-close immediately
* Add hidden iOS button to trigger it

---

# **Phase 10 – iOS Integration**

## **10.1 BackendClient.swift**

Implement calls to:

* `billing-status`
* `rpc_create_commitment`
* `rpc_report_usage`
* `rpc_update_monitoring_status`
* `rpc_get_week_status`

## **10.2 Screen Logic**

### **Setup Screen**

* Collect limit/penalty/apps → store locally

### **Commit Action**

* Ensure Sign in with Apple
* Call `billing-status` → SetupIntent if needed
* Call `rpc_create_commitment`
* Show `max_charge_cents`

### **During Week**

* Periodically call `rpc_report_usage`
* On Screen Time revocation → `rpc_update_monitoring_status`

### **Bulletin Screen**

* Call `rpc_get_week_status`
* Display:
  * Weekly total
  * Max charge
  * Pool amount
  * IG link + image

---

## **10.3 Dev-only: Admin Close Week Now (iOS)**

* Add a hidden **dev-only control** in the app that is only visible for test builds or when the logged-in user is marked as `is_test_user = true`.

  * Examples:
    * A hidden "Dev" screen accessible via a secret gesture (e.g., tapping the logo 7×).
    * A debug section only compiled in `#if DEBUG` builds.

* On tap of **"Dev: Close week now"**:

  1. Retrieve the current Supabase **access token** from your auth layer.

  2. Send a `POST` request to:
     * `https://<PROJECT-REF>.functions.supabase.co/admin-close-week-now`

  3. Include headers:
     * `Authorization: Bearer <access_token>`
     * `apikey: <SUPABASE_ANON_KEY>` (if you're using the Supabase client)
     * `Content-Type: application/json`

  4. Body can simply be:
     ```json
     {}
     ```

  5. On success (`200 OK`), optionally:
     * Show a small toast/snackbar: *"Dev: weekly close triggered"*
     * Immediately refresh the **Bulletin** screen by calling `rpc_get_week_status` so you can see the updated penalties and pool.

* This allows you to simulate **Monday settlement** and the full Stripe/webhook flow in minutes, without waiting for real time to pass.

---

If you want next steps, I can generate:

* Full SQL schema
* All Edge Function templates
* A complete `BackendClient.swift` implementation
