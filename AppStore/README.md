# App Store asset pack

Everything here is ready for App Store Connect (plus the icons already wired into the Xcode project).

## Contents

| Path | Purpose |
|------|---------|
| `Icons/AppStore-Icon-1024.png` | 1024×1024 App Store icon (opaque) |
| `Screenshots/iPhone-6.9-inch/` | **Primary** iPhone screenshots (1320×2868) |
| `Screenshots/iPad-13-inch/` | **Primary** iPad screenshots (2064×2752) |
| `Screenshots/iPhone-6.7-inch/` | Optional (1290×2796) |
| `Screenshots/iPhone-6.5-inch/` | Optional (1284×2778) |
| `Screenshots/README.md` | Upload order + what was omitted |
| `METADATA.md` | Copy/paste listing text, keywords, privacy labels |
| `REVIEW_NOTES.md` | Paste-ready App Review notes + day-of-submit click order |
| `../OpenThanks/Assets.xcassets/AppIcon.appiconset/` | In-app icons (light / dark / tinted) |
| `../OpenThanks/PrivacyInfo.xcprivacy` | Required privacy manifest |

## Regenerate marketing screenshots

```bash
python3 scripts/generate_appstore_assets.py
```

(Requires Pillow: `python3 -m pip install pillow`)

## Submit flow

1. Fill App Store Connect listing from `METADATA.md` (age questionnaire, privacy labels)
2. Follow day-of clicks in `REVIEW_NOTES.md` (archive → build → review notes → submit)
3. Confirm Settings has **no** Stripe/Subscribe CTA; Report works on appreciation + profile
4. Upload screenshots from `Screenshots/iPhone-6.9-inch/` then `Screenshots/iPad-13-inch/` (see `Screenshots/README.md`)
5. In Xcode: select **Any iOS Device** → **Product → Archive** → **Distribute App**
6. Complete App Privacy questionnaire using the labels in `METADATA.md`
7. Paste review notes from `REVIEW_NOTES.md`; do not delete `test@test.com` during review
