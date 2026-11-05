package com.mafia.game.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import com.mafia.game.util.PushRegistrar
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private data class RoomItem(val id: String, val name: String, val count: Int, val max: Int, val isOwner: Boolean = false)
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
        val av = p?.strOrNull("avatar")
        val shown = name.ifBlank { "لاعب" }
        MemberItem(it.getString("user_id"), it.getString("role"), if (av != null) "$av $shown" else shown, p?.optBoolean("is_bot") == true)
    }

@Composable
fun HomeScreen(
    client: SupabaseClient, onOpenRoom: (String) -> Unit, onDebug: () -> Unit,
    onAccount: () -> Unit, onRules: () -> Unit, onStats: () -> Unit, onAdmin: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val appCtx = LocalContext.current.applicationContext
    var rooms by remember { mutableStateOf(listOf<RoomItem>()) }
    var myRooms by remember { mutableStateOf(listOf<RoomItem>()) }
    var invites by remember { mutableStateOf(listOf<InviteItem>()) }
    var isAdmin by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<RoomItem?>(null) }
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
        PushRegistrar.register(appCtx, client)
        JSONArray(client.get("/rest/v1/profiles?select=display_name,username&id=eq.$uid")).optJSONObject(0)?.let {
            val dn = it.strOrNull("display_name") ?: ""
            if (myName.isBlank()) myName = dn
        }
        rooms = parseRooms(client.get(
            "/rest/v1/rooms?select=id,name,member_count,max_players&visibility=eq.public&status=eq.open&order=created_at.desc&limit=30"))
        isAdmin = runCatching { client.rpc("is_admin").trim() == "true" }.getOrDefault(false)
        invites = JSONArray(client.get(
            "/rest/v1/room_invites?select=id,room_id,room_name&invitee_id=eq.$uid&status=eq.pending&expires_at=gt.${java.time.Instant.now()}"
        )).objects().map { InviteItem(it.getString("id"), it.getString("room_id"), it.optString("room_name")) }
        myRooms = JSONArray(client.get(
            "/rest/v1/room_members?select=room_id,role,rooms(name,status,member_count,max_players)&user_id=eq.$uid&status=eq.active"
        )).objects().mapNotNull { o ->
            val r = o.optJSONObject("rooms") ?: return@mapNotNull null
            if (r.optString("status") == "closed") null
            else RoomItem(o.getString("room_id"), r.optString("name"), r.optInt("member_count"), r.optInt("max_players"), o.optString("role") == "owner")
        }
    }
    fun refresh() = act { loadAll() }
    LaunchedEffect(Unit) { if (client.isConfigured) refresh() }

    val c = LocalAppColors.current
    val stepMax = (max.toIntOrNull() ?: 10).coerceIn(4, 20)

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // ----- الترويسة -----
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("🎭 المافيا", style = MaterialTheme.typography.headlineMedium, color = c.accent)
            Text("لعبة الخداع والذكاء: اجمع أصدقاءك وابدأ", style = MaterialTheme.typography.bodyMedium, color = c.muted)
        }
        if (msg.isNotBlank()) StatusBanner(msg)

        deleteTarget?.let { target ->
            AlertDialog(
                onDismissRequest = { deleteTarget = null },
                title = { Text("حذف الغرفة؟") },
                text = { Text("سيُحذف «${target.name}» وكل ما فيها نهائيًا. لا يمكن التراجع.") },
                confirmButton = {
                    TextButton(onClick = {
                        deleteTarget = null
                        act { client.rpc("delete_room", JSONObject().put("p_room_id", target.id)); msg = "تم حذف الغرفة"; loadAll() }
                    }) { Text("حذف", color = c.danger) }
                },
                dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text("إلغاء") } }
            )
        }

        // ----- الدعوات -----
        if (invites.isNotEmpty()) {
            SectionCard("دعوات إليك", icon = "💌", subtitle = "لاعبون يدعونك للانضمام") {
                invites.forEach { inv ->
                    Text("دعوة إلى: ${inv.roomName}", style = MaterialTheme.typography.bodyLarge, color = c.title)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        PrimaryButton("قبول", modifier = Modifier.weight(1f), enabled = !busy, compact = true, onClick = {
                            act {
                                client.rpc("respond_invite", JSONObject().put("p_invite_id", inv.id).put("p_accept", true))
                                onOpenRoom(inv.roomId)
                            }
                        })
                        GhostButton("رفض", modifier = Modifier.weight(1f), enabled = !busy, compact = true, onClick = {
                            act {
                                client.rpc("respond_invite", JSONObject().put("p_invite_id", inv.id).put("p_accept", false))
                                loadAll()
                            }
                        })
                    }
                }
            }
        }

        // ----- غرفك الحالية -----
        if (myRooms.isNotEmpty()) {
            SectionCard("غرفك الحالية", icon = "🚪", subtitle = "عُد إلى غرفة أنت عضو فيها") {
                myRooms.forEach { r ->
                    RoomCard(r.name, r.count, r.max, "فتح", true, allowWhenFull = true,
                        actionIcon = Icons.AutoMirrored.Filled.ArrowForward,
                        onDelete = if (r.isOwner || isAdmin) ({ deleteTarget = r }) else null) { onOpenRoom(r.id) }
                }
            }
        }

        // ----- إنشاء غرفة -----
        SectionCard("إنشاء غرفة", icon = "➕", subtitle = "عامة للجميع، أو خاصة برمز دعوة") {
            AppField(name, { name = it.take(40) }, "اسم الغرفة", leading = "🏠")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text("الحد الأقصى للاعبين", style = MaterialTheme.typography.bodyLarge, color = c.title)
                    Text("من 4 إلى 20", style = MaterialTheme.typography.bodySmall, color = c.muted)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    StepperButton("+", enabled = stepMax < 20, onClick = { max = (stepMax + 1).toString() })
                    Text(stepMax.toString(), style = MaterialTheme.typography.headlineSmall, color = c.accent)
                    StepperButton("−", enabled = stepMax > 4, onClick = { max = (stepMax - 1).toString() })
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("غرفة خاصة (برمز دعوة)", style = MaterialTheme.typography.bodyLarge, color = c.title)
                Switch(isPrivate, { isPrivate = it })
            }
            PrimaryButton("إنشاء", modifier = Modifier.fillMaxWidth(), icon = Icons.Filled.Add,
                enabled = !busy && client.isConfigured && name.trim().length >= 2, onClick = {
                act {
                    val r = JSONObject(client.rpc("create_room", JSONObject()
                        .put("p_name", name.trim())
                        .put("p_visibility", if (isPrivate) "private" else "public")
                        .put("p_max_players", max.toIntOrNull() ?: 10)))
                    onOpenRoom(r.getString("id"))
                }
            })
        }

        // ----- الانضمام برمز -----
        SectionCard("الانضمام برمز دعوة", icon = "🎟️") {
            AppField(code, { code = it.uppercase().replace(" ", "").take(12) }, "الرمز", ltr = true, center = true, leading = "🔑")
            PrimaryButton("الانضمام", modifier = Modifier.fillMaxWidth(), icon = Icons.AutoMirrored.Filled.ArrowForward,
                enabled = !busy && code.isNotBlank(), onClick = {
                act {
                    val r = JSONObject(client.rpc("join_room", JSONObject().put("p_invite_code", code.trim())))
                    onOpenRoom(r.getString("id"))
                }
            })
        }

        // ----- الغرف العامة المفتوحة (عنوان + تحديث، ثم بطاقات) -----
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("👥", fontSize = 22.sp)
                Text("الغرف العامة المفتوحة", style = MaterialTheme.typography.titleMedium, color = c.title)
            }
            GhostButton("تحديث", { refresh() }, enabled = !busy && client.isConfigured, compact = true, icon = Icons.Filled.Refresh)
        }
        if (rooms.isEmpty()) {
            SectionCard("لا توجد غرف عامة الآن") {
                Text("أنشئ غرفتك وادعُ أصدقاءك لتبدأ اللعب.", color = c.muted, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth())
            }
        }
        rooms.forEach { r ->
            RoomCard(r.name, r.count, r.max, "دخول", !busy, actionIcon = Icons.AutoMirrored.Filled.ArrowForward,
                onDelete = if (isAdmin) ({ deleteTarget = r }) else null) {
                act {
                    val j = JSONObject(client.rpc("join_room", JSONObject().put("p_room_id", r.id)))
                    onOpenRoom(j.getString("id"))
                }
            }
        }

        // ----- الاسم -----
        SectionCard("اسمك في اللعبة", icon = "👤", subtitle = "يظهر للاعبين الآخرين") {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                AppField(myName, { myName = it.take(30) }, "الاسم المعروض", Modifier.weight(1f))
                PrimaryButton("حفظ", enabled = !busy && myName.trim().length >= 2, compact = true, onClick = {
                    act { client.rpc("set_display_name", JSONObject().put("p_name", myName.trim())); msg = "تم حفظ الاسم" }
                })
            }
        }

        // ----- اختصارات -----
        val quick = buildList<Pair<String, () -> Unit>> {
            add("📊 إحصاءاتي" to onStats)
            add("👤 حسابي" to onAccount)
            add("📖 القواعد" to onRules)
            if (isAdmin) add("🛡️ الإدارة" to onAdmin)
            add("🔌 اختبار الاتصال" to onDebug)
        }
        quick.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { (label, action) -> GhostButton(label, action, Modifier.weight(1f), compact = true) }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
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
    var confirmDelete by remember { mutableStateOf(false) }
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
                    "/rest/v1/room_members?select=user_id,role,profiles(username,display_name,is_bot,avatar)&room_id=eq.$roomId&status=eq.active&order=joined_at.asc"))
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
        if (isOwner) {
            GhostButton("🗑️ حذف الغرفة", { confirmDelete = true }, modifier = Modifier.fillMaxWidth(), enabled = !busy)
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text("حذف الغرفة؟") },
                text = { Text("سيُحذف «${room?.optString("name") ?: ""}» وكل ما فيها نهائيًا. لا يمكن التراجع، ولا يجوز أثناء لعبة جارية.") },
                confirmButton = {
                    TextButton(onClick = {
                        confirmDelete = false
                        scope.launch {
                            busy = true; msg = ""
                            try { client.rpc("delete_room", JSONObject().put("p_room_id", roomId)); onBack() }
                            catch (e: Exception) { msg = friendlyError(e) }
                            busy = false
                        }
                    }) { Text("حذف", color = MaterialTheme.colorScheme.error) }
                },
                dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("إلغاء") } }
            )
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع (بدون مغادرة)") }
    }
}
