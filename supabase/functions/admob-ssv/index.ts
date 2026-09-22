// AdMob server-side verification (SSV) callback.
//
// AdMob calls this URL with a GET after a user finishes a rewarded ad. The query
// string is signed by Google; if the signature checks out, the user named in
// `user_id` gets one post credit.
//
// Why a server at all: a credit the phone could grant itself is a limit that
// does not exist. The app only ever *reads* `post_credits`.
//
// Deploy (free plan, no card):
//   supabase functions deploy admob-ssv --no-verify-jwt
//
// `--no-verify-jwt` is required: the caller is Google, which has no Supabase
// session. The Google signature is what authenticates the request instead.
//
// Then, in the AdMob console → the rewarded ad unit → "Server-side
// verification", set the callback URL to:
//   https://<project-ref>.supabase.co/functions/v1/admob-ssv
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform. The
// service role key never leaves this function.

import { createClient } from "npm:@supabase/supabase-js@2";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";

// Google rotates the keys rarely; an hour of caching keeps a burst of
// callbacks from each fetching them, and a key id we have not seen forces a
// refresh anyway.
const KEY_TTL_MS = 60 * 60 * 1000;
let cachedKeys: Map<string, CryptoKey> = new Map();
let cachedAt = 0;

async function loadKeys(force = false): Promise<Map<string, CryptoKey>> {
  if (!force && cachedKeys.size > 0 && Date.now() - cachedAt < KEY_TTL_MS) {
    return cachedKeys;
  }
  const response = await fetch(KEYS_URL);
  if (!response.ok) throw new Error(`keys: HTTP ${response.status}`);
  const body = (await response.json()) as {
    keys: { keyId: number; base64: string }[];
  };

  const keys = new Map<string, CryptoKey>();
  for (const entry of body.keys) {
    const der = Uint8Array.from(atob(entry.base64), (c) => c.charCodeAt(0));
    keys.set(
      String(entry.keyId),
      await crypto.subtle.importKey(
        "spki",
        der,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
      ),
    );
  }
  cachedKeys = keys;
  cachedAt = Date.now();
  return keys;
}

function base64UrlToBytes(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

// Google signs with DER-encoded ECDSA; WebCrypto verifies the raw r||s form.
function derToRaw(der: Uint8Array): Uint8Array {
  let offset = 2; // SEQUENCE tag + length
  if (der[1] & 0x80) offset += der[1] & 0x7f;

  const readInt = (): Uint8Array => {
    if (der[offset] !== 0x02) throw new Error("bad DER");
    const length = der[offset + 1];
    let value = der.slice(offset + 2, offset + 2 + length);
    offset += 2 + length;
    while (value.length > 32 && value[0] === 0) value = value.slice(1);
    const out = new Uint8Array(32);
    out.set(value, 32 - value.length);
    return out;
  };

  const r = readInt();
  const s = readInt();
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

async function verify(query: string): Promise<URLSearchParams | null> {
  // The signed content is everything before `&signature=`, byte for byte as
  // it arrived. Re-serialising the parsed parameters would change the order or
  // the escaping and break the check.
  const cut = query.indexOf("&signature=");
  if (cut < 0) return null;
  const message = query.slice(0, cut);

  const params = new URLSearchParams(query);
  const signature = params.get("signature");
  const keyId = params.get("key_id");
  if (!signature || !keyId) return null;

  let keys = await loadKeys();
  if (!keys.has(keyId)) keys = await loadKeys(true);
  const key = keys.get(keyId);
  if (!key) return null;

  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    derToRaw(base64UrlToBytes(signature)),
    new TextEncoder().encode(message),
  );
  return ok ? params : null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const query = url.search.startsWith("?") ? url.search.slice(1) : url.search;

  // AdMob pings the URL with no parameters when the callback is first saved in
  // the console. It has to answer 200 or the console refuses the URL.
  if (!query) return new Response("ok");

  let params: URLSearchParams | null;
  try {
    params = await verify(query);
  } catch (error) {
    console.error("verification error", error);
    // 500 so AdMob retries: a transient failure fetching the keys must not
    // cost the user the reward they watched a video for.
    return new Response("error", { status: 500 });
  }
  if (!params) return new Response("bad signature", { status: 403 });

  const userId = params.get("user_id") ?? "";
  const transactionId = params.get("transaction_id") ?? "";

  // A valid signature over a request that does not name one of our users is
  // still a request we cannot pay. 200 so AdMob stops retrying it.
  if (!UUID.test(userId) || !transactionId) {
    console.warn("signed callback without a usable user", { userId });
    return new Response("ignored");
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data, error } = await supabase.rpc("grant_post_credit", {
    p_user: userId,
    p_transaction: transactionId,
  });
  if (error) {
    console.error("grant failed", error);
    return new Response("error", { status: 500 });
  }

  return new Response(data ? "granted" : "duplicate");
});
