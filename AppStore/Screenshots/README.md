# App Store screenshots (ready to upload)

Real simulator captures, resized to App Store Connect exact pixel sizes.

## Upload these first (required)

| Slot in Connect | Folder | Size | Count |
|-----------------|--------|------|-------|
| **iPhone 6.9"** (primary) | `iPhone-6.9-inch/` | **1320 × 2868** | 8 |
| **iPad 13"** (required — app is universal) | `iPad-13-inch/` | **2064 × 2752** | 7 |

Optional extras (only if Connect asks / you want device-specific sets):

| Slot | Folder | Size |
|------|--------|------|
| iPhone 6.7" | `iPhone-6.7-inch/` | 1290 × 2796 |
| iPhone 6.5" | `iPhone-6.5-inch/` | 1284 × 2778 |
| iPad 12.9" | `iPad-12.9-inch/` | 2048 × 2732 |

## Suggested upload order (iPhone)

1. `01-onboarding.png` — Gratitude changes everything  
2. `02-welcome-signin.png` — Sign-in + 18+ age gate  
3. `03-world-feed-accept.png` — World feed + accept pending  
4. `04-compose.png` — New Appreciation (filled)  
5. `05-share-link.png` — Share / copy link after save  
6. `06-profile-cause.png` — Profile + cause  
7. `07-appearance.png` — Theme + alternate icons  
8. `08-stats-challenge.png` — Streak / 30 Days of Thanks  

## Suggested upload order (iPad)

1. `01-world-feed-share.png`  
2. `02-say-thanks-ways.png`  
3. `03-welcome-signin.png`  
4. `04-profile.png`  
5. `05-appearance.png`  
6. `06-stats.png`  
7. `07-compose.png`  

## Intentionally omitted from store gallery

- Empty compose screen  
- Notifications list with “Test” sender  
- Notifications **settings** with **“Preview for reviewers”** (dev/review-only UI — fine on device, not for the public listing)

## Notes

- Source captures were iPhone 16/17 Pro (1206×2622) and 11" iPad class (1640×2360); resized with cover+center crop (tiny crop on iPad aspect change).  
- Status bar still shows real simulator time (not 9:41). Apple accepts this; optional polish later via `xcrun simctl status_bar … override`.  
- For sharper native pixels later: capture on **iPhone 17 Pro Max** (1320×2868) and **iPad Pro 13"** (2064×2752) with File → Save Screen.
