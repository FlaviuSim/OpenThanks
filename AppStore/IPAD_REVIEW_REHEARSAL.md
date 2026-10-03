# iPad App Review dress rehearsal (Phase 0)

Date: 2026-10-02  
Method: Code-path audit + iPad Pro 13" Simulator build (universal `1,2`).  
Demo account: `test@test.com` / `PlayStoreTest2026!` (from `REVIEW_NOTES.md`).

## A. First launch / auth

| # | Check | Result | Notes |
|---|--------|--------|-------|
| 1 | Welcome CTAs gated on 18+ | PASS | Overlay + disabled until `AgeConfirmationToggle` |
| 2 | `test@test.com` auto password sign-in | PASS | `isTestAccountEmail` bypasses OTP |
| 3 | Email OTP verify on iPad | PASS (code) | Fixed in `8232d5d`; sheet uses `.large` on regular |
| 4 | Onboarding Continue tappable | PASS | No `.tabViewStyle(.page)`; comment lock kept |
| 5 | Optional permissions skippable | PASS | Core flow not blocked |

## B. Home shell

| # | Check | Result | Notes |
|---|--------|--------|-------|
| 6 | Sidebar chrome / no double Thank CTA | PASS | `usesSidebar` + Feed hides FAB |
| 7 | Empty detail intentional | **FAIL→FIXED** | System `ContentUnavailableView` felt sparse; branded placeholder |
| 8 | List↔detail selection | PASS | `splitSelection` wiring present |
| 9 | Compact → phone tab bar | PASS | `horizontalSizeClass` switch |

## C. Core UGC loop

| # | Check | Result | Notes |
|---|--------|--------|-------|
| 10 | Compose sheet readable width | PASS | `composeCover` maxWidth 640 |
| 11 | No leaked member phone on share | PASS | `b2872e3` |
| 12 | Report + Block | PASS | Existing Guideline 1.2 paths |
| 13 | Delete Account visible | PASS | Settings |

## D. Multitasking / keyboard

| # | Check | Result | Notes |
|---|--------|--------|-------|
| 14 | Compact↔regular mid-compose | **FAIL→FIXED** | Sheet/fullScreenCover tore on size-class flip; lock mode while open |
| 15 | Landscape usable | PASS (layout) | Readable columns + split |
| 16 | Sheet CTAs vs keyboard | **FAIL→FIXED** | Add-link was `.medium` only; enjoyment sheet now scroll + large detent |
| 17 | Keyboard inset Stage Manager | **FAIL→FIXED** | Was `UIScreen.main`; now key-window overlap |

## E. Connect / marketing (Guideline 1.1)

| # | Check | Result | Notes |
|---|--------|--------|-------|
| 18 | No age-gate hero screenshot | **FAIL→FIXED** | Docs + upload order; exclude `03-welcome-signin` |
| 19 | Gratitude-only copy | PASS | Keep METADATA rules; What’s New mentions iPad |
| 20 | Watch cream icon | PASS | Prior Guideline 4 fix retained |

## Exit

Phase 1 addresses FAIL rows. Device family flip and Connect package follow.
