# Apple Identifiers Reference

Use this checklist when rotating bundle IDs, App Groups, merchant IDs, URL schemes, or provisioning assets in the Apple Developer portal.

---

## 1. Bundle Identifiers & Targets
| Target | File(s) | Identifier |
| --- | --- | --- |
| Main app | `payattentionclub-app-1.1.xcodeproj/project.pbxproj` (build settings) | `com.payattentionclub.payattentionclub-app-1-1` |
| DeviceActivity monitor extension | same `.pbxproj` | `com.payattentionclub.payattentionclub-app-1-1.DeviceActivityMonitorExtension` |
| Deep-link URL scheme | `payattentionclub-app-1-1-Info.plist` | `com.payattentionclub.app.deeplink` |

**If changed:** update Xcode target settings, regenerate App IDs/profiles in Apple portal, and re-export provisioning profiles.

---

## 2. App Group Identifier
| File | Reference |
| --- | --- |
| App + extension entitlements (`*.entitlements`) | `<string>group.com.payattentionclub2.0.app</string>` |
| Swift code (`AppModel`, `UsageTracker`, `MonitoringManager`, extensions, etc.) | `UserDefaults(suiteName: "group.com.payattentionclub2.0.app")` |
| Docs (`ARCHITECTURE.md`, `SETUP_INSTRUCTIONS.md`, `EXTENSION_*`) | Reference same string |

**If changed:** update entitlements + every `UserDefaults(suiteName:)` string, add group to both targets in Apple portal, regenerate provisioning profiles.

---

## 3. Merchant ID (Apple Pay / Stripe)
| File | Identifier |
| --- | --- |
| Entitlements | `<string>merchant.com.payattentionclub2.0.app</string>` |
| `StripePaymentManager.swift` | `let merchantId = "merchant.com.payattentionclub2.0.app"` |

**If changed:** update both locations and recreate Apple Pay certificates for the new merchant ID.

---

## 4. Logging / Subsystem IDs
| File | Identifier |
| --- | --- |
| `UsageTracker.swift` | `Logger(subsystem: "com.payattentionclub2.0.app", ...)` |
| `SyncLogger`, logging docs | `com.payattentionclub.payattentionclub-app-1-1` |
| `UsageSyncManager.swift` queue label | `"com.payattentionclub2.0.app.sync"` |

Mostly for log filtering; update if bundle ID changes to keep Console filters aligned.

---

## 5. URL Schemes / Deep Links
| File | Details |
| --- | --- |
| `payattentionclub-app-1-1-Info.plist` | `<key>CFBundleURLSchemes</key> ... "com.payattentionclub.app.deeplink"` |
| `AppModel.handleDeepLink` | Routes `payattentionclub://...` URLs |

Register any new scheme in App Store Connect and update the handler.

---

## 6. DeviceActivity / FamilyControls References
Docs such as `EXTENSION_DEBUGGING_*`, `EXTENSION_ISSUE_FOR_CHATGPT.md`, and troubleshooting guides explicitly reference:
- Bundle ID `com.payattentionclub.payattentionclub-app-1-1.DeviceActivityMonitorExtension`
- App Group `group.com.payattentionclub2.0.app`

Update these docs if you rename the targets so setup steps stay accurate.

---

## 7. Miscellaneous References
- `SETUP_INSTRUCTIONS.md`, `VERIFICATION_CHECKLIST.md`: organization ID `com.payattentionclub`, App Group setup steps.
- `HOW_TO_VIEW_LOGS_MAC_CONSOLE.md`: log predicates referencing the bundle ID/subsystem.
- `UsageSyncManager.swift` queue label / `SyncLogger` subsystem strings.
- `supabase/config.toml` `[auth.external.apple]`: Sign-in with Apple client/secret placeholders.

Keep these in sync with any identifier changes for consistent tooling/docs.

---

## 8. Sign in with Apple (Supabase) – How we generated the credentials

1. **Create / locate the Services ID (client ID)**
   - Apple Developer portal → *Certificates, Identifiers & Profiles* → Identifiers → “+” → **Services IDs**.
   - Give it an identifier such as `com.payattentionclub.auth`, enable **Sign in with Apple**, and configure the return URL.
   - This value is the `client_id` Supabase needs.

2. **Generate a Sign in with Apple key (.p8)**
   - Apple Developer portal → Keys → “+”.
   - Enable **Sign in with Apple**, link the Services ID from step 1, and download the `.p8` private key.
   - Apple shows the **Key ID** (e.g., `VUJHM3XP22`). Note it alongside your **Team ID** (from Membership).

3. **Configure Supabase provider**
   - Supabase Dashboard → *Authentication* → *Providers* → Apple.
   - Fill in:
     - **Client ID** = Services ID (step 1).
     - **Team ID** = Apple Developer Team ID.
     - **Key ID** = value from step 2 (e.g., `VUJHM3XP22`).
     - **Private key** = paste the contents of the `.p8` file.
   - Supabase stores these securely and uses them to mint the Sign in with Apple JWT. (If self-hosting, set `client_id`, `secret`, `key_id`, and `team_id` via env vars referenced in `supabase/config.toml`.)

4. **Rotate as needed**
   - When rotating keys, repeat step 2 (new `.p8`) and update the provider settings with the new Key ID + private key.
   - Redeploy or restart Supabase services if required so the new credentials take effect.

Keep this workflow handy whenever you need to update the Sign in with Apple credentials.*** End Patch*** End Patch

