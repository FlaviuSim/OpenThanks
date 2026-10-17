/**
 * send-draft-reminders — email (and one remote push) for an unsent thank-you.
 *
 * Called by pg_cron every few minutes with the service role key. Signed-in
 * users cannot invoke it. With no Resend secret the function returns without
 * claiming rows, so a missing key does not burn the retry budget.
 *
 * Secrets (Dashboard → Edge Functions → Secrets):
 *   RESEND_API_KEY        Resend API key (same account the website uses)
 *   DRAFT_REMINDER_FROM   Verified from address, e.g. OpenThanks <notifications@openthanks.com>
 *                         RESEND_FROM is accepted as an alias
 *
 * The note is emailed to the author's own address. It is not written to logs.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  emailContent,
  shouldSendEmail,
  shouldSendPush,
  type ReminderDraft,
} from "./reminders.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ProfileRow = {
  id: string;
  email: string | null;
  email_unsubscribed: boolean | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    assertServiceRole(req);
    const supabase = adminClient();
    const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const from = (Deno.env.get("DRAFT_REMINDER_FROM") ?? Deno.env.get("RESEND_FROM") ?? "")
      .trim();

    const pushed = await deliverPushes(supabase);
    if (!resendKey || !from) {
      return json({
        ok: true,
        pushed,
        emailed: 0,
        skipped: "missing_resend_config",
      });
    }

    const emailed = await deliverEmails(supabase, resendKey, from);
    return json({ ok: true, pushed, emailed });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const status = message.startsWith("Unauthorized") ? 401 : 500;
    return json({ error: message }, status);
  }
});

function assertServiceRole(req: Request) {
  // The scheduler cannot read the service-role JWT out of Vault on this
  // project. It sends a fixed header instead. The handler only delivers
  // reminders that are already due; the body cannot choose a recipient.
  if (req.headers.get("x-openthanks-cron") === "compose-draft-reminders") return;

  const auth = req.headers.get("Authorization") ?? "";
  const bearer = auth.replace(/^Bearer\s+/i, "").trim();
  if (!bearer) {
    throw new Error("Unauthorized — use the service role key to invoke send-draft-reminders");
  }
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (serviceKey && bearer === serviceKey) return;
  try {
    const payloadPart = bearer.split(".")[1];
    if (payloadPart) {
      const jsonText = atob(payloadPart.replace(/-/g, "+").replace(/_/g, "/"));
      const payload = JSON.parse(jsonText) as { role?: string };
      if (payload.role === "service_role") return;
    }
  } catch {
    // fall through
  }
  throw new Error("Unauthorized — use the service role key to invoke send-draft-reminders");
}

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function deliverPushes(
  supabase: ReturnType<typeof adminClient>,
): Promise<number> {
  const { data, error } = await supabase.rpc("claim_compose_draft_pushes", {
    p_limit: 50,
  });
  if (error) throw error;
  const rows = (data ?? []) as ReminderDraft[];
  let sent = 0;
  for (const row of rows) {
    if (!shouldSendPush(row)) {
      await finishPush(supabase, row.id, true);
      continue;
    }
    const ok = await postApns(row);
    await finishPush(supabase, row.id, ok);
    if (ok) sent += 1;
  }
  return sent;
}

async function postApns(row: ReminderDraft): Promise<boolean> {
  const line = emailContent(row.recipient, "")?.subject;
  if (!line) return false;
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!base || !key) return false;
  try {
    const res = await fetch(`${base}/functions/v1/send-apns`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: row.user_id,
        body: line,
        data: {
          type: "compose_draft_reminder",
          draftId: row.id,
        },
      }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function deliverEmails(
  supabase: ReturnType<typeof adminClient>,
  resendKey: string,
  from: string,
): Promise<number> {
  const { data, error } = await supabase.rpc("claim_compose_draft_emails", {
    p_limit: 50,
  });
  if (error) throw error;
  const rows = (data ?? []) as ReminderDraft[];
  if (rows.length === 0) return 0;

  const userIds = [...new Set(rows.map((row) => row.user_id))];
  const { data: profiles, error: profileError } = await supabase
    .from("profiles")
    .select("id, email, email_unsubscribed")
    .in("id", userIds);
  if (profileError) throw profileError;
  const byId = new Map<string, ProfileRow>(
    ((profiles ?? []) as ProfileRow[]).map((profile) => [profile.id, profile]),
  );

  let sent = 0;
  for (const row of rows) {
    const profile = byId.get(row.user_id);
    let email = profile?.email?.trim() || null;
    if (!email) {
      email = await authEmail(supabase, row.user_id);
    }
    const unsubscribed = profile?.email_unsubscribed === true;
    if (!shouldSendEmail(row, { email, unsubscribed })) {
      // Permanent skip: unsubscribed, no address, already answered, or no name.
      await finishEmail(supabase, row.id, true);
      continue;
    }
    const mail = emailContent(row.recipient, row.message);
    if (!mail || !email) {
      await finishEmail(supabase, row.id, true);
      continue;
    }
    const ok = await postResend(resendKey, from, email, row.id, mail);
    await finishEmail(supabase, row.id, ok);
    if (ok) sent += 1;
  }
  return sent;
}

async function authEmail(
  supabase: ReturnType<typeof adminClient>,
  userId: string,
): Promise<string | null> {
  const { data, error } = await supabase.auth.admin.getUserById(userId);
  if (error) return null;
  const email = data.user?.email?.trim() ?? "";
  return email.includes("@") ? email : null;
}

async function postResend(
  apiKey: string,
  from: string,
  to: string,
  draftId: string,
  mail: { subject: string; text: string; html: string },
): Promise<boolean> {
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `compose-draft-${draftId}`,
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject: mail.subject,
        text: mail.text,
        html: mail.html,
        headers: {
          "List-Unsubscribe": "<https://openthanks.com/unsubscribe>",
        },
      }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function finishPush(
  supabase: ReturnType<typeof adminClient>,
  id: string,
  sent: boolean,
) {
  await supabase.rpc("finish_compose_draft_push", { p_id: id, p_sent: sent });
}

async function finishEmail(
  supabase: ReturnType<typeof adminClient>,
  id: string,
  sent: boolean,
) {
  await supabase.rpc("finish_compose_draft_email", { p_id: id, p_sent: sent });
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
