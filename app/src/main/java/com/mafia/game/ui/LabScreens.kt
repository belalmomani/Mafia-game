package com.mafia.game.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.time.OffsetDateTime

private data class LabPlayer(
    val id: String, val name: String, val seat: Int, val alive: Boolean, val role: String,
    val bullets: Int, val lastProtected: String?
)

/** مختبر التجربة: إنشاء لعبة بلاعبين وهميين يتحكم بهم المشرف، أو فتح لعبة سابقة. */
@Composable
fun LabHomeScreen(client: SupabaseClient, onOpen: (String) -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var players by remember { mutableStateOf("4") }
    var fast by remember { mutableStateOf(true) }
    var silencer by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var items by remember { mutableStateOf(listOf<JSONObject>()) }
    var reload by remember { mutableStateOf(0) }

    LaunchedEffect(reload) {
        try { items = JSONArray(client.rpc("lab_list")).objects() } catch (e: Exception) { msg = friendlyError(e) }
    }

    fun act(block: suspend () -> Unit) {
        scope.launch {
            busy = true; msg = ""
            try { block() } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("🧪 مختبر التجربة", style = MaterialTheme.typography.titleLarge)
        Text("تنشئ لعبة بلاعبين وهميين تتحكم بهم كلهم وترى أدوارهم وإجراءاتهم. لا تؤثر على الألعاب الحقيقية.")
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(players, { players = it.filter(Char::isDigit).take(2) }, label = { Text("عدد اللاعبين (4-20)") },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Switch(fast, { fast = it }); Text("مؤقتات قصيرة (20 ثانية)")
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Switch(silencer, { silencer = it }); Text("مافيا الإسكات")
                }
                Button(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
                    act {
                        val id = client.rpc("lab_start", JSONObject()
                            .put("p_players", (players.toIntOrNull() ?: 4).coerceIn(4, 20))
                            .put("p_silencer", silencer)
                            .put("p_speech_seconds", if (fast) 20 else 120)
                            .put("p_night_seconds", if (fast) 20 else 60)
                            .put("p_vote_seconds", if (fast) 20 else 60)).trim().trim('"')
                        onOpen(id)
                    }
                }) { Text("ابدأ لعبة تجريبية") }
            }
        }

        Text("ألعابك التجريبية", style = MaterialTheme.typography.titleMedium)
        if (items.isEmpty()) Text("لا توجد.")
        items.forEach { it0 ->
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("${it0.optString("phase")} — الجولة ${it0.optInt("round")} (${it0.optString("status")})")
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Button(onClick = { onOpen(it0.getString("game_id")) }) { Text("فتح") }
                        OutlinedButton(enabled = !busy, onClick = {
                            act { client.rpc("lab_remove", JSONObject().put("p_room_id", it0.getString("room_id"))); reload++ }
                        }) { Text("حذف") }
                    }
                }
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}

@Composable
fun LabGameScreen(client: SupabaseClient, gameId: String, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf<JSONObject?>(null) }
    var actor by remember { mutableStateOf<String?>(null) }
    var text by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }
    var nowMs by remember { mutableStateOf(System.currentTimeMillis()) }

    LaunchedEffect(gameId, reload) {
        while (true) {
            try { state = JSONObject(client.rpc("lab_state", JSONObject().put("p_game_id", gameId))) }
            catch (e: Exception) { msg = friendlyError(e) }
            delay(2000)
        }
    }
    LaunchedEffect(Unit) { while (true) { nowMs = System.currentTimeMillis(); delay(1000) } }

    fun run(block: suspend () -> Unit) {
        scope.launch {
            busy = true; msg = ""
            try { block(); reload++ } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }
    fun doAct(action: String, target: String? = null, say: String? = null, channel: String = "public") {
        val a = actor ?: return
        run {
            val b = JSONObject().put("p_game_id", gameId).put("p_actor", a).put("p_action", action).put("p_channel", channel)
            if (target != null) b.put("p_target", target)
            if (say != null) b.put("p_text", say)
            client.rpc("lab_act", b)
        }
    }

    val s = state
    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("🧪 مختبر التجربة — عرض المشرف", style = MaterialTheme.typography.titleLarge)
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)
        if (s == null) {
            Text("جارٍ التحميل...")
            OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
            return@Column
        }

        val g = s.getJSONObject("game")
        val phase = g.optString("phase")
        val status = g.optString("status")
        val round = g.optInt("round_no")
        val inProgress = status == "in_progress"
        val ps = s.getJSONArray("players").objects().map {
            LabPlayer(it.getString("user_id"), it.optString("name"), it.optInt("seat"), it.optBoolean("alive"),
                it.optString("role"), it.optInt("bullets"), it.strOrNull("last_protected"))
        }
        val names = ps.associate { it.id to it.name }
        val alive = ps.filter { it.alive }
        val order = g.optJSONArray("speech_order")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
        val speaker = order.getOrNull(g.optInt("speech_idx"))
        val pendingPull = g.strOrNull("pending_pull")
        val endsMs = g.strOrNull("phase_ends_at")?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() }
        val left = if (endsMs != null) ((endsMs - nowMs) / 1000).coerceAtLeast(0L) else 0L
        val phaseAr = when (phase) { "night" -> "الليل"; "day" -> "التبرير"; "voting" -> "التصويت"; else -> "انتهت" }

        Text("$phaseAr — الجولة $round — " + (if (inProgress) "المتبقي $left ث" else "الحالة: $status"),
            style = MaterialTheme.typography.titleMedium)
        if (!inProgress) {
            Text(when (g.strOrNull("winner")) { "citizens" -> "فاز المواطنون"; "mafia" -> "فازت المافيا"; else -> "انتهت اللعبة" },
                style = MaterialTheme.typography.titleLarge)
        }
        g.strOrNull("silenced_id")?.let { Text("🔇 مُسكَت اليوم: ${names[it] ?: ""}") }
        if (pendingPull != null) Text("⏳ الولد (${names[pendingPull] ?: ""}) يختار من يسحبه")

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Button(enabled = !busy && inProgress, onClick = {
                run { client.rpc("lab_advance", JSONObject().put("p_game_id", gameId).put("p_force", true)) }
            }) { Text("⏩ التالي الآن") }
            OutlinedButton(enabled = !busy && inProgress, onClick = {
                run { client.rpc("lab_autofill", JSONObject().put("p_game_id", gameId)) }
            }) { Text("🎲 عشوائي للباقين") }
        }
        OutlinedButton(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
            run { client.rpc("lab_remove", JSONObject().put("p_room_id", g.getString("room_id"))); onBack() }
        }) { Text("🗑️ حذف المختبر والرجوع") }

        // ---------- اللاعبون (عرض الأدوار كاملة) ----------
        Text("اللاعبون (الأدوار ظاهرة لك)", style = MaterialTheme.typography.titleMedium)
        ps.forEach { p ->
            val tags = buildString {
                if (!p.alive) append(" — ميت")
                if (p.id == speaker && phase == "day") append(" — 🎙️ يتكلم")
                if (p.id == actor) append(" — ◀ تتحكم به")
            }
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("${p.seat}. ${p.name} — ${Roles.nameAr(p.role)}$tags")
                    if (p.id == actor) Button(onClick = { actor = p.id }) { Text("محدد") }
                    else OutlinedButton(onClick = { actor = p.id }) { Text("تحكّم") }
                }
            }
        }

        // ---------- لوحة تحكم اللاعب المحدد ----------
        val me = ps.firstOrNull { it.id == actor }
        if (me != null && inProgress) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("تتحكم بـ: ${me.name} (${Roles.nameAr(me.role)})", style = MaterialTheme.typography.titleMedium)
                    val others = alive.filter { it.id != me.id }
                    val mafiaRole = Roles.isMafia(me.role)

                    if (pendingPull == me.id) {
                        Text("اختر من يسحبه الولد:")
                        others.forEach { t -> Button(enabled = !busy, onClick = { doAct("boy_pull", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) } }
                    }

                    if (me.alive) {
                        when (phase) {
                            "night" -> {
                                when (me.role) {
                                    "mafia", "red_mafia" -> {
                                        Text("اغتيال:")
                                        alive.filter { !Roles.isMafia(it.role) }.forEach { t ->
                                            Button(enabled = !busy, onClick = { doAct("kill", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) }
                                        }
                                        OutlinedButton(enabled = !busy, onClick = { doAct("skip") }, modifier = Modifier.fillMaxWidth()) { Text("تخطّي") }
                                    }
                                    "silencer" -> {
                                        Text("إسكات:")
                                        alive.filter { !Roles.isMafia(it.role) }.forEach { t ->
                                            Button(enabled = !busy, onClick = { doAct("silence", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) }
                                        }
                                        OutlinedButton(enabled = !busy, onClick = { doAct("skip") }, modifier = Modifier.fillMaxWidth()) { Text("تخطّي") }
                                    }
                                    "girl" -> {
                                        Text("حماية:")
                                        alive.filter { it.id != me.lastProtected }.forEach { t ->
                                            Button(enabled = !busy, onClick = { doAct("protect", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) }
                                        }
                                        OutlinedButton(enabled = !busy, onClick = { doAct("skip") }, modifier = Modifier.fillMaxWidth()) { Text("تخطّي") }
                                    }
                                    "sheikh" -> {
                                        Text("تفجير:")
                                        others.forEach { t ->
                                            Button(enabled = !busy, onClick = { doAct("bomb", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) }
                                        }
                                        OutlinedButton(enabled = !busy, onClick = { doAct("skip") }, modifier = Modifier.fillMaxWidth()) { Text("تخطّي") }
                                    }
                                    else -> Text("لا قدرة ليلية لهذا الدور.")
                                }
                                if (mafiaRole) {
                                    OutlinedTextField(text, { text = it.take(300) }, label = { Text("رسالة لقناة المافيا") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedButton(enabled = !busy && text.isNotBlank(), onClick = { doAct("say", null, text.trim(), "mafia"); text = "" }) { Text("أرسل للمافيا") }
                                }
                            }
                            "day" -> {
                                if (me.id == speaker) {
                                    Button(enabled = !busy, onClick = { doAct("end_speech") }, modifier = Modifier.fillMaxWidth()) { Text("أنهِ دوره") }
                                    OutlinedTextField(text, { text = it.take(300) }, label = { Text("ما يقوله") }, modifier = Modifier.fillMaxWidth())
                                    OutlinedButton(enabled = !busy && text.isNotBlank(), onClick = { doAct("say", null, text.trim()); text = "" }) { Text("قل") }
                                } else {
                                    Text("ليس دوره في الكلام (يتكلم: ${names[speaker] ?: "-"}).")
                                }
                                if (me.role == "hunter" && me.bullets > 0) {
                                    Text("إطلاق الصياد:")
                                    others.forEach { t -> Button(enabled = !busy, onClick = { doAct("hunter", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) } }
                                }
                            }
                            "voting" -> {
                                Text("تصويت:")
                                others.forEach { t -> Button(enabled = !busy, onClick = { doAct("vote", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) } }
                                OutlinedButton(enabled = !busy, onClick = { doAct("vote") }, modifier = Modifier.fillMaxWidth()) { Text("امتناع") }
                            }
                        }
                        if (me.role == "boy") {
                            Text("هدف سحب الولد المسبق:")
                            others.forEach { t -> OutlinedButton(enabled = !busy, onClick = { doAct("boy_target", t.id) }, modifier = Modifier.fillMaxWidth()) { Text(t.name) } }
                        }
                        OutlinedButton(enabled = !busy, onClick = { doAct("leave") }, modifier = Modifier.fillMaxWidth()) { Text("انسحاب هذا اللاعب") }
                    } else Text("هذا اللاعب خارج اللعبة.")
                }
            }
        } else if (inProgress) {
            Text("اضغط «تحكّم» على أي لاعب لتنفيذ إجراءاته.")
        }

        // ---------- عرض المشرف: الإجراءات والأحداث ----------
        val na = s.getJSONArray("night_actions").objects()
        if (na.isNotEmpty()) {
            Text("إجراءات الليل الحالية", style = MaterialTheme.typography.titleMedium)
            na.forEach { Text("• ${names[it.optString("actor")] ?: ""}: ${it.optString("action")} ← ${names[it.optString("target")] ?: "-"}") }
        }
        val vs = s.getJSONArray("votes").objects()
        if (vs.isNotEmpty()) {
            Text("الأصوات الحالية", style = MaterialTheme.typography.titleMedium)
            vs.forEach { Text("• ${names[it.optString("voter")] ?: ""} ← ${names[it.optString("target")] ?: "امتناع"}") }
        }
        val msgs = s.getJSONArray("messages").objects()
        if (msgs.isNotEmpty()) {
            Text("الرسائل", style = MaterialTheme.typography.titleMedium)
            msgs.takeLast(12).forEach { Text("[${it.optString("channel")}] ${names[it.optString("user")] ?: ""}: ${it.optString("body")}") }
        }
        val evs = s.getJSONArray("events").objects()
        Text("سجل الأحداث (كل أنواعها)", style = MaterialTheme.typography.titleMedium)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(10.dp)) {
                evs.takeLast(25).reversed().forEach {
                    Text("• [${it.optString("vis")}] ${it.optString("type")} ${it.optJSONObject("payload")?.toString()?.take(110) ?: ""}",
                        style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}
