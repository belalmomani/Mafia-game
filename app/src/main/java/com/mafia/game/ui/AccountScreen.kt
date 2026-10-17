package com.mafia.game.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import kotlinx.coroutines.launch

@Composable
fun AccountScreen(client: SupabaseClient, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
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
        if (msg.isNotBlank()) Text(msg)
        Text("ملاحظة: إن طلب Supabase تأكيد البريد فسيصلك رابط. يمكن للمالك تعطيل «Confirm email» من لوحة Supabase لتجربة أسرع.",
            style = MaterialTheme.typography.bodySmall)
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}
