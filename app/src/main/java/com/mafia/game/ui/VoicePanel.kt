package com.mafia.game.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.mafia.game.data.SupabaseClient
import com.mafia.game.util.VoiceController
import kotlinx.coroutines.launch

/**
 * الصوت داخل اللعبة. المتحدث وحده يملك الميكروفون نهارًا، والمافيا ليلًا في قناتهم.
 * يتجدد التصريح تلقائيًا عند تغيّر المرحلة أو المتحدث.
 */
@Composable
fun VoicePanel(client: SupabaseClient, gameId: String, stateKey: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val vc = remember { VoiceController(ctx, client) }

    DisposableEffect(Unit) { onDispose { vc.leave() } }

    fun join() {
        scope.launch {
            try { vc.join(gameId) } catch (e: Exception) { vc.leave(); vc.error = friendlyError(e) }
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) join() else vc.error = "يلزم السماح باستخدام الميكروفون للمشاركة"
    }

    // تغيّر المرحلة أو المتحدث: نجدد التصريح كي تتبدّل صلاحية الميكروفون
    LaunchedEffect(stateKey) {
        if (vc.joined) {
            try { vc.join(gameId) } catch (e: Exception) { vc.leave(); vc.error = friendlyError(e) }
        }
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("🎤 الصوت", style = MaterialTheme.typography.titleMedium)
            if (!vc.joined) {
                Button(modifier = Modifier.fillMaxWidth(), onClick = {
                    val ok = ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                    if (ok) join() else permission.launch(Manifest.permission.RECORD_AUDIO)
                }) { Text("انضم إلى الصوت") }
            } else {
                Text("متصل: ${vc.label}")
                Text(if (vc.canPublish) (if (vc.micOn) "🔊 ميكروفونك مفتوح (دورك)" else "🔇 ميكروفونك مكتوم")
                     else "🎧 استماع فقط حتى يأتي دورك")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (vc.canPublish) {
                        OutlinedButton(onClick = { scope.launch { runCatching { vc.setMic(!vc.micOn) } } }) {
                            Text(if (vc.micOn) "كتم" else "فتح الميكروفون")
                        }
                    }
                    OutlinedButton(onClick = { vc.leave() }) { Text("مغادرة الصوت") }
                }
            }
            if (vc.error.isNotBlank()) Text(vc.error, color = MaterialTheme.colorScheme.error)
        }
    }
}
