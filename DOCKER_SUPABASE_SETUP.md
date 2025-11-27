# Docker Setup for Supabase CLI

## Do You Actually Need Docker?

**For linking to remote project and pulling functions: NO** ✅
- `supabase link` works without Docker
- `supabase functions pull` works without Docker
- You only need Docker for **local development** (`supabase start`)

**For local development: YES** ⚠️
- `supabase start` requires Docker
- Local testing requires Docker

---

## Option 1: Link to Remote (No Docker Needed) ✅ RECOMMENDED

You can link to your remote Supabase project without Docker:

```bash
cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1

# Link to remote project (no Docker needed)
supabase link --project-ref YOUR_PROJECT_REF

# Pull functions (no Docker needed)
supabase functions pull
```

**To get your project ref:**
1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to Project Settings → General
4. Copy the "Reference ID" (looks like `abcdefghijklmnop`)

---

## Option 2: Install Docker (If You Want Local Development)

If you want to run Supabase locally for testing, install Docker:

### macOS Installation

**Using Homebrew (Recommended):**
```bash
brew install --cask docker
```

**Or download directly:**
1. Go to https://www.docker.com/products/docker-desktop/
2. Download Docker Desktop for Mac
3. Install and start Docker Desktop

### Verify Installation

```bash
docker --version
docker ps
```

### Start Docker Desktop

- Open Docker Desktop app (from Applications)
- Wait for it to start (whale icon in menu bar should be steady)
- Verify: `docker ps` should work without errors

---

## Option 3: Link Without Docker (What We'll Do Now)

Since you just want to pull functions, let's link without Docker:

### Step 1: Get Your Project Ref

1. Go to Supabase Dashboard
2. Select your project
3. Settings → General → Reference ID

### Step 2: Link to Project

```bash
cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
supabase link --project-ref YOUR_PROJECT_REF
```

You'll be prompted for:
- **Database Password** (if you set one)
- **Git Branch** (usually `main` or leave empty)

### Step 3: Pull Functions

```bash
supabase functions pull
```

This downloads all Edge Functions to `supabase/functions/`

---

## Troubleshooting

### "Cannot connect to Docker daemon"

**If you see this error:**
- You're trying to run `supabase start` (local dev)
- For `supabase link`, this error shouldn't appear
- If it does, try: `supabase link --project-ref XXX --db-password YOUR_PASSWORD`

### "Project not found"

- Double-check your project ref
- Make sure you're logged in: `supabase login`
- Check you have access to the project

### "Authentication failed"

- Run `supabase login` first
- Make sure you're logged into the correct account

---

## Quick Start (No Docker)

```bash
# 1. Login (if not already)
supabase login

# 2. Link to remote project
supabase link --project-ref YOUR_PROJECT_REF

# 3. Pull functions
supabase functions pull

# 4. Check what you got
ls -la supabase/functions/
```

---

## When You DO Need Docker

You'll need Docker if you want to:
- Run Supabase locally (`supabase start`)
- Test Edge Functions locally (`supabase functions serve`)
- Run migrations locally
- Develop offline

For now, since you just want to inspect what's deployed, **you don't need Docker**.

---

## Next Steps

1. Get your project ref from Supabase Dashboard
2. Run `supabase link --project-ref XXX`
3. Run `supabase functions pull`
4. Then I can help inspect and create the implementation plan!




