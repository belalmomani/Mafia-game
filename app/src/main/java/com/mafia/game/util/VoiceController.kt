package com.mafia.game.util

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mafia.game.data.SupabaseClient
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import org.json.JSONObject

/** إدارة اتصال الصوت (LiveKit). الصلاحيات تحددها دالة الخادم voice-token، وليس التطبيق. */
class VoiceController(private val ctx: Context, private val client: SupabaseClient) {
    private var room: Room? = null
    var joined by mutableStateOf(false)
    var canPublish by mutableStateOf(false)
    var micOn by mutableStateOf(false)
    var label by mutableStateOf("")
    var error by mutableStateOf("")

    /** يطلب تصريحًا جديدًا ويتصل (يُستدعى أيضًا عند تغيّر الدور أو المرحلة لتحديث الصلاحيات). */
    suspend fun join(gameId: String) {
        leave()
        val j = JSONObject(client.callFunction("voice-token", JSONObject().put("game_id", gameId)))
        val r = LiveKit.create(ctx.applicationContext)
        r.connect(j.getString("url"), j.getString("token"))
        room = r
        canPublish = j.optBoolean("can_publish")
        label = if (j.optBoolean("mafia")) "قناة المافيا السرية" else "الغرفة العامة"
        if (canPublish) {
            r.localParticipant.setMicrophoneEnabled(true)
            micOn = true
        } else {
            micOn = false
        }
        joined = true
        error = ""
    }

    suspend fun setMic(on: Boolean) {
        val allowed = on && canPublish
        room?.localParticipant?.setMicrophoneEnabled(allowed)
        micOn = allowed
    }

    fun leave() {
        runCatching { room?.disconnect() }
        room = null
        joined = false
        micOn = false
    }
}
