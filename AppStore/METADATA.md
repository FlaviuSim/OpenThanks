# App Store Connect — OpenThanks

Use these fields when creating the listing in [App Store Connect](https://appstoreconnect.apple.com).

## Identity

| Field | Value |
|--------|--------|
| Name | OpenThanks |
| Subtitle (30 chars) | Share real appreciation |
| Bundle ID | `com.openthanks.gratitude` |
| Devices (1.1) | **iPhone only** — re-enable iPad in a later update |
| SKU | `openthanks-ios` |
| Primary language | English (U.S.) |
| Category (Primary) | Social Networking |
| Category (Secondary) | Lifestyle |
| Content rights | Yes — you own / have rights to the content |
| Age rating | Answer the questionnaire for Social Networking + UGC (messages; optional photos of thank-yous). **Do not** market the app as adult/18+ content. Terms still require users 18+ in-app; keep that as a product rule, not App Store promo copy. |

## Description

Paste this into App Store Connect **Description** (replaces any prior text). Keep it gratitude-only — no adult, dating, or unrestricted-media framing.

```
OpenThanks helps you thank the people who make your life better.

Write a short appreciation and send it by email, text, or link. The recipient reviews it and chooses whether to accept. Nothing is shared publicly until they accept.

WHY OPENTHANKS
• Personal thank-yous, not performative posts
• Recipients decide what to accept
• Keep notes private, or share accepted ones with the community
• Optional nonprofit cause on your profile
• Gentle Friday reminders to thank someone who helped you

HOW IT WORKS
1. Write a thank-you note
2. Send the link by text, email, or copy/paste
3. They accept — and kindness can travel

Sign in with Apple, email, or phone. No ads. Built for real gratitude.
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

## What’s New (1.1)

Do **not** mention age gates, 18+, adult content, or unrestricted media in What’s New / promotional text.

```
• Sign in with Apple keeps your name and email after first sign-in
• Report and Block from appreciations and profiles
• Clearer thank-you claim flow
• iPhone-focused release (Watch icon updated)
```

## App Review notes

**Paste-ready notes + day-of-submit click order:** see [`REVIEW_NOTES.md`](REVIEW_NOTES.md).

## Screenshots

Real simulator captures, sized for Connect — see `AppStore/Screenshots/README.md`.

**Upload first (iPhone-only release for 1.1):**

- `AppStore/Screenshots/iPhone-6.9-inch/` — **1320×2868** (primary iPhone)

Do **not** upload iPad screenshots while the binary is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). iPad sets remain in the repo for a later universal update.

Also generated: 6.7" / 6.5" iPhone and 12.9" / 13" iPad sets. Order by filename `01`…

## Icons

- Xcode asset catalog: `OpenThanks/Assets.xcassets/AppIcon.appiconset/` (light / dark / tinted, 1024×1024, **no alpha**)
- Watch: `OpenThanksWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` — **light cream background** (not black) so the icon reads circular on watchOS
- Standalone upload copy: `AppStore/Icons/AppStore-Icon-1024.png`; Watch preview: `AppStore/Icons/Watch-AppIcon-1024.png`
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

- [ ] Age rating questionnaire: mark Social Networking + UGC accurately; **do not** use Description / What’s New / screenshots to market the app as adult or “18+ content”
- [ ] Privacy Nutrition Labels match the table above (Analytics + App Functionality; Tracking = No)
- [ ] Sign in with Apple works on device alongside Google / LinkedIn / email / phone
- [ ] Settings → Delete Account works (use a spare test account — keep the reviewer demo account intact)
- [ ] Confirm Settings has **no** Stripe / Subscribe / donate / external payment CTA
- [ ] Description + What’s New match the gratitude-only copy above (no 18+ / adult / dating language)
- [ ] Screenshots: **do not** upload the welcome screen that shows the “I am 18 or older” checkbox

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
