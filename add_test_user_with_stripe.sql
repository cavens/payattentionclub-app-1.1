-- Add a test user with a Stripe customer ID for testing weekly-close
-- This user will have a valid Stripe customer ID so payments can be processed

-- First, create a Stripe customer (you'll need to do this in Stripe Dashboard or via API)
-- Then update this script with the real customer ID

-- Option 1: Update existing test user with Stripe customer ID
-- Replace 'USER_EMAIL' with your test user's email
UPDATE users
SET 
  stripe_customer_id = 'cus_TEST_CUSTOMER_ID',  -- Replace with real Stripe customer ID
  has_active_payment_method = true,
  is_test_user = true
WHERE email = 'USER_EMAIL@example.com';

-- Option 2: Insert a new test user with Stripe customer ID
-- First create the auth user, then insert into public.users
-- (This assumes you have a way to create the auth user)

-- Insert into public.users (assuming auth user already exists)
INSERT INTO public.users (
  id,
  email,
  stripe_customer_id,
  has_active_payment_method,
  is_test_user,
  created_at,
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,  -- Replace with real auth user ID
  'test-with-stripe@example.com',
  'cus_TEST_CUSTOMER_ID',  -- Replace with real Stripe customer ID from Stripe
  true,
  true,
  NOW(),
  NOW()
)
ON CONFLICT (id) DO UPDATE SET
  stripe_customer_id = EXCLUDED.stripe_customer_id,
  has_active_payment_method = EXCLUDED.has_active_payment_method,
  is_test_user = EXCLUDED.is_test_user;

-- To get a real Stripe customer ID for testing:
-- 1. Go to Stripe Dashboard → Customers → Create customer
-- 2. Or use Stripe API:
--    curl https://api.stripe.com/v1/customers \
--      -u sk_test_YOUR_KEY: \
--      -d "email=test@example.com" \
--      -d "name=Test User"
-- 3. Copy the "id" field (starts with cus_)
-- 4. Update the script above with that ID


