// دالة Edge: send-push — ترسل إشعارات FCM لرسائل جدول push_outbox
// تُستدعى من Database Webhook فقط (يضيف مفتاح service_role تلقائيًا). نرفض أي نداء بغيره.
import { createClient } from "npm:@supabase/supabase-js@2";

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function jwtRole(authHeader: string | null): string | null {
  try {
    const token = (authHeader ?? "").replace(/^Bearer\s+/i, "");
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload)).role ?? null;
  } catch {
    return null;
  }
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

async function fcmAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error("FCM auth failed: " + JSON.stringify(json));
  return json.access_token;
}

Deno.serve(async (req) => {
  if (jwtRole(req.headers.get("Authorization")) !== "service_role") {
    return new Response("forbidden", { status: 403 });
  }
  const payload = await req.json().catch(() => null);
  const rec = payload?.record;
  if (!rec?.user_ids?.length) return new Response("no record", { status: 400 });

  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saRaw) return new Response("FCM_SERVICE_ACCOUNT missing", { status: 500 });
  const sa = JSON.parse(saRaw);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: tokens } = await supabase.from("push_tokens").select("token").in("user_id", rec.user_ids);
  if (!tokens?.length) return Response.json({ sent: 0 });

  const access = await fcmAccessToken(sa);
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(rec.data ?? {})) data[k] = String(v);

  let sent = 0;
  const dead: string[] = [];
  await Promise.all(tokens.map(async ({ token }: { token: string }) => {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: rec.title, body: rec.body },
          data,
          android: { priority: "HIGH", notification: { channel_id: "game_events" } },
        },
      }),
    });
    if (r.ok) sent++;
    else {
      const t = await r.text();
      if (r.status === 404 || t.includes("UNREGISTERED")) dead.push(token);
    }
  }));
  if (dead.length) await supabase.from("push_tokens").delete().in("token", dead);
  return Response.json({ sent, removed: dead.length });
});
