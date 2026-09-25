// Push notification for a new thread message.
//
// Called through pg_net by two triggers:
//   - `messages_after_insert_push` (0006) with `{ "message_id": "<uuid>" }`;
//   - `stories_after_insert_push` (0007) with `{ "continuation_id": "<uuid>" }`
//     when an author publishes the next part of a story: everyone who entered
//     the previous part's thread, or liked it, is told;
//   - `reports_names_someone` / `review_content()` (0008) with
//     `{ "hidden_story_id" }` or `{ "restored_story_id" }`: the author is told
//     their story was hidden pending review, and again if it comes back.
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
import { accessToken, type ServiceAccount } from "../_shared/google_auth.ts";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

const CHANNEL_ID = "thread_messages"; // PushService.channelId in the app.

function clip(text: string, max: number): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : `${flat.slice(0, max - 1)}…`;
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("PUSH_SECRET");
  if (!secret || request.headers.get("x-push-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  let payload: {
    message_id?: string;
    continuation_id?: string;
    hidden_story_id?: string;
    restored_story_id?: string;
  };
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
  if (payload.hidden_story_id) {
    return await notifyAuthor(supabase, payload.hidden_story_id, "hidden");
  }
  if (payload.restored_story_id) {
    return await notifyAuthor(supabase, payload.restored_story_id, "restored");
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

// The next part of a story: everyone who followed the previous part hears
// about it once. No "once until read" rule here — a new part is
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

  // Everyone "following" the previous part: whoever entered its thread (and
  // did not mute it) and whoever liked it.
  const [{ data: members }, { data: likers }] = await Promise.all([
    supabase.from("thread_members").select("user_id")
      .eq("story_id", story.parent_id).eq("muted", false),
    supabase.from("story_likes").select("user_id")
      .eq("story_id", story.parent_id),
  ]);
  const followers = [
    ...new Set<string>([
      ...(members ?? []).map((m: { user_id: string }) => m.user_id),
      ...(likers ?? []).map((l: { user_id: string }) => l.user_id),
    ]),
  ]
    .filter((id) => id !== story.author_id)
    .map((user_id) => ({ user_id }));
  const recipients = await withoutBlocks(supabase, story.author_id, followers);
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

// The author's own story was hidden by a "names someone" report, or came back
// after review. In the author's first language: this one is about them.
async function notifyAuthor(
  supabase: Client,
  storyId: string,
  kind: "hidden" | "restored",
): Promise<Response> {
  const { data: story } = await supabase
    .from("stories")
    .select("id, body, author_id")
    .eq("id", storyId)
    .maybeSingle();
  if (!story) return new Response("skip");
  const { data: profile } = await supabase
    .from("profiles").select("languages").eq("id", story.author_id)
    .maybeSingle();
  const en = (profile?.languages ?? [])[0] === "en";

  const title = kind === "hidden"
    ? (en ? "Your story is hidden for now" : "Tu historia está oculta por ahora")
    : (en ? "Your story is back" : "Tu historia vuelve a estar visible");
  const body = kind === "hidden"
    ? (en
      ? "Someone reported that it points at a real person. We will review it and let you know."
      : "Alguien ha indicado que señala a una persona real. La revisaremos y te avisaremos.")
    : (en
      ? "We reviewed it and it follows the rules."
      : "La hemos revisado y cumple las normas.");

  await send(supabase, [story.author_id], {
    title,
    body: `${body} «${clip(story.body, 60)}»`,
    storyId: story.id,
    kind,
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
  content: { title: string; body: string; storyId: string; kind?: string },
): Promise<void> {
  const { data: devices } = await supabase
    .from("devices")
    .select("fcm_token")
    .in("user_id", userIds);
  if (!devices || devices.length === 0) return;

  const account = JSON.parse(
    Deno.env.get("FCM_SERVICE_ACCOUNT")!,
  ) as ServiceAccount;
  const token = await accessToken(account, FCM_SCOPE);
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
          // `kind` tells the app where a tap lands: a review notice opens
          // "Mis historias", everything else the thread.
          data: { story_id: content.storyId, kind: content.kind ?? "thread" },
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
