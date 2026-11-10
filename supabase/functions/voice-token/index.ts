// دالة Edge: voice-token — تصدر تصريح LiveKit بعد التحقق من الدور واللعبة على الخادم.
// قواعد الميكروفون: نهارًا المتحدث وحده، ليلًا فريق المافيا في قناتهم السرية، والباقون استماع فقط.
import { createClient } from "npm:@supabase/supabase-js@2";

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function livekitToken(
  apiKey: string, secret: string, identity: string, name: string, room: string, canPublish: boolean,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${b64url(JSON.stringify({
    iss: apiKey,
    sub: identity,
    name,
    nbf: now - 10,
    exp: now + 600,
    video: { roomJoin: true, room, canPublish, canSubscribe: true, canPublishData: false },
  }))}`;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${b64url(sig)}`;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: u, error } = await supabase.auth.getUser(jwt);
  if (error || !u?.user) return json({ error: "unauthorized" }, 401);
  const uid = u.user.id;

  const body = await req.json().catch(() => ({}));
  const gameId = body.game_id as string | undefined;
  if (!gameId) return json({ error: "game_id required" }, 400);

  const { data: game } = await supabase.from("games")
    .select("id,status,phase,speech_order,speech_idx").eq("id", gameId).maybeSingle();
  if (!game || game.status !== "in_progress") return json({ error: "game_not_active" }, 409);

  const { data: player } = await supabase.from("game_players")
    .select("is_alive").eq("game_id", gameId).eq("user_id", uid).maybeSingle();
  if (!player) return json({ error: "not_a_player" }, 403);

  const { data: secret } = await supabase.from("game_secrets")
    .select("role").eq("game_id", gameId).eq("user_id", uid).maybeSingle();
  const { data: prof } = await supabase.from("profiles").select("display_name,username").eq("id", uid).maybeSingle();
  const name = (prof?.display_name || prof?.username || "player") as string;

  const mafiaRoles = ["mafia", "red_mafia", "silencer"];
  let room = `game-${gameId}`;
  let canPublish = false;
  if (player.is_alive) {
    if (game.phase === "night" && mafiaRoles.includes(secret?.role ?? "")) {
      room = `mafia-${gameId}`;
      canPublish = true;
    } else if (game.phase === "day") {
      const cur = (game.speech_order ?? [])[game.speech_idx];
      canPublish = cur === uid;
    }
  }

  const url = Deno.env.get("LIVEKIT_URL")!;
  const token = await livekitToken(
    Deno.env.get("LIVEKIT_API_KEY")!, Deno.env.get("LIVEKIT_API_SECRET")!, uid, name, room, canPublish,
  );
  return json({ url, token, room, can_publish: canPublish, mafia: room.startsWith("mafia-") });
});
