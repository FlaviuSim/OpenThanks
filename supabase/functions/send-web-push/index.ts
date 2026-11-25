/**
 * send-web-push — deliver the same notification allowlist as send-apns via
 * Web Push (RFC 8291 + VAPID). Chrome shows these in the Android Trusted Web
 * Activity because notification delegation is already on. No Firebase project.
 *
 * Secrets (Dashboard → Edge Functions → Secrets, or `supabase secrets set`):
 *   WEB_PUSH_VAPID_KEYS    JSON from scripts/generate_vapid_keys.ts
 *                          { "publicKey": { JWK }, "privateKey": { JWK } }
 *   WEB_PUSH_SUBJECT       mailto: or https: contact URL.
 *                          Default mailto:founders@openthanks.com
 *   WEB_PUSH_ORIGIN        Link origin in the payload. Default https://openthanks.com
 *
 * GET  (no auth) → { applicationServerKey } for pushManager.subscribe.
 * POST (service role) → same body as send-apns, plus optional `subscription`.
 *
 * Rows: device_push_tokens where platform = 'web'.
 *   token    = subscription endpoint
 *   p256dh   = subscription.keys.p256dh
 *   auth_key = subscription.keys.auth
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  ApplicationServer,
  exportApplicationServerKey,
  importVapidKeys,
  PushMessageError,
  Urgency,
  type ExportedVapidKeys,
} from "jsr:@negrel/webpush@0.5.0";
import type { PushRequest } from "../_shared/push.ts";
import {
  handleWebPush,
  targetFromRow,
  WebPushDeliveryError,
  type WebPushDeps,
  type WebPushTarget,
} from "./handler.ts";

const TTL_SECONDS = 7 * 24 * 60 * 60;

type CachedServer = {
  server: ApplicationServer;
  applicationServerKey: string;
};

let cached: CachedServer | null = null;

function vapidKeysFromEnv(): ExportedVapidKeys | null {
  const raw = Deno.env.get("WEB_PUSH_VAPID_KEYS");
  if (!raw || raw.trim().length === 0) return null;
  let parsed: ExportedVapidKeys;
  try {
    parsed = JSON.parse(raw) as ExportedVapidKeys;
  } catch {
    throw new Error("WEB_PUSH_VAPID_KEYS is not valid JSON");
  }
  if (!parsed?.publicKey || !parsed?.privateKey) {
    throw new Error(
      "WEB_PUSH_VAPID_KEYS must be JSON with publicKey and privateKey JWKs",
    );
  }
  return parsed;
}

function contactSubject(): string {
  const value = (Deno.env.get("WEB_PUSH_SUBJECT") ??
    "mailto:founders@openthanks.com").trim();
  if (!value.startsWith("mailto:") && !value.startsWith("https://")) {
    throw new Error("WEB_PUSH_SUBJECT must be a mailto: or https: URL");
  }
  return value;
}

async function getServer(): Promise<CachedServer | null> {
  if (cached) return cached;
  const exported = vapidKeysFromEnv();
  if (!exported) return null;
  const vapidKeys = await importVapidKeys(exported);
  const server = await ApplicationServer.new({
    contactInformation: contactSubject(),
    vapidKeys,
  });
  const applicationServerKey = await exportApplicationServerKey(vapidKeys);
  cached = { server, applicationServerKey };
  return cached;
}

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function loadTargets(payload: PushRequest) {
  if (!payload.user_id) {
    throw new Error("user_id or subscription is required");
  }

  const supabase = adminClient();
  const { data, error } = await supabase
    .from("device_push_tokens")
    .select("token, p256dh, auth_key")
    .eq("user_id", payload.user_id)
    .eq("platform", "web");

  if (error) throw error;

  const targets: WebPushTarget[] = [];
  let incomplete = 0;
  for (const row of data ?? []) {
    const target = targetFromRow(row as {
      token: string | null;
      p256dh: string | null;
      auth_key: string | null;
    });
    if (target) targets.push(target);
    else incomplete += 1;
  }
  return { targets, incomplete };
}

async function send(
  target: WebPushTarget,
  message: string,
  topic?: string,
): Promise<void> {
  const ready = await getServer();
  if (!ready) throw new Error("Web Push is not configured");
  const subscriber = ready.server.subscribe({
    endpoint: target.endpoint,
    keys: { p256dh: target.p256dh, auth: target.auth },
  });
  try {
    await subscriber.pushTextMessage(message, {
      ttl: TTL_SECONDS,
      urgency: Urgency.High,
      topic,
    });
  } catch (err) {
    if (err instanceof PushMessageError) {
      const reason = await err.response.text();
      throw new WebPushDeliveryError(err.response.status, reason);
    }
    throw err;
  }
}

async function deleteStale(endpoints: string[]) {
  if (endpoints.length === 0) return;
  const supabase = adminClient();
  await supabase.from("device_push_tokens").delete().in("token", endpoints);
}

function deps(): WebPushDeps {
  return {
    configured: () => vapidKeysFromEnv() !== null,
    applicationServerKey: async () => (await getServer())?.applicationServerKey ?? null,
    loadTargets,
    send,
    deleteStale,
    origin: Deno.env.get("WEB_PUSH_ORIGIN") ?? undefined,
  };
}

Deno.serve((req) => handleWebPush(req, deps()));
