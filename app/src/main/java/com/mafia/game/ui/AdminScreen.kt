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

private data class ReportRow(
    val id: String, val reason: String, val details: String, val status: String,
    val reporter: String, val reported: String, val createdAt: String
)

private fun reasonAr(code: String) = when (code) {
    "cheating" -> "غش"; "harassment" -> "إساءة"; "spam" -> "إزعاج"
    "offensive_name" -> "اسم مسيء"; "leaving_game" -> "ترك اللعبة"; else -> "أخرى"
}

@Composable
fun AdminScreen(client: SupabaseClient, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var filter by remember { mutableStateOf("open") }
    var rows by remember { mutableStateOf(listOf<ReportRow>()) }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var reload by remember { mutableStateOf(0) }

    LaunchedEffect(filter, reload) {
        try {
            rows = JSONArray(client.rpc("admin_list_reports", JSONObject().put("p_status", filter))).objects().map {
                ReportRow(it.getString("rp_id"), it.optString("rp_reason"), it.optString("rp_details"),
                    it.optString("rp_status"), it.optString("rp_reporter"), it.optString("rp_reported"),
                    it.optString("rp_created_at").take(16).replace('T', ' '))
            }
            msg = ""
        } catch (e: Exception) { msg = friendlyError(e) }
    }

    fun setStatus(id: String, status: String) {
        scope.launch {
            busy = true
            try {
                client.rpc("admin_set_report_status", JSONObject().put("p_id", id).put("p_status", status))
                reload++
            } catch (e: Exception) { msg = friendlyError(e) }
            busy = false
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("🛡️ البلاغات", style = MaterialTheme.typography.titleLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("open" to "مفتوحة", "reviewing" to "قيد المراجعة", "resolved" to "محلولة", "all" to "الكل").forEach { (k, label) ->
                if (filter == k) Button(onClick = { filter = k }) { Text(label) }
                else OutlinedButton(onClick = { filter = k }) { Text(label) }
            }
        }
        if (msg.isNotBlank()) Text(msg, color = MaterialTheme.colorScheme.error)
        if (rows.isEmpty() && msg.isBlank()) Text("لا توجد بلاغات.")
        rows.forEach { r ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${r.reporter} ← ${r.reported}", style = MaterialTheme.typography.titleSmall)
                    Text("السبب: ${reasonAr(r.reason)}   |   الحالة: ${r.status}   |   ${r.createdAt}")
                    if (r.details.isNotBlank()) Text(r.details)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedButton(enabled = !busy, onClick = { setStatus(r.id, "reviewing") }) { Text("مراجعة") }
                        Button(enabled = !busy, onClick = { setStatus(r.id, "resolved") }) { Text("تم الحل") }
                        OutlinedButton(enabled = !busy, onClick = { setStatus(r.id, "dismissed") }) { Text("رفض") }
                    }
                }
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}
