# App Store asset pack

Everything here is ready for App Store Connect (plus the icons already wired into the Xcode project).

## Contents

| Path | Purpose |
|------|---------|
| `Icons/AppStore-Icon-1024.png` | 1024×1024 App Store icon (opaque) |
| `Screenshots/iPhone-6.7-inch/` | Required modern iPhone screenshots (1290×2796) |
| `Screenshots/iPhone-6.5-inch/` | Additional size (1284×2778) |
| `METADATA.md` | Copy/paste listing text, keywords, review notes, privacy labels |
| `../OpenThanks/Assets.xcassets/AppIcon.appiconset/` | In-app icons (light / dark / tinted) |
| `../OpenThanks/PrivacyInfo.xcprivacy` | Required privacy manifest |

## Regenerate marketing screenshots

```bash
python3 scripts/generate_appstore_assets.py
```

(Requires Pillow: `python3 -m pip install pillow`)

## Submit flow

1. Fill App Store Connect listing from `METADATA.md`
2. Upload screenshots from `Screenshots/iPhone-6.7-inch/` (order 01→05)
3. In Xcode: select **Any iOS Device** → **Product → Archive** → **Distribute App**
4. Complete App Privacy questionnaire using the labels in `METADATA.md`
5. Submit for review with the demo notes
