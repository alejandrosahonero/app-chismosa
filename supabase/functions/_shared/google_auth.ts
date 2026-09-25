// Google service-account OAuth, shared by thread-push (FCM) and
// verify-purchase (Play Developer API). Signs a JWT with WebCrypto and trades
// it for an access token; tokens are cached per account and scope until five
// minutes before they expire.

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const cache = new Map<string, { value: string; expiresAt: number }>();

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

export async function accessToken(
  account: ServiceAccount,
  scope: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const key = `${account.client_email} ${scope}`;
  const hit = cache.get(key);
  if (hit && hit.expiresAt - 300 > now) return hit.value;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const signingKey = await importPrivateKey(account.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      signingKey,
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
  cache.set(key, {
    value: json.access_token,
    expiresAt: now + json.expires_in,
  });
  return json.access_token;
}
