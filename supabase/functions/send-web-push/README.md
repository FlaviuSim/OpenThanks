# send-web-push

Delivers the same remote notifications as `send-apns` to browsers and to the Android app.

Android is a Trusted Web Activity of `https://openthanks.com`. The app already has notification delegation (`POST_NOTIFICATIONS`, `DelegationService`). It does not register an FCM token. This function sends **Web Push** (VAPID) to a subscription stored on `device_push_tokens` with `platform = 'web'`. Chrome shows that notification in the TWA. No Firebase project and no Play Billing.

The website repo (`v0-gratitude-network`) was not available when this shipped. The sender and the token columns are in this repo. The service worker and the subscribe call still have to be added on the website. The exact change is below.

## What gets sent

Same allowlist as iOS, from `../_shared/push.ts`:

- `gratitude_pending`
- `gratitude_received`
- `heart_received`
- `email_bounced`
- `competition_winner`

Tap opens:

| Type | URL |
| --- | --- |
| `gratitude_pending`, `competition_winner` | `https://openthanks.com/notifications` |
| `gratitude_received`, `heart_received` | `https://openthanks.com/gratitude/{id}`, or `/notifications` when there is no id |
| `email_bounced` | `https://openthanks.com/pending?resend={id}` |

iOS opens the Personal feed's pending cards for `gratitude_pending`. The site has no separate URL for that section, so Android opens `/notifications`.

## 1. Generate VAPID keys (once)

From the repo root, with Deno installed:

```bash
~/.deno/bin/deno run --allow-env scripts/generate_vapid_keys.ts
```

The command prints three values. Do not commit them. Generating a new pair later invalidates every subscription.

## 2. Supabase secrets

Dashboard → **Edge Functions** → **Secrets** (project `open-thanks`, ref `dsftvyuzmhlqadhbubgw`), or the CLI.

| Secret | Value |
| --- | --- |
| `WEB_PUSH_VAPID_KEYS` | The JSON object the script prints (`publicKey` and `privateKey` JWKs). One line. |
| `WEB_PUSH_SUBJECT` | `mailto:founders@openthanks.com` |
| `WEB_PUSH_ORIGIN` | Optional. Defaults to `https://openthanks.com`. |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected for Edge Functions.

There is no `google-services.json`, no FCM server key, and no Firebase console step.

## 3. Apply the migration

Run `supabase/migrations/20261029_web_push_subscriptions.sql` in the SQL editor (or `supabase db push`). It:

- adds `p256dh` and `auth_key` on `device_push_tokens`
- allows `platform = 'web'`
- installs `dispatch_notification_push` so an allowlisted `notifications` insert POSTs to **both** `send-apns` and `send-web-push`

On 29 Oct 2026 the live database had **no** `dispatch_notification_push` trigger. Applying this migration is what starts the fan-out. Inserts still succeed if push fails.

The trigger reads the Vault secret `send_apns_service_role` (the service-role JWT). The name is the existing one; it authorizes both functions.

Dashboard → **Project Settings** → **Vault** → New secret, if it is not already there:

- Name: `send_apns_service_role`
- Secret: the project **service_role** key (Project Settings → API)

If a Dashboard **Database Webhook** on `public.notifications` INSERT already calls `send-apns`, remove it when you apply this migration. Leaving both in place sends each iOS notification twice.

## 4. Deploy

From the repo root so the `_shared` import is bundled:

```bash
supabase functions deploy send-web-push --project-ref dsftvyuzmhlqadhbubgw
supabase functions deploy send-apns --project-ref dsftvyuzmhlqadhbubgw
```

`send-apns` must be redeployed with this change. Alert copy now lives in `supabase/functions/_shared/push.ts`. iOS delivery behavior is unchanged: it still selects `platform = 'ios'` only.

`config.toml` sets `verify_jwt = false` for this function. POST checks the service-role JWT itself. GET returns only the public application server key.

## 5. Website changes (still required)

In `v0-gratitude-network`, the published worker is `https://openthanks.com/sw.js`. It precaches `/offline.html` and icons and has **no** `push` handler. Add the following to that worker. Leave the existing `install`, `activate`, and `fetch` listeners in place.

Set `NEXT_PUBLIC_VAPID_PUBLIC_KEY` to the application server key the script prints (the base64url line, not the JWK).

```javascript
self.addEventListener('push', (event) => {
  let payload = {}
  try {
    payload = event.data ? event.data.json() : {}
  } catch {
    payload = { title: 'OpenThanks', body: event.data ? event.data.text() : '' }
  }

  const title = payload.title || 'OpenThanks'
  const url = payload.url || 'https://openthanks.com/notifications'
  event.waitUntil(
    self.registration.showNotification(title, {
      body: payload.body || '',
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      tag: payload.tag || 'openthanks',
      data: { url, ...(payload.data || {}) },
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = event.notification.data?.url || 'https://openthanks.com/notifications'
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    for (const client of all) {
      if (!client.url.startsWith(self.location.origin)) continue
      if ('navigate' in client) await client.navigate(url)
      return client.focus()
    }
    if (self.clients.openWindow) return self.clients.openWindow(url)
  })())
})
```

Subscribe after the user is signed in, with the same Supabase browser client the site already uses. Call `registerWebPush` from a click (the permission prompt must be a user gesture the first time). On later visits, if permission is already `granted`, call it again so the endpoint stays saved. The Android TWA shows Chrome's permission dialog through the existing `DelegationService`. Do not add notification UI in the Android project.

```javascript
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(base64)
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i += 1) bytes[i] = raw.charCodeAt(i)
  return bytes
}

export async function registerWebPush(supabase) {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return
  if (!('Notification' in window)) return
  const permission = await Notification.requestPermission()
  if (permission !== 'granted') return

  const registration = await navigator.serviceWorker.ready
  const existing = await registration.pushManager.getSubscription()
  const subscription = existing ?? await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(
      process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,
    ),
  })
  const json = subscription.toJSON()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user || !json?.endpoint || !json.keys?.p256dh || !json.keys?.auth) return

  const { error } = await supabase.from('device_push_tokens').upsert({
    user_id: user.id,
    token: json.endpoint,
    platform: 'web',
    environment: 'production',
    p256dh: json.keys.p256dh,
    auth_key: json.keys.auth,
  }, { onConflict: 'token' })
  if (error) console.error('Could not save web push subscription', error)
}
```

On sign-out, delete the row and unsubscribe so the next person on the device does not receive the previous account's alerts:

```javascript
export async function unregisterWebPush(supabase) {
  const registration = await navigator.serviceWorker.ready
  const subscription = await registration.pushManager.getSubscription()
  if (!subscription) return
  await supabase.from('device_push_tokens').delete().eq('token', subscription.endpoint)
  await subscription.unsubscribe()
}
```

Row-level security already lets a signed-in user insert, update, and delete only their own `device_push_tokens` rows. The endpoint is the unique `token`. `p256dh` and `auth_key` are required when `platform` is `web`.

## 6. Test

Public key (must match `NEXT_PUBLIC_VAPID_PUBLIC_KEY`):

```bash
curl -s "https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-web-push"
```

Send to every web subscription for a user:

```bash
curl -s "https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-web-push" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "USER_UUID",
    "type": "gratitude_pending"
  }'
```

`{"ok":true,"sent":0,"skipped":"web_push_not_configured"}` means `WEB_PUSH_VAPID_KEYS` is not set. `skipped: "no_tokens"` means that user has no `platform = 'web'` row yet. A `410` or `404` from the push service deletes that row.

Until the website subscribe code is deployed, Android still has nothing to show. The TWA shell does not need another release for push to start working.

## Tests

```bash
~/.deno/bin/deno test --allow-env --allow-net \
  supabase/functions/_shared/push_test.ts \
  supabase/functions/send-web-push/handler_test.ts \
  supabase/functions/send-web-push/vapid_test.ts
```
