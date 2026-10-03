# App Store screenshots (ready to upload)

Real simulator captures, resized to App Store Connect exact pixel sizes.

## Upload these (universal 1.2)

| Slot in Connect | Folder | Size | Count |
|-----------------|--------|------|-------|
| **iPhone 6.9"** (primary) | `iPhone-6.9-inch/` | **1320 × 2868** | see folder |
| **iPad 13"** | `iPad-13-inch/` | **2064 × 2752** | 6 |
| iPad 12.9" (if Connect asks) | `iPad-12.9-inch/` | **2048 × 2732** | 6 |

Optional extras:

| Slot | Folder | Size |
|------|--------|------|
| iPhone 6.7" | `iPhone-6.7-inch/` | 1290 × 2796 |
| iPhone 6.5" | `iPhone-6.5-inch/` | 1284 × 2778 |

## Suggested upload order (iPhone)

**Skip any welcome/sign-in frame that shows “I am 18 or older”** — Guideline 1.1 marketing risk. Keep the gate in the app; do not market it.

1. `01-onboarding.png` — Gratitude changes everything  
2. `03-world-feed-accept.png` — World feed + accept pending  
3. `04-compose.png` — New Appreciation (filled)  
4. `05-share-link.png` — Share / copy link after save  
5. `06-profile-cause.png` — Profile + cause  
6. `07-appearance.png` — Theme + alternate icons  
7. `08-stats-challenge.png` — Streak / 30 Days of Thanks  

## Suggested upload order (iPad)

**Do not upload welcome/sign-in with the age checkbox.** That asset lives under `_excluded/`.

1. `01-world-feed-share.png` — Home / feed (sidebar if captured)  
2. `07-compose.png` — Compose / thank someone  
3. `02-say-thanks-ways.png` — Share ways  
4. `04-profile.png` — Profile  
5. `06-stats.png` — Stats / streak  
6. `05-appearance.png` — Appearance  

Prefer a fresh native capture on **iPad Pro 13"** (2064×2752) when possible: Home sidebar + feed, compose sheet, success/share, accept pending, profile — gratitude-only frames.

## Intentionally omitted from store gallery

- Welcome / sign-in with “I am 18 or older” (see `_excluded/`)  
- Empty compose screen  
- Notifications list with “Test” sender  
- Notifications **settings** with **“Preview for reviewers”** (dev/review-only UI)

## Notes

- Status bar may show real simulator time (not 9:41). Apple accepts this.  
- For sharper native pixels: capture on **iPhone 17 Pro Max** (1320×2868) and **iPad Pro 13"** (2064×2752) with File → Save Screen.  
- Rehearsal notes: `AppStore/IPAD_REVIEW_REHEARSAL.md`
