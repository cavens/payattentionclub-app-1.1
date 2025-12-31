# PII (Personally Identifiable Information) Inventory

**Last Updated**: 2025-12-31  
**Status**: ✅ Complete  
**Purpose**: Document all PII collected, stored, and processed by Pay Attention Club

---

## Executive Summary

This document inventories all personally identifiable information (PII) collected by the Pay Attention Club application. This inventory is required for:
- GDPR compliance
- Privacy policy development
- Data retention planning
- Security risk assessment
- User data deletion procedures

---

## PII Categories

### 1. Authentication & Identity Data

#### Email Address
- **Location**: `public.users.email`, `auth.users.email`
- **Source**: Apple Sign In (via Supabase Auth)
- **Type**: Pseudonymous (Apple Private Relay email, e.g., `abcd1234@privaterelay.appleid.com`)
- **Purpose**: 
  - User identification
  - Authentication
  - Communication (future: weekly summaries, reminders)
- **Retention**: While account is active
- **Deletion**: On account deletion, email is removed from `public.users` table
- **Access**: 
  - User can view their own email
  - Service role can access for support/admin purposes
  - Edge Functions can access for user operations
- **Encryption**: Encrypted at rest (Supabase default), encrypted in transit (HTTPS/TLS)

#### User ID (UUID)
- **Location**: `auth.users.id`, `public.users.id` (all tables reference this)
- **Source**: Supabase Auth (generated on sign-up)
- **Type**: Unique identifier
- **Purpose**: 
  - Primary key for all user data
  - Foreign key in all user-related tables
  - Authentication token claims
- **Retention**: While account is active
- **Deletion**: On account deletion, cascades to all related tables
- **Access**: 
  - User can see their own ID in JWT token
  - Service role can access for all operations
- **Encryption**: Encrypted at rest (Supabase default)

#### Apple ID Identifier
- **Location**: `auth.users.raw_user_meta_data` (Supabase Auth)
- **Source**: Apple Sign In
- **Type**: Pseudonymous identifier from Apple
- **Purpose**: Authentication provider linkage
- **Retention**: While account is active
- **Deletion**: On account deletion
- **Access**: Supabase Auth only (not exposed to application)
- **Encryption**: Encrypted at rest (Supabase default)

---

### 2. Payment & Financial Data

#### Stripe Customer ID
- **Location**: `public.users.stripe_customer_id`
- **Source**: Stripe API (created on first payment)
- **Type**: External identifier (`cus_xxxxx`)
- **Purpose**: 
  - Link user to Stripe customer record
  - Enable payment processing
  - Store payment methods
- **Retention**: While account is active (or until user requests deletion)
- **Deletion**: 
  - Removed from `public.users` on account deletion
  - Stripe customer record must be deleted separately via Stripe API
- **Access**: 
  - User cannot directly access (not exposed in app)
  - Service role can access for payment operations
- **Encryption**: Encrypted at rest (Supabase default)

#### Payment Method ID
- **Location**: `public.commitments.saved_payment_method_id`
- **Source**: Stripe API (created via Apple Pay or PaymentSheet)
- **Type**: External identifier (`pm_xxxxx`)
- **Purpose**: Store payment method for future charges
- **Retention**: While commitment is active (or until user removes payment method)
- **Deletion**: 
  - Removed from database on commitment deletion
  - Payment method must be deleted separately via Stripe API
- **Access**: 
  - User cannot directly access (not exposed in app)
  - Service role can access for payment operations
- **Encryption**: Encrypted at rest (Supabase default)

**Note**: Full payment card details are **NOT stored** in our database. All payment data is handled by Stripe and stored in Stripe's secure systems (PCI DSS compliant).

#### Payment Transaction Data
- **Location**: `public.payments` table
- **Source**: Stripe webhooks and Edge Functions
- **Type**: Transaction metadata
- **Fields**:
  - `stripe_payment_intent_id` (e.g., `pi_xxxxx`)
  - `stripe_charge_id` (e.g., `ch_xxxxx`)
  - `amount_cents` (penalty amount)
  - `status` (succeeded, failed, etc.)
  - `payment_type` (penalty, refund, etc.)
- **Purpose**: Track payment transactions for accounting and reconciliation
- **Retention**: 7 years (for tax/accounting compliance)
- **Deletion**: Not automatically deleted (retained for compliance)
- **Access**: 
  - User can view their own payment history
  - Service role can access for support/admin purposes
- **Encryption**: Encrypted at rest (Supabase default)

---

### 3. Usage & Behavioral Data

#### Screen Time Usage Data
- **Location**: `public.daily_usage` table
- **Source**: iOS DeviceActivity extension
- **Type**: Behavioral data
- **Fields**:
  - `used_minutes` (total screen time for the day)
  - `limit_minutes` (daily limit set by user)
  - `exceeded_minutes` (minutes over limit)
  - `penalty_cents` (calculated penalty)
  - `date` (date of usage)
  - `source` (e.g., `ios_app`, `estimated`)
- **Purpose**: 
  - Track user's screen time usage
  - Calculate penalties for exceeding limits
  - Enable commitment enforcement
- **Retention**: 90 days (after commitment ends)
- **Deletion**: 
  - Automatically deleted after 90 days
  - Can be deleted on user request
- **Access**: 
  - User can view their own usage data
  - Service role can access for support/admin purposes
- **Encryption**: Encrypted at rest (Supabase default)
- **Note**: App names and categories are stored in `apps_to_limit` JSONB field, but actual usage is aggregated (no individual app-level usage stored)

#### App Selection Data
- **Location**: `public.commitments.apps_to_limit` (JSONB)
- **Source**: iOS FamilyActivityPicker
- **Type**: Behavioral preference data
- **Fields**:
  - `app_bundle_ids` (array of app bundle identifiers)
  - `categories` (array of app category identifiers)
- **Purpose**: Define which apps/categories are limited in the commitment
- **Retention**: While commitment is active (or until user creates new commitment)
- **Deletion**: Removed when commitment is deleted
- **Access**: 
  - User can view their own app selections
  - Service role can access for support/admin purposes
- **Encryption**: Encrypted at rest (Supabase default)
- **Note**: App bundle IDs are opaque tokens from Apple's FamilyActivity framework (not human-readable app names)

#### Commitment Data
- **Location**: `public.commitments` table
- **Source**: User input during commitment creation
- **Type**: Preference/behavioral data
- **Fields**:
  - `limit_minutes` (daily screen time limit)
  - `penalty_per_minute_cents` (penalty rate)
  - `max_charge_cents` (maximum authorization amount)
  - `week_start_date`, `week_end_date` (commitment period)
  - `monitoring_status` (ok, revoked, etc.)
  - `autocharge_consent_at` (timestamp of consent)
- **Purpose**: Store user's commitment parameters
- **Retention**: While commitment is active + 90 days
- **Deletion**: 
  - Soft-deleted when commitment ends
  - Hard-deleted after 90 days
- **Access**: 
  - User can view their own commitments
  - Service role can access for support/admin purposes
- **Encryption**: Encrypted at rest (Supabase default)

---

### 4. Device & Technical Data

#### Device Activity Source
- **Location**: `public.daily_usage.source` field
- **Source**: iOS DeviceActivity extension
- **Type**: Technical metadata
- **Values**: `ios_app`, `estimated`, `extension`
- **Purpose**: Track data source for debugging and quality assurance
- **Retention**: Same as usage data (90 days)
- **Deletion**: Same as usage data
- **Access**: Same as usage data
- **Encryption**: Encrypted at rest (Supabase default)

#### Rate Limiting Data
- **Location**: `public.rate_limits` table
- **Source**: Edge Functions (rate limiting system)
- **Type**: Technical metadata
- **Fields**:
  - `key` (endpoint:user_id format)
  - `user_id` (reference to user)
  - `timestamp` (request timestamp)
- **Purpose**: Track API request rates for security
- **Retention**: 2x rate limit window (typically 2 minutes)
- **Deletion**: Automatically cleaned up after window expires
- **Access**: 
  - User can view their own rate limit entries (for debugging)
  - Service role can access for all operations
- **Encryption**: Encrypted at rest (Supabase default)

---

## Data Not Collected

The following data is **NOT collected** by Pay Attention Club:

1. **Real Names**: We do not collect user's real name
2. **Phone Numbers**: We do not collect phone numbers
3. **Physical Addresses**: We do not collect addresses
4. **Payment Card Details**: Full card numbers, CVV, expiration dates are handled by Stripe (PCI DSS compliant)
5. **Biometric Data**: No fingerprint, face ID, or other biometric data
6. **Location Data**: No GPS or location tracking
7. **Contacts**: No access to user's contacts
8. **Photos/Media**: No access to user's photos or media
9. **Individual App Usage**: We only store aggregated daily totals, not per-app usage
10. **Device Identifiers**: No IMEI, UDID, or other device identifiers (beyond what iOS provides for app functionality)

---

## Data Flow Summary

### Collection Points

1. **Sign Up**: Email (via Apple Sign In), User ID (generated)
2. **Commitment Creation**: App selections, limits, penalties
3. **Daily Usage**: Screen time data (via DeviceActivity extension)
4. **Payment**: Payment method ID (via Stripe), transaction metadata

### Storage Locations

1. **Supabase Database**: All user data stored in PostgreSQL (encrypted at rest)
2. **Supabase Auth**: Authentication data (email, user ID, Apple ID linkage)
3. **Stripe**: Payment methods, customer records, transaction details (PCI DSS compliant)

### Data Sharing

1. **Stripe**: Payment processing (required for service)
2. **Apple**: Authentication (via Sign in with Apple)
3. **No Third-Party Analytics**: We do not share data with analytics providers
4. **No Advertising**: We do not share data with advertising networks

---

## Data Retention Policy

### Active Users
- All data retained while account is active
- Usage data retained for 90 days after commitment ends

### Deleted Users
- User account deleted immediately on request
- Related data (commitments, usage) deleted via CASCADE
- Payment transaction data retained for 7 years (compliance)
- Stripe customer record must be deleted separately

### Automatic Cleanup
- Rate limit entries: 2 minutes (2x window)
- Old usage data: 90 days after commitment ends
- Test user data: Cleaned up periodically

---

## User Rights (GDPR Compliance)

### Right to Access
- Users can view all their data via the app
- Users can request data export (to be implemented)

### Right to Rectification
- Users can update their email (via Apple Sign In)
- Users can update commitment parameters (create new commitment)

### Right to Erasure
- Users can delete their account
- All user data will be deleted (except payment transactions for compliance)

### Right to Data Portability
- Users can request data export (to be implemented)
- Data will be provided in JSON format

### Right to Object
- Users can opt out of data collection by not using the service
- No marketing emails sent (currently)

---

## Security Measures

1. **Encryption at Rest**: All data encrypted by Supabase (AES-256)
2. **Encryption in Transit**: All connections use HTTPS/TLS
3. **Row Level Security (RLS)**: Users can only access their own data
4. **Access Controls**: Service role key only used server-side
5. **Input Validation**: All user inputs validated before storage
6. **Rate Limiting**: API endpoints rate-limited to prevent abuse

---

## Compliance Status

- ✅ **GDPR**: Data inventory complete, user rights documented
- ✅ **CCPA**: Similar rights to GDPR (to be verified)
- ✅ **PCI DSS**: Payment data handled by Stripe (Level 1 compliant)
- ⚠️ **Privacy Policy**: Needs to be created and published
- ⚠️ **Data Export**: Feature to be implemented
- ⚠️ **Data Deletion**: Automated deletion to be implemented

---

## Next Steps

1. ✅ Complete PII inventory (this document)
2. ⏳ Create privacy policy based on this inventory
3. ⏳ Implement automated data deletion
4. ⏳ Implement data export feature
5. ⏳ Set up data retention automation
6. ⏳ Regular review (quarterly) of PII inventory

---

**Document Owner**: Security Team  
**Review Frequency**: Quarterly  
**Last Review Date**: 2025-12-31

