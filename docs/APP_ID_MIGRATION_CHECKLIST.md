# New App ID checklist — `com.openthanks.gratitude`

Xcode / repo target state (already done or updated in git):

| Item | Value |
| --- | --- |
| Team ID | `XA73L5SR8P` |
| iOS app | `com.openthanks.gratitude` |
| Widget | `com.openthanks.gratitude.widget` |
| Share | `com.openthanks.gratitude.share` |
| Watch | `com.openthanks.gratitude.watch` |
| Watch widgets | `com.openthanks.gratitude.watch.widgets` |
| App Group | `group.com.openthanks.gratitude` |
| URL scheme (auth) | `openthanks://auth-callback` |
| Associated domains | `applinks:` + `webcredentials:` for `openthanks.com` / `www.openthanks.com` |
| BG task | `com.openthanks.gratitude.calendar-gratitude-refresh` |
| AASA (web) | `XA73L5SR8P.com.openthanks.gratitude` (+ old ID kept temporarily) |

---

## What you must change outside the repo

Do these in order. Email links / Universal Links will keep opening in Safari until **§2** is live and Apple’s CDN refreshes.

### 1. Apple Developer (team `XA73L5SR8P`)

Create / confirm **Identifiers**:

- [ ] App ID `com.openthanks.gratitude` with: Push Notifications, Associated Domains, Sign In with Apple, App Groups
- [ ] App ID `com.openthanks.gratitude.widget` (App Groups)
- [ ] App ID `com.openthanks.gratitude.share` (App Groups)
- [ ] App ID `com.openthanks.gratitude.watch` (App Groups, if used)
- [ ] App ID `com.openthanks.gratitude.watch.widgets` (App Groups)
- [ ] App Group `group.com.openthanks.gratitude` — enable on **every** App ID above
- [ ] **Sign In with Apple** capability on the main App ID; if you use a Services ID for web, keep that for the website
- [ ] **APNs key** (.p8) on **this** team (old team’s key will not work). Note Key ID + Team ID `XA73L5SR8P`
- [ ] Provisioning: Xcode Automatic Signing is fine once IDs/capabilities exist
- [ ] App Store Connect: new app record for `com.openthanks.gratitude` (cannot transfer TestFlight-only apps from the old account)

### 2. Universal Links / email open-in-app (AASA) — **this was why email links failed**

Live file was still `53CL59ATX8.com.openthanks.app`. Repo now points at the new ID.

- [ ] Deploy web so `https://openthanks.com/.well-known/apple-app-site-association` serves the new JSON (no `Content-Type` tricks required; must be reachable without redirects that strip the body)
- [ ] Confirm: https://app-site-association.cdn-apple.com/a/v1/openthanks.com shows `XA73L5SR8P.com.openthanks.gratitude`
- [ ] On device: delete the app, reinstall TestFlight build, open a Notes link to `https://openthanks.com/claim/...` or `/for/...` — should offer **Open in OpenThanks**
- [ ] Paths already covered (no email template change needed): `/claim/*`, `/for/*`, `/gratitude/*`, `/pending`, `/sent`, `/notifications`, profile usernames

### 3. Supabase Auth

Dashboard → **Authentication** → **Providers** → **Apple**:

- [ ] **Client IDs** must include **both**:
  1. Web Services ID (e.g. `com.openthanks.web` / whatever the site uses)
  2. **`com.openthanks.gratitude`** (native Sign in with Apple)
- [ ] Secret / Key stays the Services ID JWT from Apple (usually unchanged if Services ID unchanged)

**URL Configuration → Redirect URLs** must still include:

- [ ] `openthanks://auth-callback`
- [ ] `https://openthanks.com/auth/mobile`
- [ ] Any other existing web callbacks

### 4. Push notifications (APNs → Supabase secrets)

Old secrets used Team `53CL59ATX8`. Update to the new team key:

```bash
supabase secrets set \
  APNS_KEY="$(cat AuthKey_NEWID.p8 | sed ':a;N;$!ba;s/\n/\\n/g')" \
  APNS_KEY_ID="YOUR_NEW_KEY_ID" \
  APNS_TEAM_ID="XA73L5SR8P" \
  APNS_TOPIC="com.openthanks.gratitude"
```

- [ ] Redeploy `send-apns` (or whatever function reads these secrets)
- [ ] Expect users to **re-open the new app** so a fresh device token registers (old tokens belong to the old app ID)
- [ ] TestFlight = production APNs environment; Xcode debug = sandbox

### 5. Google Sign-In (via Supabase) — usually OK

Web Google OAuth client is unchanged. iOS uses the HTTPS lander `/auth/mobile` → `openthanks://auth-callback`.

- [ ] Smoke-test Google sign-in on a device with the **new** build
- [ ] If it fails, confirm Redirect URLs (§3) and that `/auth/mobile` still bounces to `openthanks://auth-callback`

### 6. Google Calendar (separate iOS OAuth client) — **easy to miss**

Google iOS clients are locked to one bundle ID.

- [ ] Google Cloud Console → Credentials → your **iOS** OAuth client
- [ ] Bundle ID must be exactly `com.openthanks.gratitude`
- [ ] If the client was created for `com.openthanks.app`, **create a new iOS client**, then update in the app:
  - `OpenThanks/Config/AppConfig.swift` → `googleCalendarClientID`
  - `OpenThanks/Info.plist` → reversed client URL scheme
  - `project.yml` URL schemes (if you regenerate with XcodeGen)
- [ ] Users must reconnect Google Calendar in Settings (Keychain is per-app-ID)

### 7. Apple Calendar / local permissions

No portal change. On the new app install:

- [ ] Re-grant Calendar access
- [ ] Re-grant Notifications
- [ ] Confirm weekday evening nudge / BG task still schedules (`com.openthanks.gratitude.calendar-gratitude-refresh`)

### 8. Widgets / Share / Watch / Live Activity / Control Center

- [ ] After install: add widgets again (new bundle = new widget kind namespace)
- [ ] Share sheet: confirm OpenThanks appears (Share extension ID `.share`)
- [ ] Watch app installs with phone; App Group must match
- [ ] Streak Live Activity: start once on a grace day; confirm countdown
- [ ] Control Center “Thank someone” control: re-add if missing

### 9. Password Autofill / webcredentials (optional)

- [ ] AASA `webcredentials.apps` includes `XA73L5SR8P.com.openthanks.gratitude` (done in repo)
- [ ] Associated Domains on App ID includes associated domains capability (done in entitlements)

### 10. Analytics / third parties

- [ ] PostHog: usually fine (same key); filter by new bundle if you segment by app
- [ ] Any Firebase / Crashlytics / Sentry app records: create/select the new bundle
- [ ] App Store Connect API / fastlane / CI: update `APP_IDENTIFIER` / team

### 11. Android TWA / Play (if still shipping)

Unrelated to iOS bundle, but keep `assetlinks.json` package name accurate (`com.openthanks.myapp` today). No change required for this iOS migration.

---

## Quick verification matrix

| Flow | How to verify |
| --- | --- |
| Apple Sign-In | New install → Sign in with Apple succeeds (no “unacceptable audience”) |
| Google Sign-In | Completes and returns to app (not stuck in Safari) |
| Email claim link | Mail → link → opens **app** on `/claim/...` |
| Email pending / notifications | Opens app tabs, not only Safari |
| Push | Send test via `send-apns`; tap opens correct screen |
| Apple Calendar nudge | Grant access; suggestion appears after meetings |
| Google Calendar | Connect; meetings load; reconnect after client ID change |
| Share extension | Share image/text into OpenThanks compose |
| Widget / Control | Opens compose |
| Watch | Dictate / send path still reaches iPhone compose |

---

## What we cannot change from the IDE

Anything in Apple Developer, App Store Connect, Supabase Dashboard secrets, Google Cloud OAuth clients, or Apple’s AASA CDN cache — those are listed above. Code + AASA files in git are the only parts automation can fix.
