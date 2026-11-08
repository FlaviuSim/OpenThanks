# Ship gate — OpenThanks 1.7 (1) universal

## Done in-repo

- [x] Marketing version **1.7**, build **1** (`project.yml` → all app/extension targets)
- [x] Share invite copy matches appreciation language (incl. Romanian)
- [x] Profile Thank Someone drafts save/restore like blank compose
- [x] Guess deliver recipient from note when name/email empty
- [x] What’s New + Review notes updated for 1.7

## Before upload (human / Mac)

1. `xcodegen` (if `project.yml` changed) then open `OpenThanks.xcodeproj`
2. Archive → Upload to App Store Connect (build **1.7 (1)**)

## App Store Connect

1. Create / open version **1.7** → attach build **1**
2. Paste **What’s New** from `METADATA.md` (1.7 delta only vs live 1.6)
3. Paste Review notes from `REVIEW_NOTES.md` (demo: `test@test.com` / `PlayStoreTest2026!`)
4. Submit for Review
