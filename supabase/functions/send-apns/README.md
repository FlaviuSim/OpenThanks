# send-apns Edge Function

Delivers iOS remote notifications through APNs using tokens in `device_push_tokens`.

## One-time Apple setup

1. [Apple Developer](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles**
2. Enable **Push Notifications** on App ID `com.openthanks.gratitude`
3. **Keys** → create a key with **Apple Push Notifications service (APNs)** → download the `.p8` (once)
4. Note **Key ID**, **Team ID** (`53CL59ATX8` for OpenThanks), and keep the `.p8` contents

## Supabase secrets

```bash
supabase secrets set \
  APNS_KEY="$(cat AuthKey_XXXXXX.p8 | sed ':a;N;$!ba;s/\n/\\n/g')" \
  APNS_KEY_ID="YOUR_KEY_ID" \
  APNS_TEAM_ID="53CL59ATX8" \
  APNS_TOPIC="com.openthanks.gratitude"
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are usually injected automatically for Edge Functions.

## Deploy

```bash
cd /path/to/OpenThanks
supabase functions deploy send-apns --project-ref dsftvyuzmhlqadhbubgw
```

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

## Wire later (optional)

Dashboard → **Database** → **Webhooks** → create webhook on `public.notifications` **Insert**:

- URL: `https://dsftvyuzmhlqadhbubgw.supabase.co/functions/v1/send-apns`
- HTTP headers: `Authorization: Bearer <service_role_key>`
- Body: map `user_id`, `type`, `id` → `notification_id`, `gratitude_id`

Or call the same URL from a Next.js API / cron after inserting a notification.
