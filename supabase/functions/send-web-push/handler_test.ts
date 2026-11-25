import { assertEquals } from "jsr:@std/assert@1";
import type { PushRequest } from "../_shared/push.ts";
import {
  handleWebPush,
  targetFromRow,
  targetFromSubscription,
  WebPushDeliveryError,
  type WebPushDeps,
  type WebPushTarget,
} from "./handler.ts";

const ENDPOINT = "https://fcm.googleapis.com/wp/example-token";
const USER = "33333333-3333-4333-8333-333333333333";

Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-test");

function serviceRequest(body: unknown, token = "service-role-test"): Request {
  return new Request("https://example.test/send-web-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
}

function deps(overrides: Partial<WebPushDeps> = {}): WebPushDeps & {
  sent: Array<{ endpoint: string; message: string; topic?: string }>;
  deleted: string[][];
} {
  const sent: Array<{ endpoint: string; message: string; topic?: string }> = [];
  const deleted: string[][] = [];
  const base: WebPushDeps = {
    configured: () => true,
    applicationServerKey: () => Promise.resolve("test-public-key"),
    loadTargets: (payload: PushRequest) => {
      if (!payload.user_id) throw new Error("user_id or subscription is required");
      return Promise.resolve({
        targets: [{
          endpoint: ENDPOINT,
          p256dh: "p256dh-key",
          auth: "auth-secret",
        }],
        incomplete: 0,
      });
    },
    send: (target: WebPushTarget, message: string, topic?: string) => {
      sent.push({ endpoint: target.endpoint, message, topic });
      return Promise.resolve();
    },
    deleteStale: (endpoints: string[]) => {
      deleted.push(endpoints);
      return Promise.resolve();
    },
  };
  const merged = { ...base, ...overrides, sent, deleted };
  return merged;
}

Deno.test("subscription row requires an https endpoint and both keys", () => {
  assertEquals(
    targetFromSubscription({
      endpoint: ENDPOINT,
      keys: { p256dh: "pub", auth: "sec" },
    })?.endpoint,
    ENDPOINT,
  );
  assertEquals(targetFromSubscription({ endpoint: "http://insecure.example" }), null);
  assertEquals(
    targetFromRow({ token: ENDPOINT, p256dh: null, auth_key: "sec" }),
    null,
  );
});

Deno.test("GET returns the application server public key", async () => {
  const res = await handleWebPush(
    new Request("https://example.test/send-web-push"),
    deps(),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { applicationServerKey: "test-public-key" });
});

Deno.test("GET reports missing VAPID configuration", async () => {
  const res = await handleWebPush(
    new Request("https://example.test/send-web-push"),
    deps({ applicationServerKey: () => Promise.resolve(null) }),
  );
  assertEquals(res.status, 503);
});

Deno.test("POST without the service role is rejected", async () => {
  const res = await handleWebPush(
    serviceRequest({ user_id: USER, type: "heart_received" }, "not-a-jwt"),
    deps(),
  );
  assertEquals(res.status, 401);
});

Deno.test("unconfigured sender skips without calling the database", async () => {
  let loaded = false;
  const res = await handleWebPush(
    serviceRequest({ user_id: USER, type: "gratitude_pending" }),
    deps({
      configured: () => false,
      loadTargets: () => {
        loaded = true;
        return Promise.resolve({ targets: [], incomplete: 0 });
      },
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    ok: true,
    sent: 0,
    skipped: "web_push_not_configured",
  });
  assertEquals(loaded, false);
});

Deno.test("local-only notification types are not pushed", async () => {
  const res = await handleWebPush(
    serviceRequest({ user_id: USER, type: "gratitude_friday" }),
    deps(),
  );
  assertEquals((await res.json()).skipped, "type_not_pushed");
});

Deno.test("sends the shared alert and drops a gone subscription", async () => {
  const harness = deps({
    send: () => {
      throw new WebPushDeliveryError(410, "gone");
    },
  });
  const res = await handleWebPush(
    serviceRequest({
      user_id: USER,
      type: "email_bounced",
      notification_id: "22222222-2222-4222-8222-222222222222",
      gratitude_id: "11111111-1111-4111-8111-111111111111",
    }),
    harness,
  );
  const body = await res.json();
  assertEquals(body.sent, 0);
  assertEquals(body.failed, 1);
  assertEquals(body.errors[0].status, 410);
  assertEquals(harness.deleted, [[ENDPOINT]]);
});

Deno.test("a direct subscription is delivered without a user id", async () => {
  const harness = deps();
  const res = await handleWebPush(
    serviceRequest({
      type: "competition_winner",
      subscription: {
        endpoint: ENDPOINT,
        keys: { p256dh: "pub", auth: "sec" },
      },
    }),
    harness,
  );
  assertEquals((await res.json()).sent, 1);
  const payload = JSON.parse(harness.sent[0].message);
  assertEquals(payload.title, "🏆 You finished 30 Days of Thanks");
  assertEquals(payload.url, "https://openthanks.com/notifications");
});
