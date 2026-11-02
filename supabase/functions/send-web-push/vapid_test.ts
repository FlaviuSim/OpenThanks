import { assertEquals } from "jsr:@std/assert@1";
import {
  exportApplicationServerKey,
  exportVapidKeys,
  generateVapidKeys,
  importVapidKeys,
} from "jsr:@negrel/webpush@0.5.0";

Deno.test("generated VAPID keys round-trip to a 65-byte application server key", async () => {
  const keys = await generateVapidKeys({ extractable: true });
  const exported = await exportVapidKeys(keys);
  const imported = await importVapidKeys(exported);
  const applicationServerKey = await exportApplicationServerKey(imported);
  assertEquals(/^[A-Za-z0-9_-]+$/.test(applicationServerKey), true);
  const padded = applicationServerKey +
    "=".repeat((4 - (applicationServerKey.length % 4)) % 4);
  const raw = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  // Uncompressed P-256 point: 0x04 || X || Y.
  assertEquals(raw.length, 65);
  assertEquals(raw.charCodeAt(0), 0x04);
});
