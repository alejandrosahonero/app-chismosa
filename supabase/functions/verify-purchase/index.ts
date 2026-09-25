// Verifies a Google Play purchase and grants (or revokes) premium.
//
// Called by the app, with the user's session, after every purchase and every
// restore — including the silent restore on each app start, which is how a
// refund eventually takes premium away again.
//
//   POST { "purchase_token": "...", "product_id": "premium_remove_ads" }
//   → 200 { "premium": true | false, "state": 0 | 1 | 2 }
//
// The phone's word is never enough: the token is looked up with the Play
// Developer API (free), and only the answer from Google decides. The result
// is written by apply_purchase() (0008), which the client cannot call.
//
// Setup, once (all free):
//   1. Play Console → Settings → API access → link a Google Cloud project.
//   2. In that project, create a service account and a JSON key.
//   3. Play Console → Users and permissions → invite the service account's
//      e-mail with "View app information" and "View financial data".
//      Permissions can take up to 24 h to apply.
//   4. supabase secrets set --env-file <file with PLAY_SERVICE_ACCOUNT=<json>>
//   5. supabase functions deploy verify-purchase
//      (JWT verification stays ON: the caller must be a signed-in user.)

import { createClient } from "npm:@supabase/supabase-js@2";
import { accessToken, type ServiceAccount } from "../_shared/google_auth.ts";

const PACKAGE = "com.alejandrosahonero.chismosa";
const PRODUCTS = new Set(["premium_remove_ads"]);
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // Who is asking: the user behind the bearer token, resolved by Supabase
  // itself. A user id in the body would be anyone's to claim.
  const jwt = (request.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const { data: auth } = await service.auth.getUser(jwt);
  const userId = auth?.user?.id;
  if (!userId) return json({ error: "unauthenticated" }, 401);

  let token: string | undefined;
  let product: string | undefined;
  try {
    const body = await request.json();
    token = body.purchase_token;
    product = body.product_id;
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!token || !product || !PRODUCTS.has(product)) {
    return json({ error: "bad_request" }, 400);
  }

  const account = JSON.parse(
    Deno.env.get("PLAY_SERVICE_ACCOUNT")!,
  ) as ServiceAccount;

  let purchase: { purchaseState?: number; orderId?: string };
  try {
    const bearer = await accessToken(account, SCOPE);
    const response = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases/products/${
        encodeURIComponent(product)
      }/tokens/${encodeURIComponent(token)}`,
      { headers: { Authorization: `Bearer ${bearer}` } },
    );
    if (response.status === 404 || response.status === 400) {
      // Not a real purchase of this app: never grant, and say so.
      return json({ premium: false, state: -1 });
    }
    if (!response.ok) {
      console.error(`play: HTTP ${response.status}`, await response.text());
      // Transient: the app keeps whatever it had and asks again later.
      return json({ error: "play_unavailable" }, 502);
    }
    purchase = await response.json();
  } catch (error) {
    console.error(error);
    return json({ error: "play_unavailable" }, 502);
  }

  const state = purchase.purchaseState ?? 2;
  const { data: premium, error } = await service.rpc("apply_purchase", {
    p_user: userId,
    p_token: token,
    p_product: product,
    p_state: state,
    p_order: purchase.orderId ?? null,
  });
  if (error) {
    console.error(error);
    return json({ error: "database" }, 500);
  }
  return json({ premium: premium === true, state });
});
