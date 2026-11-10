package com.mafia.game.util

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.mafia.game.data.SupabaseClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

/** تسجيل رمز جهاز FCM على الخادم. لا يفعل شيئًا إن لم يكن google-services.json موجودًا. */
object PushRegistrar {
    fun register(ctx: Context, client: SupabaseClient) {
        runCatching {
            if (FirebaseApp.getApps(ctx).isEmpty()) return
            FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
                CoroutineScope(Dispatchers.IO).launch {
                    runCatching { client.rpc("register_push_token", JSONObject().put("p_token", token)) }
                }
            }
        }
    }
}

/** النظام يعرض إشعارات الخلفية تلقائيًا؛ هذه الخدمة تعالج رسائل البيانات فقط وتتجاهل الواجهة المفتوحة. */
class MafiaMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // يُسجَّل الرمز الجديد عند فتح التطبيق المقبل (PushRegistrar.register).
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (AppState.foreground) return
        if (message.notification != null) return
        Notifier.notify(this, message.data["title"] ?: "المافيا", message.data["body"] ?: "")
    }
}
