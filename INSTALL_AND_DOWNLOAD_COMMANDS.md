# Commands to Install Docker and Download Functions

Run these commands in your terminal, one at a time:

## Step 1: Install Docker Desktop

```bash
brew install --cask docker
```

(This will ask for your password - enter it when prompted)

## Step 2: Start Docker Desktop

After installation completes, start Docker:

```bash
open -a Docker
```

Wait for Docker to fully start (you'll see a whale icon in your menu bar - wait until it's steady, not animating)

## Step 3: Verify Docker is Running

Check that Docker is working:

```bash
docker ps
```

If this works without errors, Docker is ready!

## Step 4: Download Supabase Functions

Navigate to your project and download the functions:

```bash
cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
supabase functions download weekly-close
supabase functions download billing-status
supabase functions download stripe-webhook
supabase functions download admin-close-week-now
```

## Step 5: Verify Downloads

Check what was downloaded:

```bash
ls -la supabase/functions/
```

---

## Quick Copy-Paste (All at Once)

If you want to run them all:

```bash
# Install Docker
brew install --cask docker

# Start Docker (wait for it to be ready)
open -a Docker

# Wait a minute for Docker to start, then verify:
docker ps

# Download functions
cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
supabase functions download weekly-close
supabase functions download billing-status
supabase functions download stripe-webhook
supabase functions download admin-close-week-now

# Check results
ls -la supabase/functions/
```

---

## After Running These Commands

Once you've run these and the functions are downloaded, let me know and I'll:
1. Review the `weekly-close` function code
2. Compare it with what we need
3. Create the Step 1.3 implementation plan




