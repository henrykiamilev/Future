// Supabase Edge Function: push-notification
// Triggered by database webhook on INSERT into notifications table.
// Sends APNs push notifications to the recipient's iOS devices.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// — APNs configuration (from Supabase secrets) —
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
const APNS_BUNDLE_ID = "com.getcurated.app";

// Use production APNs by default; set APNS_USE_SANDBOX=true for dev
const USE_SANDBOX = Deno.env.get("APNS_USE_SANDBOX") === "true";
const APNS_HOST = USE_SANDBOX
  ? "https://api.sandbox.push.apple.com"
  : "https://api.push.apple.com";

// — Supabase client (service role for reading device_tokens) —
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// ═══════════════════════════════════════════════════════════════════
// JWT for APNs (ES256 token-based auth)
// ═══════════════════════════════════════════════════════════════════

let cachedJWT: { token: string; issuedAt: number } | null = null;

async function getAPNsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // APNs tokens are valid for 1 hour; refresh after 50 minutes
  if (cachedJWT && now - cachedJWT.issuedAt < 3000) {
    return cachedJWT.token;
  }

  // Import the private key
  const pemContents = APNS_PRIVATE_KEY
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const keyData = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  // Build JWT header + payload
  const header = { alg: "ES256", kid: APNS_KEY_ID };
  const payload = { iss: APNS_TEAM_ID, iat: now };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  // Sign with ES256
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );

  // Convert DER signature to raw r||s format for JWT
  const rawSig = derToRaw(new Uint8Array(signature));
  const encodedSig = base64url(rawSig);

  const jwt = `${signingInput}.${encodedSig}`;
  cachedJWT = { token: jwt, issuedAt: now };
  return jwt;
}

function base64url(input: string | Uint8Array): string {
  let b64: string;
  if (typeof input === "string") {
    b64 = btoa(input);
  } else {
    b64 = btoa(String.fromCharCode(...input));
  }
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Convert DER-encoded ECDSA signature to raw r||s (64 bytes)
function derToRaw(der: Uint8Array): Uint8Array {
  // DER: 0x30 [len] 0x02 [rLen] [r] 0x02 [sLen] [s]
  const raw = new Uint8Array(64);

  let offset = 2; // skip 0x30 and total length
  // r
  offset++; // skip 0x02
  const rLen = der[offset++];
  const rStart = rLen > 32 ? offset + (rLen - 32) : offset;
  const rDest = rLen < 32 ? 32 - rLen : 0;
  raw.set(der.slice(rStart, offset + rLen), rDest);
  offset += rLen;

  // s
  offset++; // skip 0x02
  const sLen = der[offset++];
  const sStart = sLen > 32 ? offset + (sLen - 32) : offset;
  const sDest = sLen < 32 ? 32 + (32 - sLen) : 32;
  raw.set(der.slice(sStart, offset + sLen), sDest);

  return raw;
}

// ═══════════════════════════════════════════════════════════════════
// Build notification message
// ═══════════════════════════════════════════════════════════════════

interface NotificationRecord {
  id: string;
  user_id: string;
  actor_id: string;
  type: "like" | "follow" | "comment";
  post_id: string | null;
  comment_id: string | null;
  is_read: boolean;
  created_at: string;
}

async function getActorUsername(actorId: string): Promise<string> {
  const { data } = await supabase
    .from("users")
    .select("username")
    .eq("id", actorId)
    .single();
  return data?.username ?? "Someone";
}

function buildAPNsPayload(
  type: string,
  actorName: string
): { alert: { title: string; body: string }; sound: string; badge?: number } {
  let title: string;
  let body: string;

  switch (type) {
    case "like":
      title = "Curated";
      body = `${actorName} liked your post`;
      break;
    case "follow":
      title = "Curated";
      body = `${actorName} started following you`;
      break;
    case "comment":
      title = "Curated";
      body = `${actorName} commented on your post`;
      break;
    default:
      title = "Curated";
      body = `You have a new notification`;
  }

  return { alert: { title, body }, sound: "default" };
}

// ═══════════════════════════════════════════════════════════════════
// Send push to a single device token
// ═══════════════════════════════════════════════════════════════════

async function sendPush(deviceToken: string, payload: object): Promise<void> {
  const jwt = await getAPNsJWT();

  const response = await fetch(
    `${APNS_HOST}/3/device/${deviceToken}`,
    {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: payload }),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(
      `APNs error for token ${deviceToken.slice(0, 8)}...: ${response.status} ${errorBody}`
    );

    // If token is invalid, clean it up
    if (response.status === 410 || response.status === 400) {
      await supabase.from("device_tokens").delete().eq("token", deviceToken);
      console.log(`Removed invalid token ${deviceToken.slice(0, 8)}...`);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Main handler
// ═══════════════════════════════════════════════════════════════════

serve(async (req: Request) => {
  try {
    const body = await req.json();

    // Supabase webhook sends: { type: "INSERT", table: "notifications", record: {...} }
    const record: NotificationRecord = body.record;

    if (!record || !record.user_id || !record.actor_id) {
      return new Response(JSON.stringify({ error: "Invalid payload" }), {
        status: 400,
      });
    }

    // Don't send push for self-notifications (shouldn't happen, but safety check)
    if (record.user_id === record.actor_id) {
      return new Response(JSON.stringify({ skipped: "self-notification" }), {
        status: 200,
      });
    }

    // Get all device tokens for the recipient
    const { data: tokens, error: tokenError } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", record.user_id)
      .eq("platform", "ios");

    if (tokenError || !tokens || tokens.length === 0) {
      console.log(`No device tokens for user ${record.user_id}`);
      return new Response(
        JSON.stringify({ skipped: "no tokens" }),
        { status: 200 }
      );
    }

    // Get actor username for the notification message
    const actorName = await getActorUsername(record.actor_id);

    // Build the push payload
    const payload = buildAPNsPayload(record.type, actorName);

    // Send to all devices
    const results = await Promise.allSettled(
      tokens.map((t: { token: string }) => sendPush(t.token, payload))
    );

    const sent = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.filter((r) => r.status === "rejected").length;

    console.log(
      `Push sent: ${sent} succeeded, ${failed} failed for notification ${record.id}`
    );

    return new Response(
      JSON.stringify({ sent, failed, notificationId: record.id }),
      { status: 200 }
    );
  } catch (err) {
    console.error("Push notification error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500 }
    );
  }
});
