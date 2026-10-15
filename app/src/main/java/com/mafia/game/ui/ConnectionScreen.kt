package com.mafia.game.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import kotlinx.coroutines.launch

@Composable
fun ConnectionScreen(client: SupabaseClient, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var log by remember {
        mutableStateOf(if (client.isConfigured) "جاهز." else "المفاتيح غير مضبوطة: راجع supabase.properties")
    }
    var busy by remember { mutableStateOf(false) }

    fun run(label: String, block: suspend () -> String) {
        scope.launch {
            busy = true
            log = try { "$label ✓\n" + block() } catch (e: Exception) { "$label ✗\n${e.message}" }
            busy = false
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("اختبار الاتصال بـ Supabase", style = MaterialTheme.typography.titleLarge)
        Button(onClick = { run("ping") { client.ping() } }, enabled = !busy && client.isConfigured,
            modifier = Modifier.fillMaxWidth()) { Text("1) ping") }
        Button(onClick = { run("دخول مجهول") { "user_id = " + client.ensureSession() } },
            enabled = !busy && client.isConfigured, modifier = Modifier.fillMaxWidth()) { Text("2) دخول مجهول") }
        Button(onClick = { run("الملف الشخصي") { client.myProfile() } },
            enabled = !busy && client.isConfigured, modifier = Modifier.fillMaxWidth()) { Text("3) ملفي الشخصي") }
        OutlinedButton(onClick = { client.signOutLocal(); log = "تم مسح الجلسة المحلية." },
            enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("مسح الجلسة المحلية") }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
        Text(log)
    }
}
