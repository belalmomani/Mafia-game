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

private data class RoomItem(val id: String, val name: String, val count: Int, val max: Int)
private data class MemberItem(val userId: String, val role: String, val name: String)

private fun parseRooms(json: String): List<RoomItem> =
    JSONArray(json).objects().map {
        RoomItem(it.getString("id"), it.getString("name"), it.optInt("member_count"), it.optInt("max_players"))
    }

private fun parseMembers(json: String): List<MemberItem> =
    JSONArray(json).objects().map {
        val p = it.optJSONObject("profiles")
        val name = (p?.strOrNull("display_name") ?: "").ifBlank { p?.strOrNull("username") ?: "" }
        MemberItem(it.getString("user_id"), it.getString("role"), name.ifBlank { "لاعب" })
    }

@Composable
fun HomeScreen(client: SupabaseClient, onOpenRoom: (String) -> Unit, onDebug: () -> Unit) {
    val scope = rememberCoroutineScope()
    var rooms by remember { mutableStateOf(listOf<RoomItem>()) }
    var myRooms by remember { mutableStateOf(listOf<RoomItem>()) }
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
    val me = client.currentUserId()

    // تحديث دوري كل 3 ثوانٍ؛ وإذا بدأت لعبة في الغرفة ينتقل الجميع إليها تلقائيًا
    LaunchedEffect(roomId) {
        while (true) {
            try {
                val g = JSONArray(client.get(
                    "/rest/v1/games?select=id&room_id=eq.$roomId&status=eq.in_progress&limit=1")).optJSONObject(0)
                if (g != null) { onGame(g.getString("id")); return@LaunchedEffect }
                room = JSONArray(client.get("/rest/v1/rooms?select=*&id=eq.$roomId")).optJSONObject(0)
                members = parseMembers(client.get(
                    "/rest/v1/room_members?select=user_id,role,profiles(username,display_name)&room_id=eq.$roomId&status=eq.active&order=joined_at.asc"))
                msg = ""
            } catch (e: Exception) { msg = friendlyError(e) }
            delay(3000)
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val r = room
        Text(r?.optString("name") ?: "...", style = MaterialTheme.typography.titleLarge)
        if (r != null) {
            Text("${members.size}/${r.optInt("max_players")} لاعبين")
            val code = r.optString("invite_code")
            if (r.optString("visibility") == "private" && code.isNotBlank() && code != "null") {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) { Text("رمز الدعوة"); Text(code, style = MaterialTheme.typography.headlineSmall) }
                }
            }
        }
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)
        Text("اللاعبون", style = MaterialTheme.typography.titleMedium)
        members.forEach { m ->
            val role = when (m.role) { "owner" -> " (مالك)"; "moderator" -> " (مشرف)"; else -> "" }
            val you = if (m.userId == me) " — أنت" else ""
            Card(Modifier.fillMaxWidth()) { Text(m.name + role + you, Modifier.padding(12.dp)) }
        }

        val isOwner = r != null && r.optString("owner_id") == me
        if (isOwner) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Switch(fast, { fast = it }); Text("جولات سريعة للتجربة (20 ثانية)")
            }
            Button(enabled = !busy && members.size >= 4, modifier = Modifier.fillMaxWidth(), onClick = {
                scope.launch {
                    busy = true; msg = ""
                    try {
                        val body = client.rpc("start_game", JSONObject().put("p_room_id", roomId)
                            .put("p_night_seconds", if (fast) 20 else 60)
                            .put("p_day_seconds", if (fast) 20 else 120)
                            .put("p_vote_seconds", if (fast) 20 else 60))
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
