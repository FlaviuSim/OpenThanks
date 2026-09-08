# App Store Connect — OpenThanks

Use these fields when creating the listing in [App Store Connect](https://appstoreconnect.apple.com).

## Identity

| Field | Value |
|--------|--------|
| Name | OpenThanks |
| Subtitle (30 chars) | Share real appreciation |
| Bundle ID | `com.openthanks.gratitude` |
| SKU | `openthanks-ios` |
| Primary language | English (U.S.) |
| Category (Primary) | Social Networking |
| Category (Secondary) | Lifestyle |
| Content rights | Yes — you own / have rights to the content |
| Age rating | **18+** — Social Networking with unrestricted UGC (messages, photos). In App Store Connect, answer the age questionnaire accordingly (user-generated content, sharing personal info). Privacy/Terms require users **18+**. |

## Description

```
OpenThanks is a simple way to thank the people who make your life better — and let that kindness travel.

Write a heartfelt appreciation, add a photo if you want, and send it by email, text, or link. When they accept, it becomes part of both of your stories.

WHY OPENTHANKS
• Share appreciation that feels personal, not performative
• Recipients choose when to accept — their moment, their choice
• Public posts inspire others; private ones stay between you
• Champion a nonprofit cause on your profile
• Gentle Friday reminders to thank someone who made your week

HOW IT WORKS
1. Thank someone — write a short note (and optional photo)
2. Send them the link to accept by text, email, or copy/paste
3. They accept — and the appreciation can brighten the World feed

Sign in with email or phone. No ads. Built for real gratitude.
```

## Keywords (100 characters max, comma-separated, no spaces after commas preferred)

```
gratitude,thank you,appreciation,kindness,social,nonprofit,thanks,notes,friends
```

(Count carefully in App Store Connect — max 100 characters total.)

## URLs

| Field | URL |
|--------|-----|
| Privacy Policy | https://openthanks.com/privacy |
| Support URL | https://openthanks.com/support |
| Marketing | https://openthanks.com |
| Terms | https://openthanks.com/terms |

## What’s New (1.0.2)

```
• Share appreciation with photos
• Accept pending thanks from Home
• Phone sign-in and profile causes
• Faster Home feed and clearer notifications
```

## App Review notes

**Paste-ready notes + day-of-submit click order:** see [`REVIEW_NOTES.md`](REVIEW_NOTES.md).

## Screenshots

Real simulator captures, sized for Connect — see `AppStore/Screenshots/README.md`.

**Upload first:**

- `AppStore/Screenshots/iPhone-6.9-inch/` — **1320×2868** (primary iPhone)
- `AppStore/Screenshots/iPad-13-inch/` — **2064×2752** (required; universal app)

Also generated: 6.7" / 6.5" iPhone and 12.9" iPad sets. Order by filename `01`…

## Icons

- Xcode asset catalog: `OpenThanks/Assets.xcassets/AppIcon.appiconset/` (light / dark / tinted, 1024×1024, **no alpha**)
- Standalone upload copy: `AppStore/Icons/AppStore-Icon-1024.png`
- Alternate icons (Appearance settings): `OpenThanks/AlternateIcons/`
  - iPhone: `AppIcon-{Ember,Dawn,Night}@2x.png` (120) / `@3x.png` (180)
  - iPad (TMS-90892): `@2x~ipad.png` (152) / `@3x~ipad.png` (167), RGB PNG, no alpha
  - Declared in `Info.plist` under both `CFBundleIcons` and `CFBundleIcons~ipad`
  - After adding/changing icon files, run `xcodegen` so they are copied into the app bundle (Copy Bundle Resources). Verify in the built `.app` that `AppIcon-*@2x~ipad.png` exist at 152×152.

## Privacy Nutrition Labels (App Store Connect)

Declare accurately (PostHog analytics + account data):

| Data type | Linked to user | Used for tracking | Purposes |
|-----------|----------------|-------------------|----------|
| Email Address | Yes | No | App Functionality, Analytics |
| Phone Number | Yes | No | App Functionality |
| Name | Yes | No | App Functionality, Analytics |
| User ID | Yes | No | App Functionality, Analytics |
| Photos or Videos | Yes | No | App Functionality |
| Other User Content (messages / appreciations) | Yes | No | App Functionality |
| Device ID | Yes | No | Analytics |
| Product Interaction | Yes | No | Analytics, App Functionality |
| Calendar Events (optional connect) | Yes | No | App Functionality |

**Tracking: No** (no ATT; no third-party advertising SDK).

**Calendar:** used only when the user connects Apple Calendar (on-device EventKit) and/or Google Calendar (readonly API for today’s events for evening thank-you suggestions). Calendar events are not stored on OpenThanks servers; Google tokens stay in the on-device Keychain. Public disclosures: https://openthanks.com/privacy#google-user-data

## Connect checklist (age / SIWA / delete)

Complete in App Store Connect before submit:

- [ ] Age rating questionnaire: mark **User-Generated Content**, **Social Networking**, sharing personal info; set rating to **18+** (policy: 18+)
- [ ] Privacy Nutrition Labels match the table above (Analytics + App Functionality; Tracking = No)
- [ ] Sign in with Apple works on device alongside Google / LinkedIn / email / phone
- [ ] Settings → Delete Account works (use a spare test account — keep the reviewer demo account intact)
- [ ] Confirm Settings has **no** Stripe / Subscribe / donate / external payment CTA

## Checklist before Submit

- [ ] Archive a Release build in Xcode (Product → Archive)
- [ ] Upload via Organizer / Transporter
- [ ] Confirm no TMS-90892 (alternate iPad 152/167 icons present in archive)
- [ ] Screenshots attached for 6.7" (and 6.5" if prompted); add iPad if Connect requires
- [ ] Privacy Policy URL live (`https://openthanks.com/privacy`)
- [ ] App Privacy questionnaire completed (include Calendar Events; no tracking)
- [ ] Export compliance: uses only exempt encryption (already `ITSAppUsesNonExemptEncryption = false`)
- [ ] TestFlight: sign-in (Apple + email), compose, accept, Report, alternate icon, **Delete Account**
- [ ] Reviewer demo account ready (do not delete the demo account before review finishes)
- [ ] Sign in with Apple works if other third-party login is offered (Google)
- [ ] Apply `scripts/025_content_reports.sql` on production Supabase before shipping Report
- [ ] Deploy web `/api/report` to openthanks.com
