# App Store screenshots (ready to upload)

Real simulator captures, resized to App Store Connect exact pixel sizes.

## Upload these first (required)

| Slot in Connect | Folder | Size | Count |
|-----------------|--------|------|-------|
| **iPhone 6.9"** (primary) | `iPhone-6.9-inch/` | **1320 × 2868** | 8 |

**1.1 is iPhone-only** — do not upload iPad screenshots until the binary is universal again.

Optional extras (only if Connect asks / you want device-specific sets):

| Slot | Folder | Size |
|------|--------|------|
| iPhone 6.7" | `iPhone-6.7-inch/` | 1290 × 2796 |
| iPhone 6.5" | `iPhone-6.5-inch/` | 1284 × 2778 |
| iPad 13" (later) | `iPad-13-inch/` | 2064 × 2752 |
| iPad 12.9" (later) | `iPad-12.9-inch/` | 2048 × 2732 |

## Suggested upload order (iPhone)

**Skip `02-welcome-signin.png` for Connect** — it shows the in-app “I am 18 or older” checkbox and can trigger Guideline 1.1 marketing flags. Keep that gate in the app; do not market it.

1. `01-onboarding.png` — Gratitude changes everything  
2. `03-world-feed-accept.png` — World feed + accept pending  
3. `04-compose.png` — New Appreciation (filled)  
4. `05-share-link.png` — Share / copy link after save  
5. `06-profile-cause.png` — Profile + cause  
6. `07-appearance.png` — Theme + alternate icons  
7. `08-stats-challenge.png` — Streak / 30 Days of Thanks  

(Optional later: a welcome/sign-in capture **without** the age checkbox visible.) 

## Suggested upload order (iPad)

1. `01-world-feed-share.png`  
2. `02-say-thanks-ways.png`  
3. `03-welcome-signin.png`  
4. `04-profile.png`  
5. `05-appearance.png`  
6. `06-stats.png`  
7. `07-compose.png`  

## Intentionally omitted from store gallery

- `02-welcome-signin.png` (shows “I am 18 or older” — do not upload)  
- Empty compose screen  
- Notifications list with “Test” sender  
- Notifications **settings** with **“Preview for reviewers”** (dev/review-only UI — fine on device, not for the public listing)

## Notes

- Source captures were iPhone 16/17 Pro (1206×2622) and 11" iPad class (1640×2360); resized with cover+center crop (tiny crop on iPad aspect change).  
- Status bar still shows real simulator time (not 9:41). Apple accepts this; optional polish later via `xcrun simctl status_bar … override`.  
- For sharper native pixels later: capture on **iPhone 17 Pro Max** (1320×2868) and **iPad Pro 13"** (2064×2752) with File → Save Screen.
