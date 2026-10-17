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
import androidx.compose.material3.TextButton
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

private data class RoomItem(val id: String, val name: String, val count: Int, val max: Int)
private data class InviteItem(val id: String, val roomId: String, val roomName: String)
private data class MemberItem(val userId: String, val role: String, val name: String, val isBot: Boolean)

private fun parseRooms(json: String): List<RoomItem> =
    JSONArray(json).objects().map {
        RoomItem(it.getString("id"), it.getString("name"), it.optInt("member_count"), it.optInt("max_players"))
    }

private fun parseMembers(json: String): List<MemberItem> =
    JSONArray(json).objects().map {
        val p = it.optJSONObject("profiles")
        val name = (p?.strOrNull("display_name") ?: "").ifBlank { p?.strOrNull("username") ?: "" }
        MemberItem(it.getString("user_id"), it.getString("role"), name.ifBlank { "لاعب" }, p?.optBoolean("is_bot") == true)
    }

@Composable
fun HomeScreen(
    client: SupabaseClient, onOpenRoom: (String) -> Unit, onDebug: () -> Unit,
    onAccount: () -> Unit, onRules: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var rooms by remember { mutableStateOf(listOf<RoomItem>()) }
    var myRooms by remember { mutableStateOf(listOf<RoomItem>()) }
    var invites by remember { mutableStateOf(listOf<InviteItem>()) }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var myName by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var isPrivate by remember { mutableStateOf(false) }
    var max by remember { mutableStateOf("10") }
    var code by remember { mutableStateOf("") }

    fun act(block: suspend () -> Unit) {
        scope.launch {
            busy = true; msg = ""
            try { block() } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }
    suspend fun loadAll() {
        val uid = client.ensureSession()
        JSONArray(client.get("/rest/v1/profiles?select=display_name,username&id=eq.$uid")).optJSONObject(0)?.let {
            val dn = it.strOrNull("display_name") ?: ""
            if (myName.isBlank()) myName = dn
        }
        rooms = parseRooms(client.get(
            "/rest/v1/rooms?select=id,name,member_count,max_players&visibility=eq.public&status=eq.open&order=created_at.desc&limit=30"))
        invites = JSONArray(client.get(
            "/rest/v1/room_invites?select=id,room_id,room_name&invitee_id=eq.$uid&status=eq.pending&expires_at=gt.${java.time.Instant.now()}"
        )).objects().map { InviteItem(it.getString("id"), it.getString("room_id"), it.optString("room_name")) }
        myRooms = JSONArray(client.get(
            "/rest/v1/room_members?select=room_id,rooms(name,status,member_count,max_players)&user_id=eq.$uid&status=eq.active"
        )).objects().mapNotNull { o ->
            val r = o.optJSONObject("rooms") ?: return@mapNotNull null
            if (r.optString("status") == "closed") null
            else RoomItem(o.getString("room_id"), r.optString("name"), r.optInt("member_count"), r.optInt("max_players"))
        }
    }
    fun refresh() = act { loadAll() }
    LaunchedEffect(Unit) { if (client.isConfigured) refresh() }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("المافيا", style = MaterialTheme.typography.titleLarge)
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("اسمك في اللعبة", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(myName, { myName = it.take(30) }, label = { Text("الاسم المعروض") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                Button(enabled = !busy && myName.trim().length >= 2, modifier = Modifier.fillMaxWidth(), onClick = {
                    act { client.rpc("set_display_name", JSONObject().put("p_name", myName.trim())); msg = "تم حفظ الاسم" }
                }) { Text("حفظ الاسم") }
            }
        }

        if (invites.isNotEmpty()) {
            Text("دعوات إليك", style = MaterialTheme.typography.titleMedium)
            invites.forEach { inv ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("دعوة للانضمام إلى: ${inv.roomName}")
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(enabled = !busy, onClick = {
                                act {
                                    client.rpc("respond_invite", JSONObject().put("p_invite_id", inv.id).put("p_accept", true))
                                    onOpenRoom(inv.roomId)
                                }
                            }) { Text("قبول") }
                            OutlinedButton(enabled = !busy, onClick = {
                                act {
                                    client.rpc("respond_invite", JSONObject().put("p_invite_id", inv.id).put("p_accept", false))
                                    loadAll()
                                }
                            }) { Text("رفض") }
                        }
                    }
                }
            }
        }

        if (myRooms.isNotEmpty()) {
            Text("غرفك الحالية", style = MaterialTheme.typography.titleMedium)
            myRooms.forEach { r ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically) {
                        Column { Text(r.name, style = MaterialTheme.typography.titleSmall); Text("${r.count}/${r.max} لاعبين") }
                        Button(onClick = { onOpenRoom(r.id) }) { Text("فتح") }
                    }
                }
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("إنشاء غرفة", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(name, { name = it }, label = { Text("اسم الغرفة") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(max, { max = it.filter(Char::isDigit).take(2) }, label = { Text("الحد الأقصى للاعبين (4-20)") },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Switch(isPrivate, { isPrivate = it }); Text("غرفة خاصة (برمز دعوة)")
                }
                Button(enabled = !busy && client.isConfigured, modifier = Modifier.fillMaxWidth(), onClick = {
                    act {
                        val r = JSONObject(client.rpc("create_room", JSONObject()
                            .put("p_name", name.trim())
                            .put("p_visibility", if (isPrivate) "private" else "public")
                            .put("p_max_players", max.toIntOrNull() ?: 10)))
                        onOpenRoom(r.getString("id"))
                    }
                }) { Text("إنشاء") }
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("الانضمام برمز دعوة", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(code, { code = it.uppercase().take(12) }, label = { Text("الرمز") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                Button(enabled = !busy && code.isNotBlank(), modifier = Modifier.fillMaxWidth(), onClick = {
                    act {
                        val r = JSONObject(client.rpc("join_room", JSONObject().put("p_invite_code", code.trim())))
                        onOpenRoom(r.getString("id"))
                    }
                }) { Text("انضمام") }
            }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("الغرف العامة المفتوحة", style = MaterialTheme.typography.titleMedium)
            OutlinedButton(enabled = !busy && client.isConfigured, onClick = { refresh() }) { Text("تحديث") }
        }
        if (rooms.isEmpty()) Text("لا توجد غرف عامة الآن.")
        rooms.forEach { r ->
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.padding(12.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Column { Text(r.name, style = MaterialTheme.typography.titleSmall); Text("${r.count}/${r.max} لاعبين") }
                    Button(enabled = !busy && r.count < r.max, onClick = {
                        act {
                            val j = JSONObject(client.rpc("join_room", JSONObject().put("p_room_id", r.id)))
                            onOpenRoom(j.getString("id"))
                        }
                    }) { Text("دخول") }
                }
            }
        }
        OutlinedButton(onClick = onAccount, modifier = Modifier.fillMaxWidth()) { Text("حسابي (حماية الحساب بالبريد)") }
        OutlinedButton(onClick = onRules, modifier = Modifier.fillMaxWidth()) { Text("القواعد والأدوار") }
        OutlinedButton(onClick = onDebug, modifier = Modifier.fillMaxWidth()) { Text("اختبار الاتصال") }
    }
}

@Composable
fun LobbyScreen(client: SupabaseClient, roomId: String, onBack: () -> Unit, onGame: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    var room by remember { mutableStateOf<JSONObject?>(null) }
    var members by remember { mutableStateOf(listOf<MemberItem>()) }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var fast by remember { mutableStateOf(false) }
    var silencer by remember { mutableStateOf(false) }
    var speech by remember { mutableStateOf("120") }
    var inviteName by remember { mutableStateOf("") }
    var voice by remember { mutableStateOf("") }
    var botCount by remember { mutableStateOf("3") }
    var reload by remember { mutableStateOf(0) }
    val me = client.currentUserId()

    fun act(block: suspend () -> Unit) {
        scope.launch {
            busy = true; msg = ""
            try { block(); reload++ } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }

    // تحديث دوري كل 3 ثوانٍ؛ وإذا بدأت لعبة في الغرفة ينتقل الجميع إليها تلقائيًا
    LaunchedEffect(roomId, reload) {
        while (true) {
            try {
                val g = JSONArray(client.get(
                    "/rest/v1/games?select=id&room_id=eq.$roomId&status=eq.in_progress&limit=1")).optJSONObject(0)
                if (g != null) { onGame(g.getString("id")); return@LaunchedEffect }
                room = JSONArray(client.get("/rest/v1/rooms?select=*&id=eq.$roomId")).optJSONObject(0)
                members = parseMembers(client.get(
                    "/rest/v1/room_members?select=user_id,role,profiles(username,display_name,is_bot)&room_id=eq.$roomId&status=eq.active&order=joined_at.asc"))
                msg = ""
            } catch (e: Exception) { msg = friendlyError(e) }
            delay(3000)
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val r = room
        val myRole = members.firstOrNull { it.userId == me }?.role
        val isOwner = myRole == "owner"
        val isManager = myRole == "owner" || myRole == "moderator"

        Text(r?.optString("name") ?: "...", style = MaterialTheme.typography.titleLarge)
        if (r != null) {
            Text("${members.size}/${r.optInt("max_players")} لاعبين")
            val code = r.optString("invite_code")
            if (r.optString("visibility") == "private" && code.isNotBlank() && code != "null") {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) { Text("رمز الدعوة"); Text(code, style = MaterialTheme.typography.headlineSmall) }
                }
            }
            val vl = r.strOrNull("voice_link")
            if (vl != null) Text("🎙️ غرفة صوتية: $vl")
        }
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)

        Text("اللاعبون", style = MaterialTheme.typography.titleMedium)
        members.forEach { m ->
            val role = when (m.role) { "owner" -> " (مالك)"; "moderator" -> " (مشرف)"; else -> "" }
            val you = if (m.userId == me) " — أنت" else ""
            val bot = if (m.isBot) " 🤖" else ""
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(m.name + bot + role + you, Modifier.padding(vertical = 12.dp))
                    Row {
                        if (isOwner && m.role != "owner" && !m.isBot) {
                            TextButton(enabled = !busy, onClick = {
                                act {
                                    client.rpc("set_member_role", JSONObject().put("p_room_id", roomId).put("p_user_id", m.userId)
                                        .put("p_role", if (m.role == "moderator") "member" else "moderator"))
                                }
                            }) { Text(if (m.role == "moderator") "إلغاء الإشراف" else "ترقية") }
                        }
                        if (isManager && m.userId != me && m.role != "owner" && (isOwner || m.role == "member")) {
                            TextButton(enabled = !busy, onClick = {
                                act { client.rpc("kick_member", JSONObject().put("p_room_id", roomId).put("p_user_id", m.userId)) }
                            }) { Text("طرد") }
                        }
                    }
                }
            }
        }

        if (isManager) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("دعوة لاعب باسم المستخدم", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(inviteName, { inviteName = it.trim().take(20) }, label = { Text("اسم المستخدم (username)") },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy && inviteName.length >= 3, modifier = Modifier.fillMaxWidth(), onClick = {
                        act {
                            val enc = java.net.URLEncoder.encode(inviteName, "UTF-8")
                            val u = JSONArray(client.get("/rest/v1/profiles?select=id&username=eq.$enc")).optJSONObject(0)
                                ?: throw Exception("لا يوجد لاعب بهذا الاسم")
                            client.rpc("invite_player", JSONObject().put("p_room_id", roomId).put("p_invitee_id", u.getString("id")))
                            msg = "أُرسلت الدعوة"
                            inviteName = ""
                        }
                    }) { Text("إرسال الدعوة") }
                }
            }
        }

        if (isOwner) {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("رابط الغرفة الصوتية (اختياري)", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(voice, { voice = it.trim().take(300) }, label = { Text("https://...") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth())
                    Button(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
                        act {
                            client.rpc("set_room_voice_link", JSONObject().put("p_room_id", roomId)
                                .put("p_link", if (voice.isBlank()) JSONObject.NULL else voice))
                            msg = if (voice.isBlank()) "أُزيل الرابط" else "تم حفظ الرابط"
                        }
                    }) { Text("حفظ الرابط") }
                }
            }
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("🤖 لاعبون وهميون للتجربة", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(botCount, { botCount = it.filter(Char::isDigit).take(2) }, label = { Text("العدد") },
                        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(enabled = !busy && (botCount.toIntOrNull() ?: 0) > 0, onClick = {
                            act { client.rpc("add_bots", JSONObject().put("p_room_id", roomId).put("p_count", botCount.toIntOrNull() ?: 1)) }
                        }) { Text("إضافة") }
                        OutlinedButton(enabled = !busy, onClick = {
                            act { client.rpc("remove_bots", JSONObject().put("p_room_id", roomId)) }
                        }) { Text("إزالة كل البوتات") }
                    }
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Switch(fast, { fast = it }); Text("جولات سريعة للتجربة (20 ثانية لكل مرحلة)")
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Switch(silencer, { silencer = it }); Text("تفعيل مافيا الإسكات (من 6 لاعبين)")
            }
            if (!fast) {
                OutlinedTextField(speech, { speech = it.filter(Char::isDigit).take(3) },
                    label = { Text("مدة دور الكلام لكل لاعب بالثواني (20-300)") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
            }
            Button(enabled = !busy && members.size >= 4, modifier = Modifier.fillMaxWidth(), onClick = {
                scope.launch {
                    busy = true; msg = ""
                    try {
                        val body = client.rpc("start_game", JSONObject().put("p_room_id", roomId)
                            .put("p_night_seconds", if (fast) 20 else 60)
                            .put("p_speech_seconds", if (fast) 20 else (speech.toIntOrNull() ?: 120).coerceIn(20, 300))
                            .put("p_vote_seconds", if (fast) 20 else 60)
                            .put("p_silencer_enabled", silencer))
                        onGame(body.trim().trim('"'))
                    } catch (e: Exception) { msg = friendlyError(e) }
                    busy = false
                }
            }) { Text(if (members.size >= 4) "ابدأ اللعبة" else "يلزم 4 لاعبين على الأقل") }
        } else {
            Text("بانتظار مالك الغرفة ليبدأ اللعبة...")
        }

        OutlinedButton(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
            scope.launch {
                busy = true
                try { client.rpc("leave_room", JSONObject().put("p_room_id", roomId)); onBack() }
                catch (e: Exception) { msg = friendlyError(e) }
                busy = false
            }
        }) { Text("مغادرة الغرفة") }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع (بدون مغادرة)") }
    }
}
