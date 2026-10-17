package com.mafia.game.util

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.mafia.game.MainActivity

/** حالة التطبيق: هل الشاشة ظاهرة الآن؟ (تحدّثها MainActivity) */
object AppState {
    @Volatile var foreground: Boolean = false
}

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** اهتزاز + إشعار محلي (يعمل ما دام التطبيق حيًا في الخلفية؛ الإشعارات الفورية الكاملة تحتاج FCM لاحقًا). */
object Notifier {
    private const val CHANNEL = "game_events"

    fun init(ctx: Context) {
        val ch = NotificationChannel(CHANNEL, "أحداث اللعبة", NotificationManager.IMPORTANCE_HIGH)
        ctx.getSystemService(NotificationManager::class.java)?.createNotificationChannel(ch)
    }

    @Suppress("DEPRECATION")
    fun vibrate(ctx: Context, ms: Long = 250) {
        runCatching {
            val v = ctx.getSystemService(Vibrator::class.java) ?: return
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }

    @SuppressLint("MissingPermission")
    fun notify(ctx: Context, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        runCatching {
            val open = PendingIntent.getActivity(
                ctx, 0,
                Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val n = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title).setContentText(text)
                .setAutoCancel(true).setContentIntent(open)
                .setPriority(NotificationCompat.PRIORITY_HIGH).build()
            NotificationManagerCompat.from(ctx).notify(1001, n)
        }
    }
}
