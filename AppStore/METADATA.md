# App Store Connect — OpenThanks

Use these fields when creating the listing in [App Store Connect](https://appstoreconnect.apple.com).

## Identity

| Field | Value |
|--------|--------|
| Name | OpenThanks |
| Subtitle (30 chars) | Share real appreciation |
| Bundle ID | `com.openthanks.app` |
| SKU | `openthanks-ios` |
| Primary language | English (U.S.) |
| Category (Primary) | Social Networking |
| Category (Secondary) | Lifestyle |
| Content rights | Yes — you own / have rights to the content |
| Age rating | 4+ (no unrestricted web, no mature content) |

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
| Support / Marketing | https://openthanks.com |
| Terms | https://openthanks.com/terms |

## What’s New (1.0.2)

```
• Share appreciation with photos
• Accept pending thanks from Home
• Phone sign-in and profile causes
• Faster Home feed and clearer notifications
```

## App Review notes

```
Sign in with email OTP (or phone SMS) using a test account you create before review.
Sign in with Apple is also available on the welcome screen.

To demo the core flow:
1. Create an appreciation to a second email you control
2. Open the link to accept from the Home “waiting for you” card
3. Confirm it appears under Profile → Received

Account deletion (Guideline 5.1.1v): Settings → Delete Account (below Log Out).
This permanently deletes the profile and associated data via our API — no email required.

Optional permissions (decline does not block core use):
• Photo Library — attach a photo to an appreciation or set a profile photo
• Notifications — Friday reminders and evening thank-you nudges
• Apple Calendar / Google Calendar — evening thank-you suggestions only; calendar data stays on device (Google: readonly today’s events; tokens in Keychain). See https://openthanks.com/privacy#google-user-data
• Siri — App Shortcuts to start an appreciation

Universal Links: openthanks.com claim/for/profile routes open in-app when installed.
Export compliance: ITSAppUsesNonExemptEncryption = false (HTTPS only).
```

## Screenshots

Ready-to-upload PNGs (marketing frames):

- `AppStore/Screenshots/iPhone-6.7-inch/` — 1290×2796 (required for modern iPhones)
- `AppStore/Screenshots/iPhone-6.5-inch/` — 1284×2778

Upload **at least 3** (up to 10) per size. Suggested order matches filenames `01`–`05`.

For highest conversion, replace these with real device captures from TestFlight after you have sample content, keeping the same headlines.

## Icons

- Xcode asset catalog: `OpenThanks/Assets.xcassets/AppIcon.appiconset/` (light / dark / tinted, 1024×1024, **no alpha**)
- Standalone upload copy: `AppStore/Icons/AppStore-Icon-1024.png`
- Alternate icons (Appearance settings): `OpenThanks/AlternateIcons/`
  - iPhone: `AppIcon-{Ember,Dawn,Night}@2x.png` (120) / `@3x.png` (180)
  - iPad (TMS-90892): `@2x~ipad.png` (152) / `@3x~ipad.png` (167), RGB PNG, no alpha
  - Declared in `Info.plist` under both `CFBundleIcons` and `CFBundleIcons~ipad`
  - After adding/changing icon files, run `xcodegen` so they are copied into the app bundle (Copy Bundle Resources). Verify in the built `.app` that `AppIcon-*@2x~ipad.png` exist at 152×152.

## Privacy Nutrition Labels (App Store Connect)

Match the Privacy Manifest where possible:

- Email, Phone, Name, User ID, Photos, Other User Content, Device ID  
- Linked to user: **Yes**  
- Used for tracking: **No**  
- Purpose: App Functionality  

**Calendar** (if not already disclosed): used for Product Interaction / App Functionality when the user connects Apple Calendar (on-device EventKit) and/or Google Calendar (readonly API for today’s events to build the evening thank-you suggestion). Calendar events are not stored on OpenThanks servers; Google tokens stay in the on-device Keychain. Public disclosures: https://openthanks.com/privacy#google-user-data

Tracking: **No**

## Checklist before Submit

- [ ] Archive a Release build in Xcode (Product → Archive)
- [ ] Upload via Organizer / Transporter
- [ ] Confirm no TMS-90892 (alternate iPad 152/167 icons present in archive)
- [ ] Screenshots attached for 6.7" (and 6.5" if prompted); add iPad if Connect requires
- [ ] Privacy Policy URL live (`https://openthanks.com/privacy`)
- [ ] App Privacy questionnaire completed (include Calendar Events; no tracking)
- [ ] Export compliance: uses only exempt encryption (already `ITSAppUsesNonExemptEncryption = false`)
- [ ] TestFlight: sign-in (Apple + email), compose, accept, alternate icon, **Delete Account**
- [ ] Reviewer demo account ready (do not delete the demo account before review finishes)
- [ ] Sign in with Apple works if other third-party login is offered (Google)
