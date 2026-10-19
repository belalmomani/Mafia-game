package com.mafia.game.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.mafia.game.BuildConfig
import com.mafia.game.data.SupabaseClient
import com.mafia.game.util.findActivity
import kotlinx.coroutines.launch

@Composable
fun AccountScreen(client: SupabaseClient, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var current by remember { mutableStateOf(client.userEmail()) }

    fun act(block: suspend () -> String) {
        scope.launch {
            busy = true; msg = ""
            try { msg = block() } catch (e: Exception) { msg = friendlyError(e) }
            current = client.userEmail()
            busy = false
        }
    }

    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("حسابي", style = MaterialTheme.typography.titleLarge)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (current == null) "حسابك الآن مجهول: يضيع إن مسحت بيانات التطبيق أو غيّرت الهاتف."
                     else "حسابك محمي بالبريد: $current")
                Text("اربط بريدًا وكلمة مرور (6 خانات على الأقل) لتحتفظ باسمك وغرفك.")
            }
        }
        OutlinedTextField(email, { email = it.trim() }, label = { Text("البريد الإلكتروني") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth())
        OutlinedTextField(password, { password = it }, label = { Text("كلمة المرور") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth())

        Button(enabled = !busy && email.contains("@") && password.length >= 6, modifier = Modifier.fillMaxWidth(),
            onClick = { act { client.linkEmail(email, password) } }) { Text("ربط حسابي الحالي بهذا البريد") }
        OutlinedButton(enabled = !busy && email.contains("@") && password.length >= 6, modifier = Modifier.fillMaxWidth(),
            onClick = { act { client.signInEmail(email, password); "تم تسجيل الدخول" } }) { Text("تسجيل الدخول بحساب موجود") }
        OutlinedButton(enabled = !busy && email.contains("@") && password.length >= 6, modifier = Modifier.fillMaxWidth(),
            onClick = { act { client.signUpEmail(email, password) } }) { Text("إنشاء حساب جديد") }
        if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()) {
            OutlinedButton(enabled = !busy, modifier = Modifier.fillMaxWidth(),
                onClick = { act { signInWithGoogle(ctx, client) } }) { Text("الدخول بحساب Google") }
        }
        if (msg.isNotBlank()) Text(msg)
        SelectionContainer { Text("معرّف حسابك (اضغط مطولًا للنسخ): ${client.currentUserId() ?: "-"}", style = MaterialTheme.typography.bodySmall) }
        Text("ملاحظة: إن طلب Supabase تأكيد البريد فسيصلك رابط. يمكن للمالك تعطيل «Confirm email» من لوحة Supabase لتجربة أسرع.",
            style = MaterialTheme.typography.bodySmall)
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}

private suspend fun signInWithGoogle(ctx: Context, client: SupabaseClient): String {
    val activity = ctx.findActivity() ?: throw Exception("تعذر فتح نافذة Google")
    val option = GetGoogleIdOption.Builder()
        .setFilterByAuthorizedAccounts(false)
        .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
        .build()
    val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
    val result = try {
        CredentialManager.create(activity).getCredential(activity, request)
    } catch (e: GetCredentialException) {
        throw Exception("تعذر تسجيل Google: " + (e.message ?: e.type))
    }
    val cred = result.credential
    if (cred is CustomCredential && cred.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
        client.signInGoogle(GoogleIdTokenCredential.createFrom(cred.data).idToken)
        return "تم تسجيل الدخول بحساب Google"
    }
    throw Exception("نوع بيانات اعتماد غير مدعوم")
}
