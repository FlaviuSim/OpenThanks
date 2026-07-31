# Google Play — store listing assets

Upload these in Play Console → **Grow** → **Store presence** → **Main store listing** (wording varies slightly by Console version).

Folder: `PlayStore/listing/`

## Required graphics (ready to upload)

| Play field | File | Spec |
|------------|------|------|
| **App icon** | `hi-res-icon-512.png` | 512×512 PNG, square (Play rounds corners) |
| **Feature graphic** | `feature-graphic-1024x500.png` | 1024×500 PNG, no transparency |
| **Phone screenshots** | `phone-screenshots/01` … `05` | 1080×1920 PNG, ≥2 required (upload all 5) |
| **7-inch tablet** | `tablet-7-inch/01` … `05` | 1200×1920 PNG |
| **10-inch tablet** | `tablet-10-inch/01` … `05` | 1600×2560 PNG |

Paths on this Mac:

```
/Users/simihaian/Downloads/OpenThanks/PlayStore/listing/hi-res-icon-512.png
/Users/simihaian/Downloads/OpenThanks/PlayStore/listing/feature-graphic-1024x500.png
/Users/simihaian/Downloads/OpenThanks/PlayStore/listing/phone-screenshots/
/Users/simihaian/Downloads/OpenThanks/PlayStore/listing/tablet-7-inch/
/Users/simihaian/Downloads/OpenThanks/PlayStore/listing/tablet-10-inch/
```

Open the folder:

```bash
open /Users/simihaian/Downloads/OpenThanks/PlayStore/listing
```

## Copy / text

### App name
```
OpenThanks
```

### Short description (≤80 characters)
```
Share real appreciation with the people who make life better.
```
(64 characters)

### Full description
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

### Category
Social / Lifestyle (pick the closest Play categories, e.g. **Social** primary)

### Contact / policy URLs
| Field | URL |
|--------|-----|
| Privacy policy | https://openthanks.com/privacy |
| Support email | founders@openthanks.com |
| Website | https://openthanks.com |

## Optional (not required for internal testing)
- Promo video (YouTube)
- Graphic for TV / Wear (only if you target those)

## Notes
- Phone and tablet shots are rebuilt from the **live OpenThanks web UI** (landing, sign-in) plus product screens that match site colors/typography (feed, compose, accept).
- Icon is a full square — do **not** add your own rounded corners or drop shadow.
- After first AAB upload, complete **Data safety** using the same disclosures as the privacy policy.
