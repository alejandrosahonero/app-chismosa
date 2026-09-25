// Push notification for a new thread message.
//
// Called through pg_net by two triggers:
//   - `messages_after_insert_push` (0006) with `{ "message_id": "<uuid>" }`;
//   - `stories_after_insert_push` (0007) with `{ "continuation_id": "<uuid>" }`
//     when an author publishes the next part of a story: everyone who entered
//     the previous part's thread is told.
// Works out who should hear about it and sends through FCM HTTP v1.
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

  let payload: { message_id?: string; continuation_id?: string };
  try {
    payload = await request.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  if (payload.continuation_id) {
    return await notifyContinuation(supabase, payload.continuation_id);
  }
  const messageId = payload.message_id;
  if (!messageId) return new Response("bad request", { status: 400 });

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

  const recipients = await withoutBlocks(supabase, sender.user_id, due);
  if (recipients.length === 0) return new Response("nobody");

  await send(supabase, recipients.map((m) => m.user_id), {
    title: clip(story.body, 60),
    body: clip(`${sender.alias}: ${message.body}`, 160),
    storyId: story.id,
  });

  await supabase.from("thread_members")
    .update({ last_notified_at: new Date().toISOString() })
    .in("id", recipients.map((m) => m.id));

  return new Response("ok");
});

// deno-lint-ignore no-explicit-any
type Client = any;

// The next part of a story: everyone in the previous part's thread who has not
// muted it hears about it once. No "once until read" rule here — a new part is
// an event, not chatter.
async function notifyContinuation(
  supabase: Client,
  storyId: string,
): Promise<Response> {
  const { data: story } = await supabase
    .from("stories")
    .select("id, body, parent_id, author_id, chapter, hidden")
    .eq("id", storyId)
    .maybeSingle();
  if (!story || story.hidden || !story.parent_id) return new Response("skip");

  const { data: members } = await supabase
    .from("thread_members")
    .select("id, user_id")
    .eq("story_id", story.parent_id)
    .eq("muted", false)
    .neq("user_id", story.author_id);
  const recipients = await withoutBlocks(supabase, story.author_id, members ?? []);
  if (recipients.length === 0) return new Response("nobody");

  await send(supabase, recipients.map((m) => m.user_id), {
    // The app shows the story, not a translated label: a push is built once
    // for readers of every language, and the part number reads the same in all.
    title: `#${story.chapter} · ${clip(story.body, 50)}`,
    body: clip(story.body, 160),
    storyId: story.id,
  });
  return new Response("ok");
}

// Drops anyone on either side of a block with [writer].
async function withoutBlocks<T extends { user_id: string }>(
  supabase: Client,
  writer: string,
  members: T[],
): Promise<T[]> {
  if (members.length === 0) return members;
  const userIds = members.map((m) => m.user_id);
  const [{ data: blockedBy }, { data: blocking }] = await Promise.all([
    supabase.from("blocks").select("blocker_id")
      .eq("blocked_id", writer).in("blocker_id", userIds),
    supabase.from("blocks").select("blocked_id")
      .eq("blocker_id", writer).in("blocked_id", userIds),
  ]);
  const excluded = new Set<string>([
    ...(blockedBy ?? []).map((b: { blocker_id: string }) => b.blocker_id),
    ...(blocking ?? []).map((b: { blocked_id: string }) => b.blocked_id),
  ]);
  return members.filter((m) => !excluded.has(m.user_id));
}

// Sends one notification to every device of [userIds] and forgets the tokens
// FCM says are dead.
async function send(
  supabase: Client,
  userIds: string[],
  content: { title: string; body: string; storyId: string },
): Promise<void> {
  const { data: devices } = await supabase
    .from("devices")
    .select("fcm_token")
    .in("user_id", userIds);
  if (!devices || devices.length === 0) return;

  const account = JSON.parse(
    Deno.env.get("FCM_SERVICE_ACCOUNT")!,
  ) as ServiceAccount;
  const token = await accessToken(account);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  const stale: string[] = [];

  await Promise.all(devices.map(async (device: { fcm_token: string }) => {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: device.fcm_token,
          notification: { title: content.title, body: content.body },
          data: { story_id: content.storyId },
          android: {
            // One notification per thread in the tray: a newer message
            // replaces the older one instead of stacking.
            collapse_key: content.storyId,
            notification: {
              channel_id: CHANNEL_ID,
              tag: content.storyId,
              // A gossip app's notifications are exactly what should not be
              // readable on a locked screen by whoever picks the phone up.
              visibility: "PRIVATE",
            },
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

  if (stale.length > 0) {
    await supabase.from("devices").delete().in("fcm_token", stale);
  }
}
