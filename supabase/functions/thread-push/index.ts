// Push notification for a new thread message.
//
// Called by the `messages_after_insert_push` trigger (0006_push.sql) with
// `{ "message_id": "<uuid>" }`. Works out who should hear about it and sends
// through FCM HTTP v1.
//
// Deploy (free plan, no card):
//   supabase secrets set PUSH_SECRET=<same string as the vault's push_secret>
//   supabase secrets set --env-file <file with FCM_SERVICE_ACCOUNT=...>
//   supabase functions deploy thread-push --no-verify-jwt
//
// `--no-verify-jwt` because the caller is the database, which has no user
// session; the shared secret in `x-push-secret` authenticates it instead.
// FCM_SERVICE_ACCOUNT is the JSON key of a Firebase service account (Project
// settings → Service accounts → Generate new private key). It lives only here,
// never in the app or the repo.
//
// Who is told:
//   - members of the thread, except whoever wrote the message;
//   - who have not muted it;
//   - who have not been told already since they last opened it;
//   - and who have not blocked the writer (nor been blocked by them).
//
// What the notification says: the alias and the message. Never anything that
// identifies an account — there is nothing of that in a thread to begin with.

import { createClient } from "npm:@supabase/supabase-js@2";

const CHANNEL_ID = "thread_messages"; // PushService.channelId in the app.

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedToken: { value: string; expiresAt: number } | null = null;

function base64url(input: Uint8Array | string): string {
  const raw = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let binary = "";
  for (const byte of raw) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// An OAuth access token for FCM, from a JWT signed with the service account.
// Tokens last an hour; one is reused until five minutes before it expires.
async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 300 > now) {
    return cachedToken.value;
  }

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await importPrivateKey(account.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  const jwt = `${header}.${claims}.${base64url(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) throw new Error(`oauth: HTTP ${response.status}`);
  const json = (await response.json()) as {
    access_token: string;
    expires_in: number;
  };
  cachedToken = { value: json.access_token, expiresAt: now + json.expires_in };
  return json.access_token;
}

function clip(text: string, max: number): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : `${flat.slice(0, max - 1)}…`;
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("PUSH_SECRET");
  if (!secret || request.headers.get("x-push-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  let messageId: string | undefined;
  try {
    messageId = ((await request.json()) as { message_id?: string }).message_id;
  } catch {
    return new Response("bad request", { status: 400 });
  }
  if (!messageId) return new Response("bad request", { status: 400 });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: message } = await supabase
    .from("messages")
    .select("id, story_id, member_id, body, hidden")
    .eq("id", messageId)
    .maybeSingle();
  if (!message || message.hidden) return new Response("skip");

  const [{ data: sender }, { data: story }] = await Promise.all([
    supabase.from("thread_members").select("user_id, alias")
      .eq("id", message.member_id).single(),
    supabase.from("stories").select("id, body, hidden")
      .eq("id", message.story_id).single(),
  ]);
  if (!sender || !story || story.hidden) return new Response("skip");

  const { data: members } = await supabase
    .from("thread_members")
    .select("id, user_id, last_read_at, last_notified_at")
    .eq("story_id", message.story_id)
    .eq("muted", false)
    .neq("user_id", sender.user_id);

  // One notification per thread until it is opened. Writing in a thread
  // counts as opening it (last_read_at moves), which re-arms it.
  const due = (members ?? []).filter((m) =>
    m.last_notified_at === null ||
    new Date(m.last_notified_at) < new Date(m.last_read_at)
  );
  if (due.length === 0) return new Response("nobody");

  // Blocks either way round: a blocked person's messages never reach the
  // blocker, and the blocker should not be summoned into their thread by them.
  const userIds = due.map((m) => m.user_id);
  const [{ data: blockedBy }, { data: blocking }] = await Promise.all([
    supabase.from("blocks").select("blocker_id")
      .eq("blocked_id", sender.user_id).in("blocker_id", userIds),
    supabase.from("blocks").select("blocked_id")
      .eq("blocker_id", sender.user_id).in("blocked_id", userIds),
  ]);
  const excluded = new Set<string>([
    ...(blockedBy ?? []).map((b) => b.blocker_id),
    ...(blocking ?? []).map((b) => b.blocked_id),
  ]);
  const recipients = due.filter((m) => !excluded.has(m.user_id));
  if (recipients.length === 0) return new Response("nobody");

  const { data: devices } = await supabase
    .from("devices")
    .select("fcm_token")
    .in("user_id", recipients.map((m) => m.user_id));
  if (!devices || devices.length === 0) return new Response("no devices");

  const account = JSON.parse(
    Deno.env.get("FCM_SERVICE_ACCOUNT")!,
  ) as ServiceAccount;
  let token: string;
  try {
    token = await accessToken(account);
  } catch (error) {
    console.error(error);
    return new Response("oauth failed", { status: 500 });
  }

  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  const title = clip(story.body, 60);
  const body = clip(`${sender.alias}: ${message.body}`, 160);
  const stale: string[] = [];

  await Promise.all(devices.map(async (device) => {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: device.fcm_token,
          notification: { title, body },
          data: { story_id: story.id },
          android: {
            // One notification per thread in the tray: a newer message
            // replaces the older one instead of stacking.
            collapse_key: story.id,
            notification: { channel_id: CHANNEL_ID, tag: story.id },
          },
        },
      }),
    });
    if (response.status === 404 || response.status === 400) {
      // UNREGISTERED / INVALID_ARGUMENT: the app was uninstalled or the token
      // rotated. Forget it so the next message does not try again.
      stale.push(device.fcm_token);
    } else if (!response.ok) {
      console.error(`fcm: HTTP ${response.status}`, await response.text());
    }
  }));

  await Promise.all([
    stale.length > 0
      ? supabase.from("devices").delete().in("fcm_token", stale)
      : Promise.resolve(),
    supabase.from("thread_members")
      .update({ last_notified_at: new Date().toISOString() })
      .in("id", recipients.map((m) => m.id)),
  ]);

  return new Response("ok");
});
