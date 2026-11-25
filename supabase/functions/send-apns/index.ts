/**
 * send-apns — deliver remote notifications via Apple Push Notification service.
 *
 * Secrets (Dashboard → Edge Functions → Secrets, or `supabase secrets set`):
 *   APNS_KEY      Full .p8 contents (use \n for newlines in the secret value)
 *   APNS_KEY_ID   Key ID from Apple Developer → Keys
 *   APNS_TEAM_ID  Apple Team ID (e.g. XA73L5SR8P)
 *   APNS_TOPIC    Bundle ID, default com.openthanks.gratitude
 *
 * Auth: Authorization: Bearer <service_role OR anon JWT of an authenticated user
 *       calling for themselves is NOT enough — require service role or
 *       SUPABASE_SERVICE_ROLE_KEY match>. Callers must use the service role key.
 *
 * Body:
 *   {
 *     "user_id": "uuid",                 // required unless "token" is set
 *     "token": "apns-device-token",       // optional direct token
 *     "environment": "production"|"sandbox", // optional; defaults per token row
 *     "title": "Someone appreciated you",
 *     "body": "Open OpenThanks to accept it.",
 *     "data": { "type": "gratitude_pending", "gratitude_id": "..." },
 *     "badge": 1                         // optional
 *   }
 *
 * Web Push for Android and the website is send-web-push, not this function.
 * Alert copy for both lives in ../_shared/push.ts.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SignJWT, importPKCS8 } from "https://esm.sh/jose@5.9.6";
import {
  assertServiceRole,
  composeAlert,
  corsHeaders,
  json,
  normalizePushRequest,
  PUSH_TYPES,
  type PushRequest,
} from "../_shared/push.ts";

type TokenRow = {
  token: string;
  environment: string;
  platform: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    assertServiceRole(req);

    const raw = await req.json();
    const payload = normalizePushRequest(raw);
    if (!payload) {
      return json({ ok: true, sent: 0, skipped: "ignored_payload" });
    }

    // Webhook / trigger paths often send only `type` — skip non-push types early.
    if (
      payload.type &&
      !payload.title &&
      !payload.body &&
      !PUSH_TYPES.has(payload.type)
    ) {
      return json({ ok: true, sent: 0, skipped: "type_not_pushed" });
    }

    const supabase = adminClient();

    const targets = await resolveTargets(supabase, payload);
    if (targets.length === 0) {
      return json({ ok: true, sent: 0, skipped: "no_tokens" });
    }

    const { title, body, data } = composeAlert(payload);
    if (!title && !body) {
      return json({ error: "title or body required" }, 400);
    }

    const jwt = await getApnsJwt();
    const topic = Deno.env.get("APNS_TOPIC") ?? "com.openthanks.gratitude";

    let sent = 0;
    const errors: Array<{ token: string; status: number; reason: string }> = [];
    const stale: string[] = [];

    for (const row of targets) {
      const host =
        row.environment === "sandbox"
          ? "https://api.sandbox.push.apple.com"
          : "https://api.push.apple.com";

      const apnsBody = {
        aps: {
          alert: {
            title: title ?? "OpenThanks",
            body: body ?? "",
          },
          sound: "default",
          ...(typeof payload.badge === "number" ? { badge: payload.badge } : {}),
        },
        ...(data ?? {}),
      };

      const res = await fetch(`${host}/3/device/${row.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify(apnsBody),
      });

      if (res.ok) {
        sent += 1;
        continue;
      }

      const reason = await res.text();
      errors.push({ token: row.token.slice(0, 8) + "…", status: res.status, reason });
      // Unregistered / BadDeviceToken → drop so we don't keep failing.
      if (res.status === 410 || res.status === 400) {
        stale.push(row.token);
      }
    }

    if (stale.length > 0) {
      await supabase.from("device_push_tokens").delete().in("token", stale);
    }

    return json({ ok: true, sent, failed: errors.length, errors });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return json({ error: message }, 500);
  }
});

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function resolveTargets(
  supabase: ReturnType<typeof createClient>,
  payload: PushRequest,
): Promise<TokenRow[]> {
  if (payload.token) {
    return [
      {
        token: payload.token,
        environment: payload.environment ?? "production",
        platform: "ios",
      },
    ];
  }

  if (!payload.user_id) {
    throw new Error("user_id or token is required");
  }

  let query = supabase
    .from("device_push_tokens")
    .select("token, environment, platform")
    .eq("user_id", payload.user_id)
    .eq("platform", "ios");

  if (payload.environment) {
    query = query.eq("environment", payload.environment);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as TokenRow[];
}

let cachedJwt: { token: string; exp: number } | null = null;

async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.exp > now + 60) {
    return cachedJwt.token;
  }

  const apnsKey = Deno.env.get("APNS_KEY");
  const apnsKeyId = Deno.env.get("APNS_KEY_ID");
  const apnsTeamId = Deno.env.get("APNS_TEAM_ID");
  if (!apnsKey || !apnsKeyId || !apnsTeamId) {
    throw new Error(
      "Missing APNS_KEY, APNS_KEY_ID, or APNS_TEAM_ID — set them in Edge Function secrets",
    );
  }

  const pem = normalizeP8(apnsKey);
  const privateKey = await importPKCS8(pem, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: apnsKeyId })
    .setIssuer(apnsTeamId)
    .setIssuedAt(now)
    .setExpirationTime(now + 50 * 60)
    .sign(privateKey);

  cachedJwt = { token, exp: now + 50 * 60 };
  return token;
}

function normalizeP8(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.includes("BEGIN PRIVATE KEY")) {
    return trimmed.replace(/\\n/g, "\n");
  }
  const base64 = trimmed
    .replace(/-----BEGIN[^-]*-----/gi, "")
    .replace(/-----END[^-]*-----/gi, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  return `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`;
}
