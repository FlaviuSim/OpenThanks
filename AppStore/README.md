# App Store asset pack

Everything here is ready for App Store Connect (plus the icons already wired into the Xcode project).

## Contents

| Path | Purpose |
|------|---------|
| `Icons/AppStore-Icon-1024.png` | 1024×1024 App Store icon (opaque) |
| `Screenshots/iPhone-6.9-inch/` | **Primary** iPhone screenshots (1320×2868) |
| `Screenshots/iPhone-6.7-inch/` | Optional (1290×2796) |
| `Screenshots/iPhone-6.5-inch/` | Optional (1284×2778) |
| `Screenshots/iPad-13-inch/` | **iPad** screenshots (2064×2752) — upload for universal 1.2 |
| `Screenshots/iPad-12.9-inch/` | Optional / if Connect asks (2048×2732) |
| `Screenshots/_excluded/` | Age-gate welcome frames — **do not upload** |
| `Screenshots/README.md` | Upload order + what was omitted |
| `METADATA.md` | Copy/paste listing text, keywords, privacy labels |
| `REVIEW_NOTES.md` | Paste-ready App Review notes + day-of-submit click order |
| `IPAD_REVIEW_REHEARSAL.md` | Phase 0 pass/fail before universal ship |
| `../OpenThanks/Assets.xcassets/AppIcon.appiconset/` | In-app icons (light / dark / tinted) |
| `../OpenThanks/PrivacyInfo.xcprivacy` | Required privacy manifest |

## Regenerate marketing screenshots

```bash
python3 scripts/generate_appstore_assets.py
```

(Requires Pillow: `python3 -m pip install pillow`)

## Submit flow (universal 1.2)

1. Fill App Store Connect listing from `METADATA.md` (age questionnaire, privacy labels)
2. Follow day-of clicks in `REVIEW_NOTES.md` (archive → build → review notes → submit)
3. Confirm Settings has **no** Stripe/Subscribe CTA; Report works on appreciation + profile
4. Upload **iPhone** screenshots from `Screenshots/iPhone-6.9-inch/` **and** iPad from `Screenshots/iPad-13-inch/` (skip `_excluded/`)
5. In Xcode: select **Any iOS Device** → **Product → Archive** → **Distribute App** (build **1.2 (1)** — Devices = iPhone + iPad)
6. Complete App Privacy questionnaire using the labels in `METADATA.md`
7. Paste review notes from `REVIEW_NOTES.md`; do not delete `test@test.com` during review
