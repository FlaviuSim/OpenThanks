# Ship gate — OpenThanks 1.2 (1) universal

## Done in-repo / CI machine

- [x] Phase 0 rehearsal log: `IPAD_REVIEW_REHEARSAL.md`
- [x] Phase 1 iPad hardenings (compose lock, keyboard window, split placeholders, sheet detents)
- [x] `TARGETED_DEVICE_FAMILY = 1,2` for app / widget / share; Watch stays `4`
- [x] Version **1.2 (1)**
- [x] Debug builds: iPhone 17 Pro sim + iPad Pro 13" sim
- [x] Release archive: `UIDeviceFamily = {1,2}`; iPad alternate icons present
- [x] Uploaded IPA to App Store Connect (`xcodebuild -exportArchive` → Upload succeeded)
- [x] App launched on iPad Pro 13" Simulator (`com.openthanks.gratitude`)

## Remaining in App Store Connect (human)

1. Wait for build **1.2 (1)** to finish processing  
2. Create / open version **1.2** → attach build  
3. Upload iPhone 6.9" + iPad 13" screenshots per `Screenshots/README.md` (skip `_excluded/`)  
4. Paste Description / What’s New from `METADATA.md`  
5. Paste App Review notes from `REVIEW_NOTES.md`  
6. Internal TestFlight: re-run Phase 0 script on a **physical iPad** once  
7. Submit for Review  

Demo account unchanged: `test@test.com` / `PlayStoreTest2026!`
