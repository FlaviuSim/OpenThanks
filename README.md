# OpenThanks iOS

Native SwiftUI app for openthanks.com, wired directly to the production `open-thanks` Supabase project (`dsftvyuzmhlqadhbubgw`). Built against the live schema: `profiles`, `gratitudes`, `hearts`, `notifications`, `device_push_tokens`.

## Requirements

- Xcode 16+, iOS 17+ deployment target
- An Apple Developer team (for Sign in with Apple + device builds)

## Build

1. Open `OpenThanks.xcodeproj` in Xcode. First open resolves the `supabase-swift` package (2.x) automatically.
2. Select your team under Signing & Capabilities (bundle ID `com.openthanks.ios`, change if needed).
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
     2. iOS bundle ID `com.openthanks.ios` (required for native Sign in with Apple).
     Comma- or newline-separated is fine. If the bundle ID is missing you get
     `unacceptable audience in id_token` from the app.
   - **Google / LinkedIn (OIDC):** confirm enabled in Authentication → Providers.
   - **Redirect URLs** (Authentication → URL Configuration):
     - `https://openthanks.com/auth/mobile` (iOS OAuth lander for Google/LinkedIn)
     - `openthanks://auth-callback` (app custom scheme)
   The Welcome screen offers Apple, Google, LinkedIn, email OTP, and phone OTP.
4. **Hearts uniqueness:** the toggle assumes one heart per (user, gratitude). Add a unique index if one doesn't exist.

## Google Calendar (evening thank-you nudge)

Separate from Supabase “Sign in with Google”. Tokens stay in the device Keychain; events are not uploaded to OpenThanks.

**Use an iOS OAuth client** — Google Web clients only accept `https://` redirects, not app URL schemes.

1. In [Google Cloud Console](https://console.cloud.google.com/), create (or reuse) a project and enable **Google Calendar API**.
2. **Credentials → Create credentials → OAuth client ID → Application type: iOS**
   - Bundle ID: `com.openthanks.ios`
   - Google does **not** ask you to paste a redirect URI for iOS; it uses the reversed client ID automatically.
3. Put the Client ID in `AppConfig.googleCalendarClientID`.
4. Register the **reversed client ID** as a URL scheme in `Info.plist` / `project.yml`  
   (e.g. client `123-abc.apps.googleusercontent.com` → scheme `com.googleusercontent.apps.123-abc`).  
   The app redirects to `{reversed-client-id}:/oauthredirect`.
5. OAuth consent screen: add scope `https://www.googleapis.com/auth/calendar.readonly` (and add test users while the app is in Testing).

v1 reads the **primary** calendar only. Apple Calendar (EventKit) can be connected at the same time; the ranker merges both.

## Fonts

The design can use Fraunces (display) and DM Sans (body), but the font files are not bundled by default. Without them the app falls back to the system serif/SF.

## Not built (deliberately)

- Video attachments: schema supports `media_type`; UI supports photo + video upload.
- Universal Links require Associated Domains enabled on App ID `com.openthanks.ios` in the Apple Developer portal (entitlements already include `applinks:openthanks.com` + www). After a TestFlight/App Store install, long-press a share link in Notes — you should see “Open in OpenThanks”.
- Realtime feed updates: pull-to-refresh only in v1.

## Push notifications (APNs via Supabase)

**App (ready):** requests permission, registers the device token, upserts into `device_push_tokens` with `environment` = `sandbox` (DEBUG) or `production` (Release / TestFlight).

**Server (ready to wire):** Edge Function `supabase/functions/send-apns` talks to APNs with a `.p8` key. It does **not** auto-fire until you set secrets and deploy it.

1. Apply migration `supabase/migrations/20260731_device_push_tokens_apns.sql` (if not already).
2. Create an APNs Auth Key in Apple Developer; enable Push on `com.openthanks.ios`.
3. Set secrets and deploy — see [`supabase/functions/send-apns/README.md`](supabase/functions/send-apns/README.md).
4. Later: Database Webhook on `notifications` INSERT, or call the function from Next.js/cron with the service role key.

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

## Related repos

| Repo | Purpose |
|------|---------|
| https://github.com/FlaviuSim/OpenThanks | This iOS / Watch / Widget app |
| https://github.com/FlaviuSim/v0-gratitude-network | Web app + PWA (openthanks.com) |
| https://github.com/FlaviuSim/openthanks-twa | Android TWA (Bubblewrap) for Play Store |

**Android upload keystore** (`android.keystore`) is **not** in git — back it up separately or Play updates become painful.
