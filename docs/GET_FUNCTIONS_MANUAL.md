# How to Get Supabase Functions Without Docker

## Option 1: Install Docker (Then Download Functions)

### Step 1: Install Docker Desktop

Run this in your terminal (it will ask for your password):

```bash
brew install --cask docker
```

### Step 2: Start Docker Desktop

1. Open **Applications** → **Docker.app**
2. Wait for Docker to start (whale icon in menu bar should be steady)
3. Verify: `docker ps` should work

### Step 3: Download Functions

```bash
cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
supabase functions download weekly-close
supabase functions download billing-status
supabase functions download stripe-webhook
supabase functions download admin-close-week-now
```

---

## Option 2: View Functions in Supabase Dashboard (No Docker Needed)

### Step 1: Go to Edge Functions

1. Open https://supabase.com/dashboard
2. Select your project: **Payattentionclub**
3. Go to **Edge Functions** in the left sidebar

### Step 2: View Function Code

For each function:
1. Click on the function name (e.g., `weekly-close`)
2. Click **"View source"** or **"Edit"** button
3. Copy the code and save it locally

### Step 3: Save Locally

Create the directory structure:
```bash
mkdir -p supabase/functions/weekly-close
mkdir -p supabase/functions/billing-status
mkdir -p supabase/functions/stripe-webhook
mkdir -p supabase/functions/admin-close-week-now
```

Then paste the code into `supabase/functions/[function-name]/index.ts`

---

## Option 3: Use Supabase API (Advanced)

You can also get functions via the API, but Dashboard is easier.

---

## Recommended: Option 2 (Dashboard)

Since you just need to inspect the code, **Option 2 (Dashboard)** is fastest:
- No Docker needed
- No installation
- Just copy/paste from browser

Once you have the `weekly-close` function code, I can:
1. Review it
2. Compare with what we need
3. Create Step 1.3 implementation plan

---

## Functions to Get

Priority order:
1. ✅ **weekly-close** - The main one we need!
2. ✅ **stripe-webhook** - Related to weekly close
3. ✅ **admin-close-week-now** - Dev tool
4. ✅ **billing-status** - Already have locally, but good to compare

---

## After Getting Functions

Once you have the files, let me know and I'll:
- Review the weekly-close implementation
- Check what's missing
- Create the Step 1.3 plan




