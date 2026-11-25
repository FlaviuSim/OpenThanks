# send-apns Edge Function

Delivers iOS remote notifications through APNs using tokens in `device_push_tokens`.

## One-time Apple setup

1. [Apple Developer](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles**
2. Enable **Push Notifications** on App ID `com.openthanks.gratitude`
3. **Keys** → create a key with **Apple Push Notifications service (APNs)** → download the `.p8` (once)
4. Note **Key ID**, **Team ID** (`XA73L5SR8P` for OpenThanks), and keep the `.p8` contents

## Supabase secrets (Edge Function)

```bash
supabase secrets set \
  APNS_KEY="$(cat AuthKey_XXXXXX.p8 | sed ':a;N;$!ba;s/\n/\\n/g')" \
  APNS_KEY_ID="YOUR_KEY_ID" \
  APNS_TEAM_ID="XA73L5SR8P" \
  APNS_TOPIC="com.openthanks.gratitude"
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are usually injected automatically for Edge Functions.

## Deploy

```bash
cd /path/to/OpenThanks
supabase functions deploy send-apns --project-ref dsftvyuzmhlqadhbubgw
```

## Auto-fire on `notifications` INSERT

Apply migration `20261012_dispatch_notification_push.sql`, then `20261029_web_push_subscriptions.sql`. The second migration replaces the trigger so each allowlisted insert calls this function and `send-web-push`. Types:

- `gratitude_pending`
- `gratitude_received`
- `heart_received`
- `email_bounced`
- `competition_winner`

Store the service-role JWT in Vault once (trigger reads it; never commit the key):

```sql
select vault.create_secret(
  '<SERVICE_ROLE_JWT>',
  'send_apns_service_role',
  'Bearer for send-apns DB trigger'
);
```

If the vault secret is missing, notification inserts still succeed and push is skipped.

### Dashboard Webhook alternative

Dashboard → **Database** → **Webhooks** → create webhook on `public.notifications` **Insert**:

- URL: `https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-apns`
- HTTP headers: `Authorization: Bearer <service_role_key>`
- Body: either map `user_id`, `type`, `id` → `notification_id`, `gratitude_id`, **or** send the default webhook envelope — this function unwraps `{ type, record }` INSERT payloads.

## Test send

```bash
curl -i "https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-apns" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "USER_UUID",
    "title": "Test from OpenThanks",
    "body": "If you see this, APNs is working.",
    "data": { "type": "test" }
  }'
```

Debug builds register **sandbox** tokens; TestFlight / App Store use **production**. The function picks the host from each row’s `environment`.

## Related migrations

- `20261012_notify_recipient_on_gratitude_insert.sql` — inserts `gratitude_pending` when a pending appreciation is created for a member `recipient_id`
- `20261012_dispatch_notification_push.sql` — APNs fan-out trigger above
