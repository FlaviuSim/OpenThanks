# OpenThanks iOS

Native SwiftUI app for openthanks.com, wired directly to the production `open-thanks` Supabase project (`dsftvyuzmhlqadhbubgw`). Built against the live schema: `profiles`, `gratitudes`, `hearts`, `notifications`, `device_push_tokens`.

## Requirements

- Xcode 16+, iOS 17+ deployment target
- An Apple Developer team (for Sign in with Apple + device builds)

## Build

1. Open `OpenThanks.xcodeproj` in Xcode. First open resolves the `supabase-swift` package (2.x) automatically.
2. Select your team under Signing & Capabilities (bundle ID `com.openthanks.app`, change if needed).
3. Run.

If the project file ever fails to open on a newer Xcode, regenerate it: `brew install xcodegen && xcodegen` (a `project.yml` is included).

## Backend wiring — what's verified vs. what you must confirm

**Verified against the live project (2026-07-06):**
- URL `https://db.openthanks.com` (custom domain for project `dsftvyuzmhlqadhbubgw`) and publishable key `sb_publishable_6E3JYy1bWx45o9o9NmDjbg_77tAjxN1` (both in `Config/AppConfig.swift`)
- Table/column names and FK relationship names used in every PostgREST embed
- RLS is enabled on all public tables
- Phone auth exists (the `profiles.phone` column is populated by phone signup)
- Zero Supabase Edge Functions — your "Make it Warmer"/"Polish" AI features live in the Next.js API routes, so the iOS buttons are hidden until you set `AppConfig.polishEndpoint`

**Unverified — check before shipping (the SQL inspection call wasn't approved in session):**
1. **Storage bucket name.** `AppConfig.mediaBucket` is set to `gratitude-media` as a guess. Check Supabase Studio → Storage and correct it, and confirm the bucket has an authenticated-upload RLS policy.
2. **RLS policies permit these mobile flows:** insert into `gratitudes` by `author_id = auth.uid()`, insert/delete own `hearts`, insert own `profiles` row on first sign-in, update own `notifications.read`. Your web app already does most of this, so it likely just works — but the profile self-insert may be handled by a DB trigger on `auth.users` instead; if so, delete the insert fallback in `AuthService.loadOrCreateProfile`.
3. **Auth providers:**
   - **Apple** (Authentication → Providers → Apple): Client IDs must include **both**
     1. Web **Services ID** first (required for web OAuth), then
     2. iOS bundle ID `com.openthanks.app` (required for native Sign in with Apple).
     Comma- or newline-separated is fine. If the bundle ID is missing you get
     `unacceptable audience in id_token` from the app.
   - **Google:** confirm enabled.
   - **Redirect URLs** (Authentication → URL Configuration):
     - `https://openthanks.com/auth/mobile` (iOS Google OAuth lander)
     - `openthanks://auth-callback` (app custom scheme)
   The Welcome screen offers Sign in with Apple + Continue with Google alongside email/phone OTP. LinkedIn from the web was intentionally dropped on iOS.
4. **Hearts uniqueness:** the toggle assumes one heart per (user, gratitude). Add a unique index if one doesn't exist.

## Fonts

The design can use Fraunces (display) and DM Sans (body), but the font files are not bundled by default. Without them the app falls back to the system serif/SF.

## Not built (deliberately)

- Push notifications: the app can request notification permission, register APNs tokens in `device_push_tokens`, and schedule the local Friday gratitude reminder. Server-side APNs sending from the web/backend is still a separate work item.
- Video attachments: schema supports `media_type`, UI ships photo-only.
- Universal Links require Associated Domains enabled on App ID `com.openthanks.app` in the Apple Developer portal (entitlements already include `applinks:openthanks.com` + www). After a TestFlight/App Store install, long-press a share link in Notes — you should see “Open in OpenThanks”.
- Realtime feed updates: pull-to-refresh only in v1.

## Structure

```
OpenThanks/
  Config/AppConfig.swift        ← credentials + feature endpoints
  Theme/Theme.swift             ← palette, gradients, type, chrome
  Models/Models.swift           ← schema-mirrored Codable models
  Services/AuthService.swift    ← Apple / Google / email OTP / phone OTP
  Services/GratitudeService.swift ← feeds, compose, hearts, stats, storage
  Views/                        ← Onboarding, Welcome, Feed, Compose,
                                   Profile, Notifications, Settings, Pending
```
