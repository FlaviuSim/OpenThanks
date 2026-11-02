/**
 * Request handling for send-web-push. Delivery (VAPID + encryption) is injected
 * so tests can run without a push service.
 */

import {
  assertServiceRole,
  buildWebPushMessage,
  corsHeaders,
  json,
  normalizePushRequest,
  PUSH_TYPES,
  type PushRequest,
} from "../_shared/push.ts";

export type WebPushTarget = {
  endpoint: string;
  p256dh: string;
  auth: string;
};

export class WebPushDeliveryError extends Error {
  readonly status: number;
  readonly reason: string;

  constructor(status: number, reason: string) {
    super(`web push failed: ${status}`);
    this.status = status;
    this.reason = reason;
  }
}

export type WebPushDeps = {
  configured: () => boolean;
  applicationServerKey: () => Promise<string | null>;
  loadTargets: (
    payload: PushRequest,
  ) => Promise<{ targets: WebPushTarget[]; incomplete: number }>;
  send: (target: WebPushTarget, message: string, topic?: string) => Promise<void>;
  deleteStale: (endpoints: string[]) => Promise<void>;
  origin?: string;
};

export function targetFromSubscription(
  sub: { endpoint?: string; keys?: { p256dh?: string; auth?: string } } | null | undefined,
): WebPushTarget | null {
  const endpoint = sub?.endpoint?.trim() ?? "";
  const p256dh = sub?.keys?.p256dh?.trim() ?? "";
  const auth = sub?.keys?.auth?.trim() ?? "";
  if (!endpoint.startsWith("https://") || !p256dh || !auth) return null;
  return { endpoint, p256dh, auth };
}

export function targetFromRow(row: {
  token: string | null;
  p256dh: string | null;
  auth_key: string | null;
}): WebPushTarget | null {
  return targetFromSubscription({
    endpoint: row.token ?? undefined,
    keys: {
      p256dh: row.p256dh ?? undefined,
      auth: row.auth_key ?? undefined,
    },
  });
}

function redactEndpoint(endpoint: string): string {
  try {
    return `${new URL(endpoint).origin}/…`;
  } catch {
    return "invalid-endpoint";
  }
}

export async function handleWebPush(req: Request, deps: WebPushDeps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method === "GET") {
    try {
      const key = await deps.applicationServerKey();
      if (!key) return json({ error: "web_push_not_configured" }, 503);
      return json({ applicationServerKey: key });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return json({ error: message }, 500);
    }
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    assertServiceRole(req, "send-web-push");

    const raw = await req.json();
    const payload = normalizePushRequest(raw);
    if (!payload) {
      return json({ ok: true, sent: 0, skipped: "ignored_payload" });
    }

    if (
      payload.type &&
      !payload.title &&
      !payload.body &&
      !PUSH_TYPES.has(payload.type)
    ) {
      return json({ ok: true, sent: 0, skipped: "type_not_pushed" });
    }

    if (!deps.configured()) {
      return json({ ok: true, sent: 0, skipped: "web_push_not_configured" });
    }

    let targets: WebPushTarget[];
    let incomplete = 0;
    if (payload.subscription) {
      const one = targetFromSubscription(payload.subscription);
      if (!one) {
        return json({
          error: "subscription must include an https endpoint and keys.p256dh and keys.auth",
        }, 400);
      }
      targets = [one];
    } else {
      const loaded = await deps.loadTargets(payload);
      targets = loaded.targets;
      incomplete = loaded.incomplete;
    }

    if (targets.length === 0) {
      return json({ ok: true, sent: 0, incomplete, skipped: "no_tokens" });
    }

    const message = buildWebPushMessage(payload, deps.origin);
    const parsed = JSON.parse(message.text) as { title?: string; body?: string };
    if (!parsed.title && !parsed.body) {
      return json({ error: "title or body required" }, 400);
    }

    let sent = 0;
    const errors: Array<{ endpoint: string; status: number; reason: string }> = [];
    const stale: string[] = [];

    for (const target of targets) {
      try {
        await deps.send(target, message.text, message.topic);
        sent += 1;
      } catch (err) {
        if (err instanceof WebPushDeliveryError) {
          errors.push({
            endpoint: redactEndpoint(target.endpoint),
            status: err.status,
            reason: err.reason.slice(0, 300),
          });
          if (err.status === 404 || err.status === 410) stale.push(target.endpoint);
          continue;
        }
        throw err;
      }
    }

    if (stale.length > 0) {
      await deps.deleteStale(stale);
    }

    return json({ ok: true, sent, failed: errors.length, incomplete, errors });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const status = message.startsWith("Unauthorized") ? 401 : 500;
    return json({ error: message }, status);
  }
}
