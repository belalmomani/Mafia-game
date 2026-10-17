package com.mafia.game.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

@Composable
fun RulesScreen(onBack: () -> Unit) {
    val rules = listOf(
        "تبدأ اللعبة بالتبرير: لكل لاعب دور للكلام، ثم يبدأ التصويت.",
        "التصويت صوت واحد لا يتغير. الأغلبية تُقصي، والتعادل لا يُقصي أحدًا.",
        "إن خرج مافيا: تبرير جديد وتصويت جديد بلا ليل. وإن خرج غير مافيا: يأتي الليل.",
        "في الليل: المافيا تغتال (قرار الأحمر نهائي)، والبنت تحمي، والشيخ يفجّر، والإسكات يُسكت.",
        "اغتيال لاعب محمي = «عملية اغتيال فاشلة». التفجير لا تمنعه الحماية.",
        "المواطنون يفوزون بانتهاء المافيا، والمافيا تفوز بتساوي عددها مع الباقين أو زيادته."
    )
    val roles = listOf(
        "red_mafia" to "أنت أكبر ورقة: تقرر ضحية الليل بعد اقتراحات فريقك.",
        "mafia" to "تعرف زملاءك في المافيا وتقترح الضحية.",
        "silencer" to "مافيا الإسكات (اختياري): تُسكت لاعبًا كل ليلة فلا يُمنح دور كلام يومها.",
        "sheikh" to "تفجّر لاعبًا كل ليلة، يموت فورًا ولا تمنعه الحماية.",
        "girl" to "تحمين لاعبًا (ولك حماية نفسك) من الاغتيال، لا من التفجير، ولا نفس الشخص مرتين متتاليتين.",
        "boy" to "عند قتلك تسحب معك لاعبًا تشك أنه مافيا (مهلة قصيرة للاختيار).",
        "hunter" to "طلقة واحدة في النهار: يموت الهدف دائمًا حتى لو كان بريئًا.",
        "citizen" to "بلا قدرة: اكشف المافيا وابقَ على قيد الحياة."
    )
    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("القواعد والأدوار", style = MaterialTheme.typography.titleLarge)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                rules.forEach { Text("• $it") }
            }
        }
        roles.forEach { (role, desc) ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(Roles.nameAr(role), style = MaterialTheme.typography.titleMedium)
                    Image(painterResource(Roles.cardRes(role)), contentDescription = Roles.nameAr(role),
                        modifier = Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth)
                    Text(desc)
                }
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("رجوع") }
    }
}
