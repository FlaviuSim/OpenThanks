/**
 * Shared notification fan-out used by send-apns and send-web-push.
 * Keep alert copy here so iOS and Android/web show the same text.
 */

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export type PushRequest = {
  user_id?: string;
  token?: string;
  environment?: "sandbox" | "production";
  title?: string;
  body?: string;
  data?: Record<string, string>;
  badge?: number;
  /** When set, derive title/body from notification type (optional helper). */
  type?: string;
  notification_id?: string;
  gratitude_id?: string;
  /** Direct Web Push subscription. Ignored by send-apns. */
  subscription?: {
    endpoint?: string;
    keys?: { p256dh?: string; auth?: string };
  };
};

/** Types that get a phone push. Local-only / noisy types are skipped. */
export const PUSH_TYPES = new Set([
  "gratitude_pending",
  "gratitude_received",
  "heart_received",
  "email_bounced",
  "competition_winner",
]);

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Accepts either a direct push body or a Supabase Database Webhook envelope
 * (`{ type: "INSERT", table: "notifications", record: { ... } }`).
 */
export function normalizePushRequest(raw: unknown): PushRequest | null {
  if (!raw || typeof raw !== "object") return null;
  const body = raw as Record<string, unknown>;

  // Database Webhook / trigger envelope.
  if (
    typeof body.type === "string" &&
    (body.type === "INSERT" || body.type === "UPDATE" || body.type === "DELETE") &&
    body.record &&
    typeof body.record === "object"
  ) {
    if (body.type !== "INSERT") return null;
    const record = body.record as Record<string, unknown>;
    const userId = asString(record.user_id);
    const notifType = asString(record.type);
    if (!userId || !notifType) return null;
    return {
      user_id: userId,
      type: notifType,
      notification_id: asString(record.id),
      gratitude_id: asString(record.gratitude_id),
    };
  }

  return body as PushRequest;
}

function asString(value: unknown): string | undefined {
  if (typeof value === "string" && value.length > 0) return value;
  if (typeof value === "number") return String(value);
  return undefined;
}

export function assertServiceRole(req: Request, functionName = "send-apns") {
  const auth = req.headers.get("Authorization") ?? "";
  const bearer = auth.replace(/^Bearer\s+/i, "").trim();
  if (!bearer) {
    throw new Error(
      `Unauthorized — use the service role key to invoke ${functionName}`,
    );
  }

  // Exact match against the function's configured service role key (when set).
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (serviceKey && bearer === serviceKey) return;

  // Also accept any JWT whose role claim is service_role. Supabase may inject a
  // different copy of the key into Deno.env than the caller holds (rotate/sync),
  // and Vercel/webhooks call with their own SUPABASE_SERVICE_ROLE_KEY.
  try {
    const payloadPart = bearer.split(".")[1];
    if (payloadPart) {
      const json = atob(payloadPart.replace(/-/g, "+").replace(/_/g, "/"));
      const payload = JSON.parse(json) as { role?: string };
      if (payload.role === "service_role") return;
    }
  } catch {
    // fall through
  }

  throw new Error(
    `Unauthorized — use the service role key to invoke ${functionName}`,
  );
}

export function composeAlert(payload: PushRequest): {
  title?: string;
  body?: string;
  data?: Record<string, string>;
} {
  const data: Record<string, string> = { ...(payload.data ?? {}) };
  if (payload.type) data.type = payload.type;
  if (payload.notification_id) data.notification_id = payload.notification_id;
  if (payload.gratitude_id) data.gratitude_id = payload.gratitude_id;

  if (payload.title || payload.body) {
    return { title: payload.title, body: payload.body, data };
  }

  // Sensible defaults when only `type` is provided (e.g. from a DB webhook).
  switch (payload.type) {
    case "gratitude_pending":
      return {
        title: "🙏 Someone appreciated you",
        body: "Open OpenThanks to accept it.",
        data,
      };
    case "gratitude_received":
      return {
        title: "✅ Your appreciation was accepted",
        body: "They saw your note — take a look.",
        data,
      };
    case "heart_received":
      return {
        title: "❤️ Someone hearted your appreciation",
        body: "A little more kindness came your way.",
        data,
      };
    case "competition_winner":
      return {
        title: "🏆 You finished 30 Days of Thanks",
        body: "Unlock $30 to give away to a classroom — open notifications for next steps.",
        data,
      };
    case "email_bounced":
      return {
        title: "⚠️ Email may be invalid",
        body: "Your appreciation notification couldn't be delivered. Check the address or share the claim link.",
        data,
      };
    case "pay_it_forward_reminder":
      return {
        title: "🫶 Ready to pay it forward?",
        body: "Someone appreciated you — thank someone else to keep it going.",
        data,
      };
    case "gratitude_friday":
      return {
        title: "✨ Gratitude Friday",
        body: "Share an appreciation for someone who made your week better.",
        data,
      };
    default:
      return {
        title: "OpenThanks",
        body: "You have a new update.",
        data,
      };
  }
}

function uuidOrUndefined(value: string | undefined): string | undefined {
  if (value && UUID_RE.test(value)) return value;
  return undefined;
}

/**
 * Page to open when the notification is tapped.
 * Paths match routes the iOS app already deep-links:
 * `/notifications`, `/gratitude/{id}`, `/pending?resend={id}`.
 */
export function notificationPath(payload: PushRequest): string {
  const gratitudeId = uuidOrUndefined(payload.gratitude_id);
  switch (payload.type) {
    case "gratitude_received":
    case "heart_received":
      return gratitudeId ? `/gratitude/${gratitudeId}` : "/notifications";
    case "email_bounced":
      return gratitudeId
        ? `/pending?resend=${encodeURIComponent(gratitudeId)}`
        : "/pending";
    default:
      return "/notifications";
  }
}

export function notificationLink(
  payload: PushRequest,
  origin = "https://openthanks.com",
): string {
  const base = origin.replace(/\/$/, "");
  return `${base}${notificationPath(payload)}`;
}

/** Web Push Topic values some push services cap at 32 URL-safe characters. */
export function webPushTopic(notificationId: string | undefined): string | undefined {
  if (!notificationId) return undefined;
  const compact = notificationId.replace(/-/g, "");
  if (!/^[0-9a-f]{32}$/i.test(compact)) return undefined;
  return compact;
}

export type WebPushMessage = {
  text: string;
  topic?: string;
};

export function buildWebPushMessage(
  payload: PushRequest,
  origin = "https://openthanks.com",
): WebPushMessage {
  const { title, body, data } = composeAlert(payload);
  const message = {
    title: title ?? "OpenThanks",
    body: body ?? "",
    url: notificationLink(payload, origin),
    tag: payload.notification_id ?? payload.type ?? "openthanks",
    data: data ?? {},
  };
  return {
    text: JSON.stringify(message),
    topic: webPushTopic(payload.notification_id),
  };
}

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
