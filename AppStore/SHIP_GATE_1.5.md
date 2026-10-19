# Ship gate — OpenThanks 1.5 (6) universal

## Done in-repo

- [x] Marketing version **1.5**, build **6** (`project.yml` → all app/extension targets)
- [x] Apple re-login splash hang fix on `main` (#54)
- [x] Stop blank auto-compose on returning launch (#55)
- [x] Home feed: overlap pending + feed fetches; cap personal-circle edge scan at 500
- [x] Unit tests: home-gate task id, semver compare, feed page size, compose draft
- [x] UI tests: welcome / age / email sheet; launch performance metric; optional demo login
- [x] What’s New + Review notes updated for 1.5

## Before upload (human / Mac)

1. `xcodegen` (if `project.yml` changed) then open `OpenThanks.xcodeproj`
2. Unit tests: `xcodebuild test -scheme OpenThanks -destination 'platform=iOS Simulator,name=iPhone 17'`
3. UI tests (offline): same command includes `OpenThanksUITests`
4. Optional network e2e: `RUN_NETWORK_E2E=1 xcodebuild test … -only-testing:OpenThanksUITests/DemoLoginUITests`
5. Archive → Upload to App Store Connect (build **1.5 (6)**)

## App Store Connect

1. Create version **1.5** → attach build **6**
2. Paste **What’s New** from `METADATA.md`
3. Paste Review notes from `REVIEW_NOTES.md` (demo: `test@test.com` / `PlayStoreTest2026!`)
4. Confirm iPhone 6.9" + iPad 13" screenshots still current
5. Internal TestFlight smoke: logout → Sign in with Apple; Home My/World scroll; Thank Someone send
6. Submit for Review

## Perf checklist

- [ ] Cold launch feels instant on a physical device (UI test records `XCTApplicationLaunchMetric`)
- [ ] Home My Feed for a heavy account does not stall on first open
- [ ] Logout → Apple sign-in never sticks on the heart splash
