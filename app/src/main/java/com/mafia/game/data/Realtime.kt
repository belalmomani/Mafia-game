package com.mafia.game.data

import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * مراقب Realtime (Supabase / بروتوكول Phoenix) لإشعار الشاشة بأي تغيير في اللعبة فورًا.
 * فشله لا يعطّل شيئًا: الشاشة تبقى تستطلع كل 3 ثوانٍ كاحتياط.
 */
class RealtimeWatcher(
    private val client: SupabaseClient,
    private val gameId: String,
    private val onChange: () -> Unit
) {
    private val http = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    private val handler = Handler(Looper.getMainLooper())
    private var ws: WebSocket? = null
    @Volatile private var stopped = false
    private var ref = 1

    private val heartbeat = object : Runnable {
        override fun run() {
            ws?.send(JSONObject().put("topic", "phoenix").put("event", "heartbeat")
                .put("payload", JSONObject()).put("ref", (++ref).toString()).toString())
            if (!stopped) handler.postDelayed(this, 25_000)
        }
    }

    fun start() {
        stopped = false
        connect()
    }

    fun stop() {
        stopped = true
        handler.removeCallbacksAndMessages(null)
        ws?.close(1000, null)
        ws = null
    }

    private fun connect() {
        if (stopped || !client.isConfigured) return
        val wsUrl = client.baseUrl().replaceFirst("https://", "wss://") +
            "/realtime/v1/websocket?apikey=" + client.apiKey() + "&vsn=1.0.0"
        ws = http.newWebSocket(Request.Builder().url(wsUrl).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(joinMessage())
                handler.removeCallbacks(heartbeat)
                handler.postDelayed(heartbeat, 25_000)
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (text.contains("postgres_changes") && text.contains("\"event\":\"postgres_changes\"")) onChange()
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = reconnect()
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { if (!stopped) reconnect() }
        })
    }

    private fun reconnect() {
        if (stopped) return
        handler.removeCallbacks(heartbeat)
        handler.postDelayed({ connect() }, 5_000)
    }

    private fun joinMessage(): String {
        fun change(event: String, table: String, filter: String) =
            JSONObject().put("event", event).put("schema", "public").put("table", table).put("filter", filter)
        val changes = JSONArray()
            .put(change("*", "games", "id=eq.$gameId"))
            .put(change("*", "game_players", "game_id=eq.$gameId"))
            .put(change("INSERT", "game_events", "game_id=eq.$gameId"))
            .put(change("INSERT", "game_messages", "game_id=eq.$gameId"))
            .put(change("INSERT", "vote_results", "game_id=eq.$gameId"))
        val config = JSONObject()
            .put("broadcast", JSONObject().put("self", false))
            .put("presence", JSONObject().put("key", ""))
            .put("postgres_changes", changes)
        val payload = JSONObject().put("config", config)
        client.accessToken()?.let { payload.put("access_token", it) }
        return JSONObject().put("topic", "realtime:game-$gameId").put("event", "phx_join")
            .put("payload", payload).put("ref", "1").put("join_ref", "1").toString()
    }
}
