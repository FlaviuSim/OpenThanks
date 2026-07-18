# Apple App Site Association (deploy to openthanks.com)

Copy `public/.well-known/apple-app-site-association` into the Next.js web app's `public/.well-known/` folder (no `.json` extension).

- Team ID: `53CL59ATX8` (Flavma Inc. / App Store signing team)
- App ID: `53CL59ATX8.com.openthanks.app`
- Paths: `/claim/*`, `/for/*`, `/gratitude/*`, and `/{username}` profiles (marketing paths excluded)

Serve with `Content-Type: application/json` and **no redirects**. Apex and www must both return 200 for this file.

Validate: https://app-site-association.cdn-apple.com/a/v1/openthanks.com
