package com.mafia.game.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** الزر الأساسي: كبسولة بتدرّج بنفسجي (أحمر في وضع اللعبة)، بأيقونة اختيارية، وبلون واضح عند التعطيل. */
@Composable
fun PrimaryButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, compact: Boolean = false, icon: ImageVector? = null
) {
    val c = LocalAppColors.current
    val fg = if (enabled) c.onBtn else c.disabledFg
    val bg = if (enabled) Brush.horizontalGradient(listOf(c.btnStart, c.btnEnd))
             else Brush.horizontalGradient(listOf(c.disabledBg, c.disabledBg))
    Row(
        modifier
            .heightIn(min = if (compact) 44.dp else 54.dp)
            .clip(RoundedCornerShape(50))
            .background(bg)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (compact) 20.dp else 24.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(if (compact) 18.dp else 22.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, color = fg, fontWeight = FontWeight.Bold, fontSize = if (compact) 15.sp else 17.sp)
    }
}

/** زر ثانوي: كبسولة بحدّ ملوّن وأيقونة اختيارية. */
@Composable
fun GhostButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    enabled: Boolean = true, compact: Boolean = false, icon: ImageVector? = null
) {
    val c = LocalAppColors.current
    val fg = if (enabled) c.accent else c.disabledFg
    Row(
        modifier
            .heightIn(min = if (compact) 44.dp else 52.dp)
            .clip(RoundedCornerShape(50))
            .background(if (c.dark) Color.Transparent else Color.White)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (compact) 18.dp else 22.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, color = fg, fontWeight = FontWeight.Bold, fontSize = if (compact) 15.sp else 16.sp)
    }
}

/** زر اختيار (مثل «عامة / خاصة»). */
@Composable
fun ChoiceButton(text: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = LocalAppColors.current
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 48.dp),
        shape = RoundedCornerShape(50),
        border = BorderStroke(1.dp, if (selected) c.accent else c.fieldBorder),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (selected) c.accent.copy(alpha = 0.15f) else c.cardHigh,
            contentColor = if (selected) c.accent else c.muted
        )
    ) { Text(text, fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium, fontSize = 16.sp) }
}

/** بطاقة قسم: أيقونة وعنوان في الطرف الأول (يمين في RTL)، وإجراء اختياري في الطرف المقابل. */
@Composable
fun SectionCard(
    title: String, modifier: Modifier = Modifier, subtitle: String? = null, icon: String? = null,
    action: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit
) {
    val c = LocalAppColors.current
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = c.card),
        elevation = CardDefaults.cardElevation(defaultElevation = if (c.dark) 0.dp else 3.dp),
        border = BorderStroke(1.dp, c.line)
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) {
                    Text(icon, fontSize = 22.sp)
                    Spacer(Modifier.width(10.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium, color = c.title)
                    if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = c.muted)
                }
                if (action != null) action()
            }
            content()
        }
    }
}

/** حقل إدخال: حدّ ناعم، وأيقونة بداية اختيارية (يمينًا في RTL)، و`ltr` للرموز اللاتينية. */
@Composable
fun AppField(
    value: String, onChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, ltr: Boolean = false,
    center: Boolean = false, leading: String? = null
) {
    val c = LocalAppColors.current
    val style = if (ltr) LocalTextStyle.current.copy(
        textDirection = TextDirection.Ltr, textAlign = if (center) TextAlign.Center else TextAlign.Start,
        letterSpacing = 3.sp, fontWeight = FontWeight.Bold, fontSize = 18.sp
    ) else LocalTextStyle.current
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label) },
        singleLine = true, keyboardOptions = keyboardOptions, textStyle = style,
        leadingIcon = if (leading != null) ({ Text(leading, fontSize = 18.sp) }) else null,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = c.fieldText, unfocusedTextColor = c.fieldText,
            focusedBorderColor = c.accent, unfocusedBorderColor = c.fieldBorder,
            focusedLabelColor = c.accent, unfocusedLabelColor = c.muted,
            cursorColor = c.accent,
            focusedContainerColor = c.field, unfocusedContainerColor = c.field
        )
    )
}

/** شريط رسالة: أخضر للنجاح (تبدأ بـ «تم»/«أُرسل»)، وأحمر للخطأ. */
@Composable
fun StatusBanner(text: String, modifier: Modifier = Modifier) {
    val c = LocalAppColors.current
    val ok = text.startsWith("تم") || text.startsWith("أُرسل") || text.startsWith("أُزيل")
    val accent = if (ok) c.success else c.danger
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = accent.copy(alpha = 0.12f)),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.6f))
    ) { Text(text, Modifier.padding(12.dp), color = accent, style = MaterialTheme.typography.bodyMedium) }
}

/** بطاقة غرفة: أيقونة واسم الغرفة، وعدد اللاعبين، وزر دخول كبسولة في الطرف المقابل. */
@Composable
fun RoomCard(
    name: String, count: Int, max: Int, actionText: String, enabled: Boolean,
    allowWhenFull: Boolean = false, actionIcon: ImageVector? = null,
    onDelete: (() -> Unit)? = null, onClick: () -> Unit
) {
    val c = LocalAppColors.current
    val full = max > 0 && count >= max
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = c.card),
        elevation = CardDefaults.cardElevation(defaultElevation = if (c.dark) 0.dp else 3.dp),
        border = BorderStroke(1.dp, c.line)
    ) {
        Row(
            Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("👥", fontSize = 18.sp)
                    Text(name, style = MaterialTheme.typography.titleMedium, color = c.title,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("👤", fontSize = 15.sp)
                    Text("$count/$max لاعبين", style = MaterialTheme.typography.bodyMedium,
                        color = if (full) c.danger else c.muted)
                    if (full) Text("ممتلئة", style = MaterialTheme.typography.bodySmall, color = c.danger, fontWeight = FontWeight.Bold)
                }
            }
            if (onDelete != null) GhostButton("🗑️", onDelete, compact = true)
            PrimaryButton(actionText, onClick, enabled = enabled && (allowWhenFull || !full), compact = true, icon = actionIcon)
        }
    }
}

/** زر مربّع صغير للزيادة/النقصان (+ / −). */
@Composable
fun StepperButton(text: String, onClick: () -> Unit, enabled: Boolean = true) {
    val c = LocalAppColors.current
    OutlinedButton(
        onClick = onClick, enabled = enabled,
        modifier = Modifier.size(46.dp),
        shape = RoundedCornerShape(14.dp),
        contentPadding = PaddingValues(0.dp),
        border = BorderStroke(1.dp, if (enabled) c.accent.copy(alpha = 0.7f) else c.fieldBorder),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = c.accent, disabledContentColor = c.disabledFg)
    ) { Text(text, fontWeight = FontWeight.Bold, fontSize = 22.sp) }
}
