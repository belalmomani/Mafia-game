package com.mafia.game.ui

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
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
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
private data class Snap(
    val game: JSONObject, val players: List<Player>, val my: MyRole?,
    val events: List<Ev>, val votes: List<VoteRow>
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
    return Snap(game, players, my, events, votes)
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
            else -> ""
        }
        "مات $n$role$cause"
    }
}

private fun eventLines(e: Ev, names: Map<String, String>): List<String> = when (e.type) {
    "game_started" -> listOf("بدأت اللعبة بـ ${e.payload.optInt("players")} لاعبين")
    "night_result" -> deathsText(e.payload.optJSONArray("deaths"), names)
        .ifEmpty { listOf("مرّت الليلة بسلام ولم يمت أحد") }
    "day_started" -> listOf("طلع النهار، ناقشوا")
    "voting_started" -> listOf("بدأ التصويت")
    "player_eliminated" -> deathsText(e.payload.optJSONArray("deaths"), names)
    "no_elimination" -> listOf(if (e.payload.optBoolean("tie")) "تعادلت الأصوات ولم يُقصَ أحد" else "لم يصوّت أحد")
    "hunter_shot" -> listOf("الصياد ${names[e.payload.optString("hunter_id")] ?: ""} أطلق النار") +
        deathsText(e.payload.optJSONArray("deaths"), names)
    "night_started" -> listOf("بدأت الليلة ${e.round}")
    "game_ended" -> listOf(if (e.payload.optString("winner") == "citizens") "انتهت اللعبة: فاز المواطنون" else "انتهت اللعبة: فازت المافيا")
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
    val me = client.currentUserId()

    LaunchedEffect(gameId) {
        while (true) {
            try {
                val st = snap?.game?.optString("status")
                if (st == null || st == "in_progress") {
                    runCatching { client.rpc("advance_phase", JSONObject().put("p_game_id", gameId)) }
                }
                snap = loadSnap(client, gameId)
            } catch (e: Exception) { msg = friendlyError(e) }
            delay(2500)
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
        val phaseAr = when (phase) { "night" -> "الليل"; "day" -> "النهار"; "voting" -> "التصويت"; else -> "انتهت" }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text("$phaseAr — الجولة $round", style = MaterialTheme.typography.titleLarge)
                if (inProgress) Text("الوقت المتبقي: $left ثانية")
            }
            if (my != null) OutlinedButton(onClick = { showRole = true }) { Text("دوري") }
        }
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)

        if (showRole && my != null) {
            AlertDialog(
                onDismissRequest = { showRole = false },
                confirmButton = { Button(onClick = { showRole = false }) { Text("حسنًا") } },
                title = { Text("دورك: ${Roles.nameAr(my.role)}") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Image(painterResource(Roles.cardRes(my.role)), contentDescription = Roles.nameAr(my.role),
                            modifier = Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth)
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
                            if (my.role == "red_mafia") "اختر ضحية الليلة (قرارك نهائي)" else "اقترح ضحية للفريق (قرار الأحمر نهائي)",
                            cands, busy, onPick = { night("kill", it.id) }, skipLabel = "تخطّي", onSkip = { night("skip", null) })
                        val sug = s.events.filter { it.type == "mafia_suggestion" && it.round == roundNow }
                            .groupBy { it.payload.optString("actor_id") }.mapValues { it.value.last() }
                        if (sug.isNotEmpty()) Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text("اقتراحات الفريق", style = MaterialTheme.typography.titleMedium)
                                sug.forEach { (a, e) ->
                                    val t = e.payload.strOrNull("target_id")
                                    Text("${names[a] ?: "لاعب"} ← " + (if (t == null) "تخطّي" else (names[t] ?: "")))
                                }
                            }
                        }
                    }
                    "girl" -> PickPanel("من تحميه من الاغتيال الليلة؟", alive.filter { it.id != my.lastProtected },
                        busy, onPick = { night("protect", it.id) }, skipLabel = "تخطّي", onSkip = { night("skip", null) })
                    "sheikh" -> PickPanel("من تفجّر الليلة؟ (يموت فورًا ولا تمنعه الحماية)", alive.filter { it.id != me },
                        busy, onPick = { p -> confirm = Confirm("تفجير ${p.name}؟") { night("bomb", p.id) } },
                        skipLabel = "لا أفجّر أحدًا", onSkip = { night("skip", null) })
                    else -> Card(Modifier.fillMaxWidth()) { Text("الليل... لا قدرة لديك الآن. انتظر الصباح.", Modifier.padding(12.dp)) }
                }
                if (sentNote.isNotBlank()) Text(sentNote)
            }

            // النهار: الصياد
            if (phase == "day") {
                Card(Modifier.fillMaxWidth()) { Text("النهار: ناقشوا وتبادلوا الشكوك. سيبدأ التصويت عند انتهاء الوقت.", Modifier.padding(12.dp)) }
                if (my.role == "hunter" && my.bullets > 0) {
                    PickPanel("الصياد: أطلق طلقتك الوحيدة (يموت الهدف دائمًا)", alive.filter { it.id != me }, busy,
                        onPick = { p -> confirm = Confirm("إطلاق النار على ${p.name}؟ لا رجعة فيه.") {
                            client.rpc("hunter_shoot", JSONObject().put("p_game_id", gameId).put("p_target_id", p.id)) } })
                }
            }

            // التصويت
            if (phase == "voting") {
                val voted = s.votes.any { it.round == roundNow && it.voter == me }
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

        // ---------- اللاعبون ----------
        Text("اللاعبون", style = MaterialTheme.typography.titleMedium)
        s.players.forEach { p ->
            val tag = buildString {
                if (p.id == me) append(" — أنت")
                if (my != null && p.id in my.teammates) append(" — مافيا")
                if (!p.alive) append(" — ميت" + (p.role?.let { " (${Roles.nameAr(it)})" } ?: ""))
            }
            Card(Modifier.fillMaxWidth()) { Text("${p.seat}. ${p.name}$tag", Modifier.padding(10.dp)) }
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
        if (inProgress) OutlinedButton(onClick = onExit, modifier = Modifier.fillMaxWidth()) { Text("خروج مؤقت (اللعبة مستمرة)") }
    }
}
