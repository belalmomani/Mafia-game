package com.mafia.game.data

import android.content.Context
import com.mafia.game.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * عميل Supabase خفيف عبر REST (بدون مكتبات إضافية).
 * يستعمل المفتاح العام فقط. الصلاحيات الفعلية تحددها سياسات RLS والدوال في قاعدة البيانات.
 * ملاحظة: الجلسة تُحفظ حاليًا في تخزين التطبيق الخاص؛ نرقّيها لتخزين مشفّر في مرحلة لاحقة.
 */
class SupabaseClient(context: Context) {
    private val url = BuildConfig.SUPABASE_URL.trimEnd('/')
    private val key = BuildConfig.SUPABASE_PUBLISHABLE_KEY
    private val prefs = context.getSharedPreferences("supabase_session", Context.MODE_PRIVATE)

    val isConfigured: Boolean get() = url.startsWith("https://") && key.isNotBlank()

    fun baseUrl(): String = url
    fun apiKey(): String = key
    fun accessToken(): String? = prefs.getString("access_token", null)
    /** بريد الحساب إن كان الحساب مرتبطًا ببريد (وإلا حساب مجهول). */
    fun userEmail(): String? = prefs.getString("email", null)?.takeIf { it.isNotBlank() }

    /** تسجيل دخول ببريد وكلمة مرور (لحساب موجود، مثلًا على جهاز جديد). */
    suspend fun signInEmail(email: String, password: String): String {
        val (code, body) = http("POST", "/auth/v1/token?grant_type=password",
            JSONObject().put("email", email).put("password", password).toString())
        if (code !in 200..299) throw ApiException(code, errorText(body))
        return saveSession(JSONObject(body))
    }

    /** تسجيل الدخول بحساب Google عبر رمز الهوية (ID token). */
    suspend fun signInGoogle(idToken: String): String {
        val (code, body) = http("POST", "/auth/v1/token?grant_type=id_token",
            JSONObject().put("provider", "google").put("id_token", idToken).toString())
        if (code !in 200..299) throw ApiException(code, errorText(body))
        return saveSession(JSONObject(body))
    }

    /** إنشاء حساب جديد ببريد وكلمة مرور. */
    suspend fun signUpEmail(email: String, password: String): String {
        val (code, body) = http("POST", "/auth/v1/signup",
            JSONObject().put("email", email).put("password", password).toString())
        if (code !in 200..299) throw ApiException(code, errorText(body))
        val j = JSONObject(body)
        return if (j.has("access_token")) { saveSession(j); "تم إنشاء الحساب وتسجيل الدخول" }
        else "أُرسل رابط تأكيد إلى بريدك. افتحه ثم سجّل الدخول."
    }

    /** ربط الحساب المجهول الحالي ببريد وكلمة مرور (تبقى غرفك وبياناتك). */
    suspend fun linkEmail(email: String, password: String): String {
        ensureSession()
        val (code, body) = http("PUT", "/auth/v1/user",
            JSONObject().put("email", email).put("password", password).toString(), auth = true)
        if (code !in 200..299) throw ApiException(code, errorText(body))
        val j = JSONObject(body)
        val confirmed = j.optString("email", "")
        if (confirmed.isNotBlank()) prefs.edit().putString("email", confirmed).apply()
        return if (j.optString("new_email", "").isNotBlank()) "أُرسل رابط تأكيد إلى بريدك لإكمال الربط."
        else "تم ربط حسابك. يمكنك الدخول به من أي جهاز."
    }

    class ApiException(val status: Int, message: String) : Exception(message)

    /** اختبار الاتصال: دالة ping لا تلمس أي بيانات. */
    suspend fun ping(): String = ok(http("POST", "/rest/v1/rpc/ping", "{}"))

    /** يضمن وجود جلسة صالحة (تجديد، أو دخول مجهول جديد) ويعيد معرّف المستخدم. */
    suspend fun ensureSession(): String {
        val expiresAt = prefs.getLong("expires_at", 0L)
        val uid = prefs.getString("user_id", null)
        if (uid != null && prefs.getString("access_token", null) != null &&
            expiresAt > System.currentTimeMillis() / 1000 + 60
        ) return uid

        val refresh = prefs.getString("refresh_token", null)
        if (refresh != null) {
            val (code, body) = http(
                "POST", "/auth/v1/token?grant_type=refresh_token",
                JSONObject().put("refresh_token", refresh).toString()
            )
            if (code in 200..299) return saveSession(JSONObject(body))
            prefs.edit().clear().apply() // الجلسة لم تعد صالحة
        }
        // يتطلب تفعيل Anonymous sign-ins في لوحة Supabase
        val (code, body) = http("POST", "/auth/v1/signup", "{}")
        if (code !in 200..299) throw ApiException(code, errorText(body))
        return saveSession(JSONObject(body))
    }

    /** ملفي الشخصي (RLS تسمح بقراءة الملفات للمسجّلين). */
    suspend fun myProfile(): String {
        val uid = ensureSession()
        return ok(
            http("GET", "/rest/v1/profiles?select=id,username,display_name&id=eq.$uid", null, auth = true)
        )
    }

    /** قراءة من REST بصلاحيات المستخدم (تطبّق RLS). */
    suspend fun get(path: String): String {
        ensureSession()
        return ok(http("GET", path, null, auth = true))
    }

    /** استدعاء دالة خادمية (RPC). كل منطق اللعبة يمر من هنا. */
    suspend fun rpc(name: String, body: JSONObject = JSONObject()): String {
        ensureSession()
        return ok(http("POST", "/rest/v1/rpc/$name", body.toString(), auth = true))
    }

    fun currentUserId(): String? = prefs.getString("user_id", null)

    fun signOutLocal() = prefs.edit().clear().apply()

    // ---------- داخلي ----------
    private fun saveSession(json: JSONObject): String {
        val uid = json.getJSONObject("user").getString("id")
        prefs.edit()
            .putString("access_token", json.getString("access_token"))
            .putString("refresh_token", json.getString("refresh_token"))
            .putString("user_id", uid)
            .putString("email", json.getJSONObject("user").optString("email", ""))
            .putLong("expires_at", System.currentTimeMillis() / 1000 + json.optLong("expires_in", 3600))
            .apply()
        return uid
    }

    private fun ok(r: Pair<Int, String>): String {
        if (r.first !in 200..299) throw ApiException(r.first, errorText(r.second))
        return r.second
    }

    private fun errorText(body: String): String = try {
        val j = JSONObject(body)
        j.optString("msg").ifBlank { j.optString("message") }.ifBlank { j.optString("error_description") }
            .ifBlank { body.take(200) }
    } catch (e: Exception) { body.take(200) }

    private suspend fun http(
        method: String, path: String, body: String?, auth: Boolean = false
    ): Pair<Int, String> = withContext(Dispatchers.IO) {
        val conn = URL(url + path).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = 10_000
            conn.readTimeout = 15_000
            conn.setRequestProperty("apikey", key)
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            if (auth) prefs.getString("access_token", null)?.let {
                conn.setRequestProperty("Authorization", "Bearer $it")
            }
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toByteArray()) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            code to (stream?.bufferedReader()?.use { it.readText() } ?: "")
        } finally {
            conn.disconnect()
        }
    }
}
