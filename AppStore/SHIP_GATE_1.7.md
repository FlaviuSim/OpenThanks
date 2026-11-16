# Ship gate — OpenThanks 1.7 (1) universal

## Done in-repo

- [x] Marketing version **1.7**, build **1** (`project.yml` → all app/extension targets)
- [x] Home chrome: full-width feed, floating tab pill, compose FAB, compact campaign, scroll-hide
- [x] Home people search results scroll within the screen
- [x] Keep as primary thank-you / claim accept action; clearer claim email + share nudges
- [x] What’s New + Review notes updated for 1.7

## Before upload (human / Mac)

1. `xcodegen` (if `project.yml` changed) then open `OpenThanks.xcodeproj`
2. Archive → Upload to App Store Connect (build **1.7 (1)**)

## App Store Connect

1. Create / open version **1.7** → attach build **1**
2. Paste **What’s New** from `METADATA.md`
3. Paste Review notes from `REVIEW_NOTES.md` (demo: `test@test.com` / `PlayStoreTest2026!`)
4. Submit for Review
