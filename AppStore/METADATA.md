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

To demo the core flow:
1. Create an appreciation to a second email you control
2. Open the link to accept from the Home “waiting for you” card
3. Confirm it appears under Profile → Received

Universal Links: openthanks.com claim/for/profile routes open in-app when installed.

Photo library permission is only used when attaching a photo to an appreciation or setting a profile photo.
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
- [ ] Screenshots attached for 6.7" (and 6.5" if prompted)
- [ ] Privacy Policy URL live
- [ ] App Privacy questionnaire completed
- [ ] Export compliance: uses only exempt encryption (already `ITSAppUsesNonExemptEncryption = false`)
- [ ] TestFlight internal smoke test (sign-in, compose, accept, profile)
- [ ] Reviewer demo account ready
