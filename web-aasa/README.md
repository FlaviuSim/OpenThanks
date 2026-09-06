# Apple App Site Association (deploy to openthanks.com)

Canonical production copies live in the web repo:

`v0-gratitude-network/public/.well-known/apple-app-site-association`  
`v0-gratitude-network/public/apple-app-site-association`

## Current App IDs

| App | `appID` (`TEAMID.bundle`) |
| --- | --- |
| **New** (this Xcode project) | `XA73L5SR8P.com.openthanks.gratitude` |
| Old TestFlight (kept for transition) | `53CL59ATX8.com.openthanks.app` |

After changing AASA, deploy the web app, then validate:

https://app-site-association.cdn-apple.com/a/v1/openthanks.com

Apple caches aggressively — allow minutes to hours, then delete/reinstall the app if links still open in Safari.
