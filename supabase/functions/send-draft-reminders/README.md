# send-draft-reminders

Sends the unsent-thank-you nudge that the phone cannot send by itself.

- No notification permission, or a website draft with no device token: email about 24 hours later.
- A push was scheduled (local on iOS, or one remote APNs for a website draft when `device_push_tokens` has a row): email about 48 hours later, and only if that push was not opened.
- Sending, clearing, or opening the push deletes or flags the row so the email does not go out.
- `profiles.email_unsubscribed` is skipped. The note is included in the email because the live website form prefills only the recipient (`?for=`), not the message. The link does not contain the note.

## Secrets

```bash
supabase secrets set \
  RESEND_API_KEY="re_..." \
  DRAFT_REMINDER_FROM="OpenThanks <notifications@openthanks.com>"
```

`DRAFT_REMINDER_FROM` must be a sender Resend already verifies for openthanks.com (the same from-address as claim emails). `RESEND_FROM` is an accepted alias. If either secret is missing, the function returns `missing_resend_config` and does not mark drafts as emailed.

## Schedule

Migration `20261017_compose_draft_reminders.sql` schedules `compose-draft-reminders` every 5 minutes when `pg_cron` and `pg_net` are available. The job sends header `x-openthanks-cron: compose-draft-reminders`. The function only delivers rows that are already due. It does not enable the separate `send_apns_service_role` push trigger.

Apply the migration, deploy this function, then confirm the job:

```sql
select jobname, schedule from cron.job where jobname = 'compose-draft-reminders';
```

## Website

Signed-in web and Android (the site inside the TWA) call the same RPC the iOS app calls. On leaving the form with text:

```js
await supabase.rpc("upsert_compose_draft", {
  p_id: null,
  p_recipient: recipientName,
  p_message: message,
  p_push_scheduled: false,
  p_origin: "web",
});
```

After a successful send, or when the form is cleared:

```js
await supabase.rpc("delete_compose_draft");
```

The email opens `https://openthanks.com/gratitude/new?for=Name&source=draft_reminder`, which the current site already prefills. Restoring the message into that form still requires the website to load this row (or the note quoted in the email).
