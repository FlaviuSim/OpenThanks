# App Review Notes — paste into App Store Connect

Copy everything inside the box below into **App Review Information → Notes**.

```
UNIVERSAL APP — iPhone + iPad (build 1.8). On iPad, Home uses a sidebar; Thank Someone is in the sidebar. On iPhone, compose is the + button beside the floating tab bar.

DEMO ACCOUNT (no OTP / no inbox needed)
1. On welcome → Continue with Email
2. Enter: test@test.com
3. Tap Continue — the app signs in with the review password automatically (do not wait for email).
   Email: test@test.com
   Password (if prompted anywhere): PlayStoreTest2026!

Confirm 18+ on the age checkbox if shown.

CORE FLOW TO DEMO
1. Home → + (compose) / Thank Someone → write a short appreciation → send (email / text / copy link).
2. Accept / Keep: open a pending “waiting for you” card on Home, or open an openthanks.com claim link → Keep this thank-you.
3. Profile → Received to confirm it landed.
4. Optional — after accepting, the pay-it-forward sheet may suggest who to thank next (this week / never thanked / calendar). Decline anytime.
5. Optional — Settings → Notifications → connect Apple or Google Calendar. Evening thank-you suggestions only. Connecting asks for explicit consent before any calendar history (titles, attendees, times, notes) syncs to OpenThanks servers for thank suggestions/drafts. Decline calendar / skip sync — core thank-you flows still work. Disconnect or “Delete calendar data from OpenThanks” anytime in Settings.

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
Photos, Mic/Speech (Speak-to-write), Notifications, Apple/Google Calendar (optional thank-you suggestions; with consent, minimized history including notes may sync to OpenThanks only for suggestions/drafts — never ads; wipe on disconnect/delete), Siri Shortcuts.

LINKS
Privacy: https://openthanks.com/privacy
Google Calendar / Limited Use: https://openthanks.com/privacy#google-user-data
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
2. Confirm **Marketing Version 1.8** and bump **Current Project Version** if this build number was already uploaded  
3. **Product → Archive**  
4. Organizer → select archive → **Distribute App** → **App Store Connect** → **Upload**  
5. Wait until the build finishes processing in App Store Connect (can take 10–40+ min)

### B. App Store Connect — listing (if not already done)

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **OpenThanks**  
2. Left sidebar → version under **iOS App** (**1.8** Prepare for Submission)  
3. Fill / confirm: **iPhone + iPad** screenshots (skip age-gate welcome frames), description, keywords, support URL, marketing URL, privacy URL  
4. **Age Rating** → questionnaire → Social Networking + UGC — do **not** market as adult content in Description  
5. **App Privacy** → nutrition labels (see `METADATA.md`) → **Tracking = No**; Calendar Events = App Functionality  
6. **Build** → **+** → select processed **1.8 (N)** (universal iPhone + iPad) → Done  

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

### E. Resolution Center reply (if calendar 5.1.1(iv) comes up again)

```
Thank you for the feedback on Guideline 5.1.1(iv).

After our custom calendar rationale, the user continues by choosing Apple Calendar (system permission) or Google Calendar. There is no “Not now” that skips the system Calendar prompt when they choose Apple Calendar. If they deny, we respect that choice and continue; core thank-you flows do not require Calendar.

Optional server sync of calendar history (including notes) for thank-you suggestions requires a separate explicit consent. Users can disconnect or delete calendar data from OpenThanks in Settings. See https://openthanks.com/privacy#google-user-data

Demo account unchanged: test@test.com / PlayStoreTest2026!
```

### F. Do not

- Delete or change password on `test@test.com` until review finishes  
- Ship a build that still points at old bundle / TestFlight-only secrets  
- Leave Stripe / donate / IAP UI in Settings (should already be gone)  
- Upload welcome/sign-in screenshots that show the “I am 18 or older” checkbox (Guideline 1.1)  
- Archive an iPhone-only (`1`) binary by mistake — confirm Devices = **iPhone + iPad** in the archive’s Info before upload  
- Leave “18+”, adult, dating, or unrestricted-media language in Description / What’s New / promo text  
- Claim calendar stays “on device only” in Review Notes — that is no longer accurate after optional server sync consent  
