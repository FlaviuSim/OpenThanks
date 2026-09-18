# App Review Notes — paste into App Store Connect

Copy everything inside the box below into **App Review Information → Notes**.

```
DEMO ACCOUNT (no OTP / no inbox needed)
1. On welcome → Continue with Email
2. Enter: test@test.com
3. Tap Continue — the app signs in with the review password automatically (do not wait for email).
   Email: test@test.com
   Password (if prompted anywhere): PlayStoreTest2026!

Confirm 18+ on the age checkbox if shown.

CORE FLOW TO DEMO
1. Home → compose (+) → write a short appreciation → send (email / text / copy link).
2. Accept: open a pending “waiting for you” card on Home, or open an openthanks.com claim link.
3. Profile → Received to confirm it landed.

SIGN-IN OPTIONS ALSO AVAILABLE
• Sign in with Apple (welcome screen)
• Phone SMS OTP
• Google / LinkedIn (OAuth)

PAYMENTS (Guideline 3.1.1)
No in-app purchases, subscriptions, or external payment / donate CTAs in the iOS app.
Nonprofit honor donations exist only on the website and are not linked from iOS purchase paths.

UGC — REPORT & BLOCK (Guideline 1.2)
• Appreciation → ⋯ → Block author + Report
• Other profile → ⋯ → Block + Report
Reports go to founders@openthanks.com. Blocked users are hidden from the blocker’s feeds/search.

AGE
Terms/Privacy require 18+. Sign-in confirms “I am 18 or older.”

ACCOUNT DELETION (Guideline 5.1.1v)
Settings → Delete Account (below Log Out). Permanent; no email required.
Please do not delete this demo account during review.

OPTIONAL PERMISSIONS (decline does not block core use)
Photos, Mic/Speech (Speak-to-write), Notifications, Apple/Google Calendar (evening thank-you suggestions only; calendar data stays on device), Siri Shortcuts.

LINKS
Privacy: https://openthanks.com/privacy
Terms: https://openthanks.com/terms
Support: https://openthanks.com/support
Contact: founders@openthanks.com

EXPORT COMPLIANCE
Uses only exempt encryption (HTTPS). ITSAppUsesNonExemptEncryption = false.
```

---

# Day-of-submit — order of clicks

Do this **after** the Release build is uploaded and processed (email / Build appears as Ready to Submit).

### A. Xcode (once)

1. Open **OpenThanks.xcodeproj** → scheme **OpenThanks** → **Any iOS Device (arm64)**  
2. **Product → Archive**  
3. Organizer → select archive → **Distribute App** → **App Store Connect** → **Upload**  
4. Wait until the build finishes processing in App Store Connect (can take 10–40+ min)

### B. App Store Connect — listing (if not already done)

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **OpenThanks**  
2. Left sidebar → version under **iOS App** (e.g. **1.0.0** Prepare for Submission)  
3. Fill / confirm: **iPhone** screenshots only (remove iPad media if present), description, keywords, support URL, marketing URL, privacy URL  
4. **Age Rating** → questionnaire → **18+** (UGC / social / personal info)  
5. **App Privacy** → nutrition labels (see `METADATA.md`) → **Tracking = No**  
6. **Build** → **+** → select processed **1.1 (6)** (iPhone-only) → Done  

### C. App Review Information (this page)

1. Same version page → scroll to **App Review Information**  
2. **Sign-in required** = Yes  
3. **User name** = `test@test.com`  
4. **Password** = `PlayStoreTest2026!`  
5. **Notes** = paste the box above  
6. Contact: your phone + `founders@openthanks.com`  
7. **Attachment** = optional (skip unless Apple asked)

### D. Submit

1. Top right → **Add for Review** (or **Submit for Review**)  
2. Answer export compliance if asked → **No** (exempt / HTTPS only) — already set in Info.plist  
3. Confirm content rights / advertising ID if asked → **No** advertising identifier / no tracking  
4. **Submit to App Review**  
5. Status should move to **Waiting for Review**

### E. Resolution Center reply (rejection resubmit — Watch icon + metadata)

Paste after uploading **1.1 (7)**, updating Connect **Description** + **What’s New** from `METADATA.md`, and selecting that build:

```
Thank you for the feedback.

1) Apple Watch icon (Guideline 4)
We replaced the Watch app icon background with a light cream color so the icon reads as a clear circle on watchOS (no longer blends into the black Watch face). Please review build 1.1 (7).

2) Marketing / description (Guideline 1.1)
OpenThanks is a gratitude app for sending thank-you notes — not adult, dating, or objectionable content. We revised the App Store description and What’s New to describe only thank-you notes, recipient accept-before-share, and community kindness. There is no marketing of objectionable content or services. In-app Report and Block are available for UGC safety.

Demo account unchanged: test@test.com / PlayStoreTest2026!
```

### F. Do not

- Delete or change password on `test@test.com` until review finishes  
- Ship a build that still points at old bundle / TestFlight-only secrets  
- Leave Stripe / donate / IAP UI in Settings (should already be gone)  
- Upload or leave iPad screenshots while the binary is iPhone-only  
- Archive a universal (`1,2`) binary by mistake — confirm Devices = iPhone in the archive’s Info before upload  
- Leave “18+”, adult, dating, or unrestricted-media language in Description / What’s New / promo text  
- Resubmit without replacing the Watch icon (black background will fail Guideline 4 again)
