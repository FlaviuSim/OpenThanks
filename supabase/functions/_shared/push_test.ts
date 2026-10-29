import {
  assertEquals,
  assertStrictEquals,
} from "jsr:@std/assert@1";
import {
  buildWebPushMessage,
  composeAlert,
  normalizePushRequest,
  notificationPath,
  PUSH_TYPES,
  webPushTopic,
} from "./push.ts";

const GRATITUDE_ID = "11111111-1111-4111-8111-111111111111";
const NOTIFICATION_ID = "22222222-2222-4222-8222-222222222222";

Deno.test("allowlist is the five remote notification types", () => {
  assertEquals(
    [...PUSH_TYPES].sort(),
    [
      "competition_winner",
      "email_bounced",
      "gratitude_pending",
      "gratitude_received",
      "heart_received",
    ],
  );
});

Deno.test("webhook INSERT envelope becomes a push request", () => {
  const parsed = normalizePushRequest({
    type: "INSERT",
    table: "notifications",
    record: {
      id: NOTIFICATION_ID,
      user_id: "33333333-3333-4333-8333-333333333333",
      type: "gratitude_pending",
      gratitude_id: GRATITUDE_ID,
    },
  });
  assertEquals(parsed, {
    user_id: "33333333-3333-4333-8333-333333333333",
    type: "gratitude_pending",
    notification_id: NOTIFICATION_ID,
    gratitude_id: GRATITUDE_ID,
  });
});

Deno.test("webhook updates are ignored", () => {
  assertStrictEquals(
    normalizePushRequest({
      type: "UPDATE",
      record: { user_id: "u", type: "heart_received" },
    }),
    null,
  );
});

Deno.test("alert copy matches the iOS remote notification text", () => {
  assertEquals(composeAlert({ type: "gratitude_pending" }), {
    title: "🙏 Someone appreciated you",
    body: "Open OpenThanks to accept it.",
    data: { type: "gratitude_pending" },
  });
  assertEquals(composeAlert({ type: "gratitude_received" }).title, "✅ Your appreciation was accepted");
  assertEquals(composeAlert({ type: "heart_received" }).title, "❤️ Someone hearted your appreciation");
  assertEquals(
    composeAlert({ type: "competition_winner" }).body,
    "Unlock $30 to give away to a classroom — open notifications for next steps.",
  );
  assertEquals(
    composeAlert({ type: "email_bounced" }).title,
    "⚠️ Email may be invalid",
  );
});

Deno.test("explicit title is kept and data is merged", () => {
  const alert = composeAlert({
    title: "Custom",
    type: "heart_received",
    gratitude_id: GRATITUDE_ID,
    data: { source: "test" },
  });
  assertEquals(alert.title, "Custom");
  assertEquals(alert.data, {
    source: "test",
    type: "heart_received",
    gratitude_id: GRATITUDE_ID,
  });
});

Deno.test("tap destinations follow the iOS deep links", () => {
  assertEquals(
    notificationPath({ type: "gratitude_pending" }),
    "/notifications",
  );
  assertEquals(
    notificationPath({ type: "heart_received", gratitude_id: GRATITUDE_ID }),
    `/gratitude/${GRATITUDE_ID}`,
  );
  assertEquals(
    notificationPath({ type: "gratitude_received" }),
    "/notifications",
  );
  assertEquals(
    notificationPath({ type: "email_bounced", gratitude_id: GRATITUDE_ID }),
    `/pending?resend=${GRATITUDE_ID}`,
  );
  assertEquals(
    notificationPath({ type: "email_bounced", gratitude_id: "not-a-uuid" }),
    "/pending",
  );
  assertEquals(
    notificationPath({ type: "competition_winner" }),
    "/notifications",
  );
});

Deno.test("web push body carries title, url, and a 32-char topic", () => {
  const message = buildWebPushMessage({
    type: "heart_received",
    notification_id: NOTIFICATION_ID,
    gratitude_id: GRATITUDE_ID,
  });
  const body = JSON.parse(message.text);
  assertEquals(body.title, "❤️ Someone hearted your appreciation");
  assertEquals(body.url, `https://openthanks.com/gratitude/${GRATITUDE_ID}`);
  assertEquals(body.tag, NOTIFICATION_ID);
  assertEquals(body.data.type, "heart_received");
  assertEquals(message.topic, NOTIFICATION_ID.replace(/-/g, ""));
  assertEquals(webPushTopic("not-a-uuid"), undefined);
});
