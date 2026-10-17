package com.mafia.game.ui

import android.view.WindowManager
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.mafia.game.data.RealtimeWatcher
import com.mafia.game.data.SupabaseClient
import com.mafia.game.util.AppState
import com.mafia.game.util.Notifier
import com.mafia.game.util.findActivity
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.OffsetDateTime

private data class Player(
    val id: String, val name: String, val seat: Int, val alive: Boolean,
    val role: String?, val by: String?
)
private data class MyRole(
    val role: String, val bullets: Int, val lastProtected: String?,
    val pull: String?, val teammates: List<String>
)
private data class Ev(val id: Long, val round: Int, val type: String, val payload: JSONObject)
private data class VoteRow(val round: Int, val voter: String, val target: String?)
private data class Msg(val id: Long, val userId: String, val channel: String, val body: String)
private data class Snap(
    val game: JSONObject, val players: List<Player>, val my: MyRole?,
    val events: List<Ev>, val votes: List<VoteRow>, val messages: List<Msg>, val voiceLink: String?
)
private class Confirm(val text: String, val run: suspend () -> Unit)

private suspend fun loadSnap(client: SupabaseClient, gameId: String): Snap {
    val game = JSONArray(client.get("/rest/v1/games?select=*&id=eq.$gameId")).getJSONObject(0)
    val players = JSONArray(client.get(
        "/rest/v1/game_players?select=user_id,seat_no,is_alive,revealed_role,eliminated_by,profiles(username,display_name)&game_id=eq.$gameId&order=seat_no.asc"
    )).objects().map { o ->
        val p = o.optJSONObject("profiles")
        val nm = (p?.strOrNull("display_name") ?: "").ifBlank { p?.strOrNull("username") ?: "" }.ifBlank { "لاعب" }
        Player(o.getString("user_id"), nm, o.getInt("seat_no"), o.getBoolean("is_alive"),
            o.strOrNull("revealed_role"), o.strOrNull("eliminated_by"))
    }
    val my = JSONArray(client.rpc("get_my_role", JSONObject().put("p_game_id", gameId))).optJSONObject(0)?.let { o ->
        val t = o.optJSONArray("teammates")
        MyRole(o.getString("my_role"), o.optInt("bullets"), o.strOrNull("last_protected_id"),
            o.strOrNull("pull_target_id"), if (t == null) emptyList() else (0 until t.length()).map { t.getString(it) })
    }
    val events = JSONArray(client.get(
        "/rest/v1/game_events?select=id,round_no,event_type,payload&game_id=eq.$gameId&order=id.asc&limit=300"
    )).objects().map { Ev(it.getLong("id"), it.optInt("round_no"), it.getString("event_type"), it.optJSONObject("payload") ?: JSONObject()) }
    val votes = JSONArray(client.get(
        "/rest/v1/votes?select=round_no,voter_id,target_id&game_id=eq.$gameId&order=round_no.asc"
    )).objects().map { VoteRow(it.getInt("round_no"), it.getString("voter_id"), it.strOrNull("target_id")) }
    val messages = JSONArray(client.get(
        "/rest/v1/game_messages?select=id,user_id,channel,body&game_id=eq.$gameId&order=id.asc&limit=100"
    )).objects().map { Msg(it.getLong("id"), it.getString("user_id"), it.getString("channel"), it.getString("body")) }
    val roomId = game.optString("room_id")
    val voice = runCatching {
        JSONArray(client.get("/rest/v1/rooms?select=voice_link&id=eq.$roomId")).optJSONObject(0)?.strOrNull("voice_link")
    }.getOrNull()
    return Snap(game, players, my, events, votes, messages, voice)
}

private fun deathsText(arr: JSONArray?, names: Map<String, String>): List<String> {
    if (arr == null) return emptyList()
    return arr.objects().map { d ->
        val n = names[d.optString("user_id")] ?: "لاعب"
        val role = d.strOrNull("role")?.let { " (${Roles.nameAr(it)})" } ?: ""
        val cause = when (d.optString("cause")) {
            "explosion" -> " — بتفجير"
            "pulled" -> " — سحبه الولد معه"
            "hunt" -> " — برصاصة الصياد"
            "vote" -> " — بالتصويت"
            "left" -> " — انسحب"
            else -> ""
        }
        "مات $n$role$cause"
    }
}

private fun eventLines(e: Ev, names: Map<String, String>): List<String> = when (e.type) {
    "game_started" -> listOf("بدأت اللعبة بـ ${e.payload.optInt("players")} لاعبين")
    "night_result" -> {
        val lines = deathsText(e.payload.optJSONArray("deaths"), names).toMutableList()
        if (e.payload.optBoolean("assassination_failed")) lines.add(0, "عملية اغتيال فاشلة")
        if (lines.isEmpty()) lines.add("مرّت الليلة بسلام ولم يمت أحد")
        lines
    }
    "day_started" -> listOf("بدأ التبرير: لكل لاعب دور للكلام ثم التصويت")
    "silenced" -> listOf("أُسكت " + (names[e.payload.optString("user_id")] ?: "لاعب") + " اليوم")
    "justification_again" -> listOf("خرج مافيا! جولة تبرير جديدة ثم تصويت (بلا ليل)")
    "voting_started" -> listOf("بدأ التصويت")
    "player_eliminated" -> deathsText(e.payload.optJSONArray("deaths"), names)
    "no_elimination" -> listOf(if (e.payload.optBoolean("tie")) "تعادلت الأصوات ولم يُقصَ أحد" else "لم يصوّت أحد")
    "hunter_shot" -> listOf("الصياد ${names[e.payload.optString("hunter_id")] ?: ""} أطلق النار") +
        deathsText(e.payload.optJSONArray("deaths"), names)
    "night_started" -> listOf("بدأت الليلة ${e.round}")
    "game_ended" -> listOf(if (e.payload.optString("winner") == "citizens") "انتهت اللعبة: فاز المواطنون" else "انتهت اللعبة: فازت المافيا")
    "boy_pulled" -> deathsText(e.payload.optJSONArray("deaths"), names)
    "player_left" -> deathsText(e.payload.optJSONArray("deaths"), names)
    "game_aborted" -> listOf("أُلغيت اللعبة")
    else -> emptyList()
}

@Composable
private fun PickPanel(
    title: String, candidates: List<Player>, busy: Boolean,
    onPick: (Player) -> Unit, skipLabel: String? = null, onSkip: (() -> Unit)? = null
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            if (candidates.isEmpty()) Text("لا يوجد أهداف متاحة.")
            candidates.forEach { p ->
                Button(onClick = { onPick(p) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(p.name) }
            }
            if (skipLabel != null && onSkip != null) {
                OutlinedButton(onClick = onSkip, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(skipLabel) }
            }
        }
    }
}

@Composable
private fun ChatPanel(title: String, msgs: List<Msg>, names: Map<String, String>, canSend: Boolean, onSend: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            msgs.forEach { Text("${names[it.userId] ?: "لاعب"}: ${it.body}") }
            if (canSend) {
                OutlinedTextField(text, { text = it.take(300) }, label = { Text("اكتب رسالتك") }, modifier = Modifier.fillMaxWidth())
                Button(enabled = text.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = {
                    val t = text.trim()
                    if (t.isNotEmpty()) { onSend(t); text = "" }
                }) { Text("إرسال") }
            }
        }
    }
}

@Composable
fun GameScreen(client: SupabaseClient, gameId: String, onExit: () -> Unit) {
    val scope = rememberCoroutineScope()
    var snap by remember { mutableStateOf<Snap?>(null) }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var showRole by remember { mutableStateOf(true) }
    var nowMs by remember { mutableStateOf(System.currentTimeMillis()) }
    var sentRound by remember { mutableStateOf(-1) }
    var sentLabel by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf<Confirm?>(null) }
    var reportTarget by remember { mutableStateOf<Player?>(null) }
    val me = client.currentUserId()
    val ctx = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val trigger = remember { Channel<Unit>(Channel.CONFLATED) }

    // منع لقطة الشاشة أثناء إظهار ورقة الدور فقط
    DisposableEffect(showRole) {
        val act = ctx.findActivity()
        if (showRole) act?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { act?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    }
    // Realtime: تحديث فوري عند أي تغيير (الاستطلاع كل 3 ثوانٍ احتياط)
    DisposableEffect(gameId) {
        val w = RealtimeWatcher(client, gameId) { trigger.trySend(Unit) }
        w.start()
        onDispose { w.stop() }
    }

    LaunchedEffect(gameId) {
        while (true) {
            try {
                val st = snap?.game?.optString("status")
                if (st == null || st == "in_progress") {
                    runCatching { client.rpc("advance_phase", JSONObject().put("p_game_id", gameId)) }
                }
                snap = loadSnap(client, gameId)
            } catch (e: Exception) { msg = friendlyError(e) }
            withTimeoutOrNull(3000) { trigger.receive() }
        }
    }
    LaunchedEffect(Unit) { while (true) { nowMs = System.currentTimeMillis(); delay(1000) } }

    fun act(block: suspend () -> Unit) {
        scope.launch {
            busy = true; msg = ""
            try { block(); snap = loadSnap(client, gameId) } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }

    val s = snap
    val stateKey = s?.let {
        "${it.game.optString("phase")}|${it.game.optInt("round_no")}|${it.game.optInt("speech_idx")}|${it.game.optInt("vote_cycle")}|${it.game.optString("status")}"
    }
    var lastKey by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(stateKey) {
        val sn = snap
        if (stateKey != null && sn != null) {
            if (lastKey != null && lastKey != stateKey) {
                val ph = sn.game.optString("phase")
                val order = sn.game.optJSONArray("speech_order")
                val ix = sn.game.optInt("speech_idx")
                val curSpk = if (order != null && ix < order.length()) order.getString(ix) else null
                val (title, text) = when {
                    sn.game.optString("status") != "in_progress" -> "انتهت اللعبة" to "افتح التطبيق لمعرفة النتيجة"
                    ph == "day" && curSpk == me -> "دورك في الكلام" to "تكلّم وبرّر الآن"
                    ph == "day" -> "التبرير" to "بدأ دور كلام جديد"
                    ph == "night" -> "بدأ الليل" to "اختر قدرتك إن كان لديك"
                    ph == "voting" -> "بدأ التصويت" to "صوّت الآن"
                    else -> "" to ""
                }
                if (title.isNotEmpty()) {
                    Notifier.vibrate(ctx, if (curSpk == me) 500 else 200)
                    if (!AppState.foreground) Notifier.notify(ctx, title, text)
                }
            }
            lastKey = stateKey
        }
    }
    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (s == null) {
            Text("جارٍ تحميل اللعبة...")
            if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)
            OutlinedButton(onClick = onExit, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
            return@Column
        }

        val g = s.game
        val status = g.optString("status")
        val phase = g.optString("phase")
        val round = g.optInt("round_no")
        val names = s.players.associate { it.id to it.name }
        val meP = s.players.firstOrNull { it.id == me }
        val alive = s.players.filter { it.alive }
        val my = s.my
        val inProgress = status == "in_progress"
        val endsMs = g.strOrNull("phase_ends_at")?.let {
            runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull()
        }
        val left = if (endsMs != null) ((endsMs - nowMs) / 1000).coerceAtLeast(0L) else 0L

        // ---------- رأس الصفحة ----------
        val phaseAr = when (phase) { "night" -> "الليل"; "day" -> "التبرير"; "voting" -> "التصويت"; else -> "انتهت" }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text("$phaseAr — الجولة $round", style = MaterialTheme.typography.titleLarge)
                if (inProgress) Text("الوقت المتبقي: $left ثانية")
            }
            if (my != null) OutlinedButton(onClick = { showRole = true }) { Text("دوري") }
        }
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)
        s.voiceLink?.let { link ->
            OutlinedButton(onClick = { runCatching { uriHandler.openUri(link) } }, modifier = Modifier.fillMaxWidth()) {
                Text("🎙️ فتح الغرفة الصوتية")
            }
        }
        if (inProgress && g.strOrNull("pending_pull") != null) {
            Text("الولد يختار الآن من يسحبه معه...")
        }

        if (showRole && my != null) {
            AlertDialog(
                onDismissRequest = { showRole = false },
                confirmButton = { Button(onClick = { showRole = false }) { Text("حسنًا") } },
                title = { Text("دورك: ${Roles.nameAr(my.role)}") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Image(painterResource(Roles.cardRes(my.role)), contentDescription = Roles.nameAr(my.role),
                            modifier = Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth)
                        if (my.role == "silencer") {
                            Text("قدرتك: تُسكت لاعبًا كل ليلة، فلا يُمنح دور كلام في اليوم التالي (ويبقى يصوّت).")
                        }
                        if (Roles.isMafia(my.role) && my.teammates.isNotEmpty()) {
                            Text("زملاؤك في المافيا: " + my.teammates.joinToString("، ") { names[it] ?: "لاعب" })
                        }
                    }
                }
            )
        }
        confirm?.let { c ->
            AlertDialog(
                onDismissRequest = { confirm = null },
                title = { Text("تأكيد") }, text = { Text(c.text) },
                confirmButton = { Button(onClick = { confirm = null; act { c.run() } }) { Text("نعم") } },
                dismissButton = { TextButton(onClick = { confirm = null }) { Text("إلغاء") } }
            )
        }

        // ---------- النهاية ----------
        if (!inProgress) {
            val winner = g.strOrNull("winner")
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp)) {
                    Text(
                        when (winner) { "citizens" -> "فاز المواطنون"; "mafia" -> "فازت المافيا"; else -> "أُلغيت اللعبة" },
                        style = MaterialTheme.typography.headlineSmall
                    )
                    s.players.forEach { p -> Text("${p.name}: ${Roles.nameAr(p.role)}" + if (p.alive) "" else " (ميت)") }
                }
            }
            Button(onClick = onExit, modifier = Modifier.fillMaxWidth()) { Text("العودة للقائمة") }
        } else if (meP != null && !meP.alive) {
            if (g.strOrNull("pending_pull") == me) {
                PickPanel("الولد: اسحب لاعبًا معك الآن (مهلة قصيرة، وإلا يُنفَّذ اختيارك المسبق)",
                    alive.filter { it.id != me }, busy,
                    onPick = { p -> act { client.rpc("boy_pull", JSONObject().put("p_game_id", gameId).put("p_target_id", p.id)) } })
            }
            Card(Modifier.fillMaxWidth()) { Text("أنت خارج اللعبة. تتابع كمشاهد فقط.", Modifier.padding(12.dp)) }
        } else if (my != null) {
            val roundNow = round
            val sentNote = if (sentRound == roundNow) "✓ أُرسل اختيارك: $sentLabel (يمكنك تغييره قبل انتهاء الوقت)" else ""

            // الليل
            if (phase == "night") {
                val night = { action: String, target: String? ->
                    act {
                        val b = JSONObject().put("p_game_id", gameId).put("p_action", action)
                        if (target != null) b.put("p_target_id", target)
                        client.rpc("submit_night_action", b)
                        sentRound = roundNow
                        sentLabel = if (target == null) "تخطّي" else (names[target] ?: "")
                    }
                }
                when (my.role) {
                    "mafia", "red_mafia" -> {
                        val cands = alive.filter { it.id != me && it.id !in my.teammates }
                        PickPanel(
                            if (my.role == "red_mafia") "اختر ضحية الليلة (قرارك نهائي: أنت أكبر ورقة)" else "اقترح ضحية للفريق (قرار الأحمر نهائي)",
                            cands, busy, onPick = { night("kill", it.id) }, skipLabel = "تخطّي", onSkip = { night("skip", null) })
                    }
                    "silencer" -> PickPanel("من تُسكته غدًا؟ (لا يُمنح دور كلام)",
                        alive.filter { it.id != me && it.id !in my.teammates },
                        busy, onPick = { night("silence", it.id) }, skipLabel = "تخطّي", onSkip = { night("skip", null) })
                    "girl" -> PickPanel("من تحميه من الاغتيال الليلة؟", alive.filter { it.id != my.lastProtected },
                        busy, onPick = { night("protect", it.id) }, skipLabel = "تخطّي", onSkip = { night("skip", null) })
                    "sheikh" -> PickPanel("من تفجّر الليلة؟ (يموت فورًا ولا تمنعه الحماية)", alive.filter { it.id != me },
                        busy, onPick = { p -> confirm = Confirm("تفجير ${p.name}؟") { night("bomb", p.id) } },
                        skipLabel = "لا أفجّر أحدًا", onSkip = { night("skip", null) })
                    else -> Card(Modifier.fillMaxWidth()) { Text("الليل... لا قدرة لديك الآن. انتظر الصباح.", Modifier.padding(12.dp)) }
                }
                if (Roles.isMafia(my.role)) {
                    val sug = s.events.filter { it.type == "mafia_suggestion" && it.round == roundNow }
                        .groupBy { it.payload.optString("actor_id") }.mapValues { it.value.last() }
                    if (sug.isNotEmpty()) Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp)) {
                            Text("اقتراحات فريق المافيا", style = MaterialTheme.typography.titleMedium)
                            sug.forEach { (a, e) ->
                                val t = e.payload.strOrNull("target_id")
                                val what = when (e.payload.optString("action")) { "silence" -> "إسكات "; "kill" -> "اغتيال "; else -> "" }
                                Text("${names[a] ?: "لاعب"} ← " + (if (t == null) "تخطّي" else what + (names[t] ?: "")))
                            }
                        }
                    }
                }
                if (sentNote.isNotBlank()) Text(sentNote)
            }

            // النهار: الصياد
            if (phase == "day") {
                val order = g.optJSONArray("speech_order")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
                val idx = g.optInt("speech_idx")
                val cur = order.getOrNull(idx)
                val silencedId = g.strOrNull("silenced_id")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("دور الكلام (لكل لاعب دورة كاملة قبل التصويت)", style = MaterialTheme.typography.titleMedium)
                        order.forEachIndexed { i, id ->
                            val mark = when { i < idx -> "✓"; i == idx -> "◀ يتكلم الآن"; else -> "…" }
                            Text("$mark ${names[id] ?: "لاعب"}")
                        }
                        if (silencedId != null && alive.any { it.id == silencedId }) {
                            Text("🔇 مُسكَت اليوم: ${names[silencedId] ?: ""} (بلا دور كلام، ويصوّت)")
                        }
                    }
                }
                if (cur == me) {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("دورك الآن! تكلّم وبرّر. المتبقي $left ثانية", style = MaterialTheme.typography.titleMedium)
                            Button(enabled = !busy, modifier = Modifier.fillMaxWidth(),
                                onClick = { act { client.rpc("end_speech", JSONObject().put("p_game_id", gameId)) } }
                            ) { Text("أنهيت كلامي") }
                        }
                    }
                } else if (me == silencedId) {
                    Card(Modifier.fillMaxWidth()) { Text("🔇 أنت مُسكَت اليوم: لا دور كلام لك، لكنك تصوّت.", Modifier.padding(12.dp)) }
                }
                if (my.role == "hunter" && my.bullets > 0) {
                    PickPanel("الصياد: أطلق طلقتك الوحيدة (يموت الهدف دائمًا)", alive.filter { it.id != me }, busy,
                        onPick = { p -> confirm = Confirm("إطلاق النار على ${p.name}؟ لا رجعة فيه.") {
                            client.rpc("hunter_shoot", JSONObject().put("p_game_id", gameId).put("p_target_id", p.id)) } })
                }
            }

            // التصويت
            if (phase == "voting") {
                val voteCycle = g.optInt("vote_cycle", 1)
                val voted = s.votes.any { it.round == voteCycle && it.voter == me }
                if (voted) {
                    Card(Modifier.fillMaxWidth()) { Text("✓ تم تسجيل صوتك. بانتظار البقية.", Modifier.padding(12.dp)) }
                } else {
                    PickPanel("صوّت لإقصاء لاعب (لا يمكن تغيير الصوت)", alive.filter { it.id != me }, busy,
                        onPick = { p -> confirm = Confirm("التصويت ضد ${p.name}؟") {
                            client.rpc("cast_vote", JSONObject().put("p_game_id", gameId).put("p_target_id", p.id)) } },
                        skipLabel = "امتناع عن التصويت",
                        onSkip = { act { client.rpc("cast_vote", JSONObject().put("p_game_id", gameId)) } })
                }
            }

            // الولد: هدف السحب (في أي وقت)
            if (my.role == "boy") {
                PickPanel(
                    "الولد: اختر من تسحبه معك إذا قُتلت" + (my.pull?.let { " (الحالي: ${names[it] ?: ""})" } ?: ""),
                    alive.filter { it.id != me }, busy,
                    onPick = { p -> act { client.rpc("set_boy_target", JSONObject().put("p_game_id", gameId).put("p_target_id", p.id)) } },
                    skipLabel = "إلغاء الاختيار",
                    onSkip = { act { client.rpc("set_boy_target", JSONObject().put("p_game_id", gameId)) } })
            }
        }

        // ---------- الدردشة ----------
        val speechOrder = g.optJSONArray("speech_order")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
        val speaker = speechOrder.getOrNull(g.optInt("speech_idx"))
        val iAmAlive = meP?.alive == true
        val canPublic = inProgress && phase == "day" && speaker == me && iAmAlive
        val canMafia = inProgress && phase == "night" && my != null && Roles.isMafia(my.role) && iAmAlive
        val pubMsgs = s.messages.filter { it.channel == "public" }.takeLast(15)
        val mafMsgs = s.messages.filter { it.channel == "mafia" }.takeLast(15)
        if (pubMsgs.isNotEmpty() || canPublic) {
            ChatPanel("💬 كلام اللاعبين", pubMsgs, names, canPublic) { t ->
                act { client.rpc("send_message", JSONObject().put("p_game_id", gameId).put("p_body", t).put("p_channel", "public")) }
            }
        }
        if (my != null && Roles.isMafia(my.role) && (mafMsgs.isNotEmpty() || canMafia)) {
            ChatPanel("🕶️ دردشة المافيا (سرية)", mafMsgs, names, canMafia) { t ->
                act { client.rpc("send_message", JSONObject().put("p_game_id", gameId).put("p_body", t).put("p_channel", "mafia")) }
            }
        }

        // ---------- اللاعبون ----------
        Text("اللاعبون", style = MaterialTheme.typography.titleMedium)
        s.players.forEach { p ->
            val tag = buildString {
                if (p.id == me) append(" — أنت")
                if (my != null && p.id in my.teammates) append(" — مافيا")
                if (inProgress && p.alive && p.id == g.strOrNull("silenced_id")) append(" — 🔇 مُسكَت")
                if (!p.alive) append(" — ميت" + (p.role?.let { " (${Roles.nameAr(it)})" } ?: ""))
            }
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("${p.seat}. ${p.name}$tag", Modifier.padding(vertical = 10.dp))
                    if (p.id != me) TextButton(onClick = { reportTarget = p }) { Text("بلاغ") }
                }
            }
        }

        // ---------- سجل الأحداث ----------
        val lines = s.events.flatMap { e -> eventLines(e, names) }.takeLast(14).reversed()
        if (lines.isNotEmpty()) {
            Text("سجل اللعبة", style = MaterialTheme.typography.titleMedium)
            Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(10.dp)) { lines.forEach { Text("• $it") } } }
        }

        // ---------- تفاصيل الأصوات (حسب الصلاحية: مدير الغرفة، أو الجميع إن فُعّل) ----------
        val detail = s.votes.filter { it.voter != me }
        if (detail.isNotEmpty()) {
            Text("سجل التصويت التفصيلي", style = MaterialTheme.typography.titleMedium)
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(10.dp)) {
                    detail.groupBy { it.round }.forEach { (r, rows) ->
                        Text("الجولة $r", style = MaterialTheme.typography.titleSmall)
                        rows.forEach { v -> Text("${names[v.voter] ?: "لاعب"} ← " + (v.target?.let { names[it] } ?: "امتناع")) }
                    }
                }
            }
        }

        if (inProgress && g.strOrNull("started_by") == me) {
            OutlinedButton(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
                confirm = Confirm("إلغاء اللعبة الجارية؟") { client.rpc("abort_game", JSONObject().put("p_game_id", gameId)) }
            }) { Text("إلغاء اللعبة (المالك)") }
        }
        reportTarget?.let { rt ->
            val reasons = listOf("cheating" to "غش", "harassment" to "إساءة", "spam" to "إزعاج",
                "offensive_name" to "اسم مسيء", "leaving_game" to "ترك اللعبة", "other" to "أخرى")
            AlertDialog(
                onDismissRequest = { reportTarget = null },
                title = { Text("بلاغ عن ${rt.name}") },
                text = {
                    Column {
                        reasons.forEach { (code, label) ->
                            TextButton(onClick = {
                                reportTarget = null
                                act {
                                    client.rpc("submit_report", JSONObject().put("p_reported_id", rt.id)
                                        .put("p_reason", code).put("p_game_id", gameId))
                                    msg = "تم إرسال البلاغ"
                                }
                            }) { Text(label) }
                        }
                    }
                },
                confirmButton = { TextButton(onClick = { reportTarget = null }) { Text("إلغاء") } }
            )
        }
        if (inProgress && iAmAlive) {
            OutlinedButton(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
                confirm = Confirm("الانسحاب من اللعبة؟ ستخرج منها نهائيًا.") {
                    client.rpc("leave_game", JSONObject().put("p_game_id", gameId))
                }
            }) { Text("انسحاب من اللعبة") }
        }
        if (inProgress) OutlinedButton(onClick = onExit, modifier = Modifier.fillMaxWidth()) { Text("خروج مؤقت (اللعبة مستمرة)") }
    }
}
