# Ticket: Track notification opt-in and calendar linking in PostHog (iOS)

## Why
We can't answer two basic launch questions: how many people turned on notifications, and how many linked a calendar. PostHog (project 458812) has no event or person property for either one. Right now the only proxies are people who *tapped* a push (`notification_friday_tap`, `notification_friday`, `notification_calendar_nudge` sources on `appreciation_form_started` / `appreciation_submitted`) and people who started from `calendar_evening_nudge`. Those undercount badly.

Since the Oct 1 App Store launch: 29 non-founder installs, but only 2 signed in and 1 posted. We need opt-in data to understand the funnel.

## What to add

### Events
| Event | When | Properties |
|---|---|---|
| `push_permission_prompted` | System notification prompt (or our pre-prompt) is shown | `source` (onboarding / settings / nudge), `pre_prompt` (bool) |
| `push_permission_granted` | User allows notifications | `source`, `authorization_status` (authorized / provisional / ephemeral) |
| `push_permission_denied` | User denies | `source` |
| `push_token_registered` | APNs token successfully registered | (no token value) |
| `calendar_permission_prompted` | EventKit / calendar access prompt shown | `source` |
| `calendar_connected` | Calendar access granted or a calendar account linked | `provider` (apple_eventkit / google / other), `access_level` (full / write_only), `source` |
| `calendar_permission_denied` | Calendar access denied | `source` |
| `calendar_disconnected` | User revokes or unlinks | `provider` |

### Person properties (`$set`)
- `push_enabled` (bool), updated on every app launch from `UNUserNotificationCenter.getNotificationSettings`, so it catches changes made in iOS Settings
- `push_authorization_status` (string)
- `calendar_linked` (bool), with `calendar_provider`, also re-checked on launch
- `first_push_enabled_at` / `first_calendar_linked_at` (`$set_once`)

## Notes
- Re-check the authorization status on each foreground or launch and `$set` the person property, since users change these in iOS Settings outside the app.
- Make sure the events fire for anonymous users too, so they get merged correctly on sign-in (`identify`).
- Don't send push tokens or calendar contents to PostHog.
- Optional: if the backend already stores push tokens or calendar connections, add a one-time backfill of `push_enabled` / `calendar_linked` for existing users.

## Done when
- In PostHog, a test device shows `push_permission_prompted` then granted/denied, `calendar_connected`, and the person has `push_enabled` / `calendar_linked` set correctly.
- Toggling notifications off in iOS Settings, then reopening the app, flips `push_enabled` to false.
- Bonus: a PostHog funnel Installed → Signed in → Push enabled → Calendar linked → First public post.

## External share tracking

`appreciation_shared` stopped arriving after iOS 1.0.2 (last event Sep 10, 2026). 1.1 and 1.2 never sent it because the share screens people actually use — the post-save share screen and Pending Appreciations — did not capture, and the public post’s system share sheet counted the sheet opening instead of a finished share.

The event fires again on every completed external share:

| Property | Value |
|---|---|
| `channel` | `instagram_stories`, `linkedin`, `x`, `facebook`, `whatsapp`, `copy_link`, `text`, `email`. System share sheet: the completion handler’s activity type, mapped to those names when it is a known app, otherwise the raw activity type (`system_sheet` only when the type is missing). |
| `voice` | `author`, `recipient`, or `viewer` |
| `platform` | `ios` |
| `has_card` | bool — composed story/poster image was included |
| `has_photo` | bool — the appreciation has a still photo |
| `appreciation_id` | gratitude UUID (lowercase) |

Cancelled system share sheets are not counted. OpenThanks “Email Reminder” (the server sends it) is not an external share.
