package com.mafia.game.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private data class BoardRow(val name: String, val games: Int, val wins: Int, val mafiaWins: Int, val isMe: Boolean)

@Composable
fun StatsScreen(client: SupabaseClient, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var my by remember { mutableStateOf<JSONObject?>(null) }
    var board by remember { mutableStateOf(listOf<BoardRow>()) }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }
    val avatars = listOf("🦊", "🐺", "🐱", "🦁", "🐼", "🦅", "🐉", "🕵️", "👳", "🧕", "😎", "🤠")

    LaunchedEffect(reload) {
        try {
            val uid = client.ensureSession()
            my = JSONArray(client.get("/rest/v1/player_stats?select=*&user_id=eq.$uid")).optJSONObject(0)
            board = JSONArray(client.get(
                "/rest/v1/player_stats?select=user_id,games_played,wins,mafia_wins,profiles(username,display_name,avatar)&order=wins.desc,games_played.asc&limit=20"
            )).objects().map { o ->
                val p = o.optJSONObject("profiles")
                val nm = (p?.strOrNull("display_name") ?: "").ifBlank { p?.strOrNull("username") ?: "لاعب" }
                val av = p?.strOrNull("avatar")
                BoardRow(if (av != null) "$av $nm" else nm, o.optInt("games_played"), o.optInt("wins"),
                    o.optInt("mafia_wins"), o.getString("user_id") == uid)
            }
        } catch (e: Exception) { msg = friendlyError(e) }
    }

    fun pick(avatar: String?) {
        scope.launch {
            busy = true; msg = ""
            try {
                client.rpc("set_avatar", JSONObject().put("p_avatar", avatar ?: JSONObject.NULL))
                msg = if (avatar == null) "أُزيلت الصورة" else "تم تعيين صورتك $avatar"
                reload++
            } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("إحصاءاتي والترتيب", style = MaterialTheme.typography.titleLarge)
        if (msg.isNotBlank()) Text(msg)

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val m = my
                if (m == null) Text("لم تلعب أي لعبة منتهية بعد.")
                else {
                    val games = m.optInt("games_played"); val wins = m.optInt("wins")
                    Text("ألعاب: $games   فوز: $wins   نسبة الفوز: ${if (games > 0) wins * 100 / games else 0}%")
                    Text("لعبت مافيا: ${m.optInt("mafia_games")}   فزت كمافيا: ${m.optInt("mafia_wins")}")
                }
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("اختر صورتك الرمزية", style = MaterialTheme.typography.titleMedium)
                avatars.chunked(6).forEach { rowItems ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        rowItems.forEach { a -> OutlinedButton(enabled = !busy, onClick = { pick(a) }) { Text(a) } }
                    }
                }
                OutlinedButton(enabled = !busy, onClick = { pick(null) }) { Text("إزالة الصورة") }
            }
        }

        Text("أفضل 20 لاعبًا (بعدد الفوز)", style = MaterialTheme.typography.titleMedium)
        if (board.isEmpty()) Text("لا توجد نتائج بعد.")
        board.forEachIndexed { i, r ->
            Card(Modifier.fillMaxWidth()) {
                Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("${i + 1}. ${r.name}" + if (r.isMe) " — أنت" else "")
                    Text("فوز ${r.wins} / ${r.games}")
                }
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}
