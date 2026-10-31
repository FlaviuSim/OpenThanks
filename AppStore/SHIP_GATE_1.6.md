# Ship gate — OpenThanks 1.6 (1) universal

## Done in-repo

- [x] Marketing version **1.6**, build **1** (`project.yml` → all app/extension targets)
- [x] Update banner itunes lookup once per **cold launch**
- [x] Apple re-login splash hang fix
- [x] Stop blank auto-compose on returning launch
- [x] Two-step compose polish (autofocus, deliver preview/email/copy)
- [x] Home Decline removes pending card immediately
- [x] Calendar nudge: don’t thank yourself; first-person drafts
- [x] Push token reassign RPC for multi-account devices
- [x] What’s New + Review notes updated for 1.6

## Before upload (human / Mac)

1. `xcodegen` (if `project.yml` changed) then open `OpenThanks.xcodeproj`
2. Unit tests: `xcodebuild test -scheme OpenThanks -destination 'platform=iOS Simulator,name=iPhone 17'`
3. Archive → Upload to App Store Connect (build **1.6 (1)**)

## App Store Connect

1. Create / open version **1.6** → attach build **1**
2. Paste **What’s New** from `METADATA.md`
3. Paste Review notes from `REVIEW_NOTES.md` (demo: `test@test.com` / `PlayStoreTest2026!`)
4. Confirm iPhone 6.9" + iPad 13" screenshots still current
5. Internal TestFlight smoke: logout → Sign in with Apple; Home My/World scroll; Thank Someone send
6. Submit for Review
