/** Copy and send/skip rules for an unsent thank-you reminder. No I/O. */

export const COMPOSE_URL = "https://openthanks.com/gratitude/new";

export type ReminderDraft = {
  id: string;
  user_id: string;
  recipient: string;
  message: string;
  push_channel: string;
  push_sent_at: string | null;
  push_responded_at: string | null;
  email_sent_at: string | null;
};

export function reminderLine(recipient: string): string | null {
  const name = recipient.split(/\s+/).filter(Boolean).join(" ");
  if (!name) return null;
  const shown = name.length > 80
    ? `${name.slice(0, 79).trimEnd()}…`
    : name;
  return `Finish your thank-you to ${shown}?`;
}

export function composeURL(recipient: string): string {
  const params = new URLSearchParams({
    for: recipient.split(/\s+/).filter(Boolean).join(" "),
    source: "draft_reminder",
  });
  return `${COMPOSE_URL}?${params.toString()}`;
}

export function shouldSendPush(row: ReminderDraft): boolean {
  return row.push_channel === "remote" &&
    !row.push_sent_at &&
    !row.push_responded_at &&
    reminderLine(row.recipient) !== null;
}

export function shouldSendEmail(
  row: ReminderDraft,
  delivery: { email: string | null; unsubscribed: boolean },
): boolean {
  if (row.email_sent_at || row.push_responded_at) return false;
  if (delivery.unsubscribed) return false;
  const email = delivery.email?.trim() ?? "";
  if (!email.includes("@")) return false;
  return reminderLine(row.recipient) !== null;
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function emailContent(recipient: string, message: string): {
  subject: string;
  text: string;
  html: string;
} | null {
  const line = reminderLine(recipient);
  if (!line) return null;
  const url = composeURL(recipient);
  const note = message.trim();
  const text = [
    line,
    "",
    note ? `Your note is still here:\n\n${note}\n` : "",
    `Finish it: ${url}`,
    "",
    "If you already sent it, you can ignore this email.",
    "Unsubscribe: https://openthanks.com/unsubscribe",
  ].filter((part) => part !== "").join("\n");

  const noteHtml = note
    ? `<p>Your note is still here:</p><blockquote>${escapeHtml(note)}</blockquote>`
    : "";
  const html = [
    `<p>${escapeHtml(line)}</p>`,
    noteHtml,
    `<p><a href="${escapeHtml(url)}">Finish your thank-you</a></p>`,
    `<p>If you already sent it, you can ignore this email.</p>`,
    `<p><a href="https://openthanks.com/unsubscribe">Unsubscribe</a></p>`,
  ].filter(Boolean).join("\n");

  return { subject: line, text, html };
}
