/**
 * Print a new Web Push VAPID keypair for OpenThanks.
 *
 *   ~/.deno/bin/deno run --allow-env scripts/generate_vapid_keys.ts
 *
 * Paste the JSON into the Edge Function secret WEB_PUSH_VAPID_KEYS.
 * Paste the application server key into the website as
 * NEXT_PUBLIC_VAPID_PUBLIC_KEY. The private key never goes in the web app.
 *
 * Run this once. Generating again invalidates every existing subscription.
 */
import {
  exportApplicationServerKey,
  exportVapidKeys,
  generateVapidKeys,
} from "jsr:@negrel/webpush@0.5.0";

const keys = await generateVapidKeys({ extractable: true });
const exported = await exportVapidKeys(keys);
const applicationServerKey = await exportApplicationServerKey(keys);

console.log("WEB_PUSH_VAPID_KEYS=");
console.log(JSON.stringify(exported));
console.log("");
console.log("NEXT_PUBLIC_VAPID_PUBLIC_KEY=");
console.log(applicationServerKey);
console.log("");
console.log("WEB_PUSH_SUBJECT=mailto:founders@openthanks.com");
