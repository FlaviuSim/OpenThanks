import { assertEquals } from "jsr:@std/assert@1";
import {
  composeURL,
  emailContent,
  reminderLine,
  shouldSendEmail,
  shouldSendPush,
  type ReminderDraft,
} from "./reminders.ts";

const draft = (overrides: Partial<ReminderDraft> = {}): ReminderDraft => ({
  id: "d1",
  user_id: "u1",
  recipient: "Ada Lovelace",
  message: "Thanks for the help",
  push_channel: "none",
  push_sent_at: null,
  push_responded_at: null,
  email_sent_at: null,
  ...overrides,
});

Deno.test("reminder line matches the local notification", () => {
  assertEquals(reminderLine("  Ada   Lovelace "), "Finish your thank-you to Ada Lovelace?");
  assertEquals(reminderLine("   "), null);
  const long = "A".repeat(90);
  assertEquals(reminderLine(long), `Finish your thank-you to ${"A".repeat(79)}…?`);
});

Deno.test("compose link prefills the name and does not carry the note", () => {
  const url = new URL(composeURL("Ada Lovelace"));
  assertEquals(url.origin + url.pathname, "https://openthanks.com/gratitude/new");
  assertEquals(url.searchParams.get("for"), "Ada Lovelace");
  assertEquals(url.searchParams.get("source"), "draft_reminder");
  assertEquals(url.searchParams.get("message"), null);
  assertEquals(url.search.includes("Thanks"), false);
});

Deno.test("email is skipped when the push was opened, unsubscribed, or already sent", () => {
  const ready = { email: "ada@example.com", unsubscribed: false };
  assertEquals(shouldSendEmail(draft(), ready), true);
  assertEquals(shouldSendEmail(draft({ push_responded_at: "t" }), ready), false);
  assertEquals(shouldSendEmail(draft({ email_sent_at: "t" }), ready), false);
  assertEquals(shouldSendEmail(draft(), { email: "ada@example.com", unsubscribed: true }), false);
  assertEquals(shouldSendEmail(draft(), { email: null, unsubscribed: false }), false);
  assertEquals(shouldSendEmail(draft({ recipient: "  " }), ready), false);
});

Deno.test("remote push is only for an unopened web draft", () => {
  assertEquals(shouldSendPush(draft({ push_channel: "remote" })), true);
  assertEquals(shouldSendPush(draft({ push_channel: "local" })), false);
  assertEquals(shouldSendPush(draft({ push_channel: "none" })), false);
  assertEquals(
    shouldSendPush(draft({ push_channel: "remote", push_responded_at: "t" })),
    false,
  );
  assertEquals(
    shouldSendPush(draft({ push_channel: "remote", push_sent_at: "t" })),
    false,
  );
});

Deno.test("email quotes the note and escapes html", () => {
  const mail = emailContent("Ada", "Thanks <b> & \"you\"");
  assertEquals(mail?.subject, "Finish your thank-you to Ada?");
  assertEquals(mail?.text.includes("Thanks <b> & \"you\""), true);
  assertEquals(mail?.html.includes("<b>"), false);
  assertEquals(mail?.html.includes("Thanks &lt;b&gt; &amp; &quot;you&quot;"), true);
  assertEquals(mail?.text.includes("source=draft_reminder"), true);
});
