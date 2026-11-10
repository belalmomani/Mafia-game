package com.mafia.game.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** لوحة «نوار» الداكنة: تُستعمل داخل اللعبة (ليل/تبرير/تصويت). */
object Palette {
    val Ink = Color(0xFF0D0B14)
    val Card = Color(0xFF1B1727)
    val CardHigh = Color(0xFF262033)
    val Blood = Color(0xFFD9453B)
    val BloodDeep = Color(0xFF8E1F1A)
    val Gold = Color(0xFFD4B16A)
    val Violet = Color(0xFF7C5CD6)
    val VioletDeep = Color(0xFF2A1F4A)
    val Danger = Color(0xFFFF6B5E)
    val Ok = Color(0xFF6BD18B)
    val Muted = Color(0xFFB9B2C6)
    val Line = Color(0x22FFFFFF)
}

/** ألوان المكوّنات المشتركة: نسخة «لافندر» فاتحة للقوائم، ونسخة «نوار» داكنة للعبة. */
data class AppColors(
    val dark: Boolean,
    val card: Color, val cardHigh: Color, val line: Color,
    val title: Color, val muted: Color, val accent: Color,
    val field: Color, val fieldBorder: Color, val fieldText: Color,
    val disabledBg: Color, val disabledFg: Color,
    val success: Color, val danger: Color,
    val btnStart: Color, val btnEnd: Color, val onBtn: Color
)

val LightAppColors = AppColors(
    dark = false,
    card = Color(0xFFFFFFFF), cardHigh = Color(0xFFFFFFFF), line = Color(0xFFECE8F7),
    title = Color(0xFF1E1B2E), muted = Color(0xFF6E6A80), accent = Color(0xFF6C4CC9),
    field = Color(0xFFFFFFFF), fieldBorder = Color(0xFFC9C3DC), fieldText = Color(0xFF1E1B2E),
    disabledBg = Color(0xFFD9D4EA), disabledFg = Color(0xFF6F688A),
    success = Color(0xFF1E8E4E), danger = Color(0xFFD93B3B),
    btnStart = Color(0xFF8A5CD6), btnEnd = Color(0xFF6C4CC9), onBtn = Color.White
)

val DarkAppColors = AppColors(
    dark = true,
    card = Palette.Card, cardHigh = Palette.CardHigh, line = Palette.Line,
    title = Color(0xFFEDE8DC), muted = Palette.Muted, accent = Palette.Gold,
    field = Color(0xFF14111D), fieldBorder = Color(0xFF4A4358), fieldText = Color(0xFFEDE8DC),
    disabledBg = Color(0xFF2B2738), disabledFg = Color(0xFF9A93AA),
    success = Palette.Ok, danger = Palette.Danger,
    btnStart = Palette.Blood, btnEnd = Palette.Blood, onBtn = Color.White
)

val LocalAppColors = staticCompositionLocalOf { LightAppColors }

/** المرحلة الحالية لتلوين خلفية اللعبة (تضبطها شاشة اللعبة وتصفّرها عند الخروج). */
object Atmosphere {
    var phase by mutableStateOf("")
}

fun atmosphereBrush(phase: String): Brush = when (phase) {
    "night" -> Brush.verticalGradient(listOf(Color(0xFF080814), Color(0xFF1B1140)))
    "day" -> Brush.verticalGradient(listOf(Color(0xFF16120C), Color(0xFF2E2111)))
    "voting" -> Brush.verticalGradient(listOf(Color(0xFF160A0A), Color(0xFF331212)))
    else -> Brush.verticalGradient(listOf(Palette.Ink, Color(0xFF1A1230)))
}

/** خلفية التطبيق: لافندر فاتح للقوائم، ومتدرجة حسب المرحلة داخل اللعبة. */
fun backdropBrush(dark: Boolean, phase: String): Brush =
    if (dark) atmosphereBrush(phase)
    else Brush.verticalGradient(listOf(Color(0xFFF1EDFB), Color(0xFFFAF9FE), Color(0xFFFFFFFF)))

private val NoirColors = darkColorScheme(
    primary = Palette.Blood, onPrimary = Color.White,
    primaryContainer = Palette.BloodDeep, onPrimaryContainer = Color.White,
    secondary = Palette.Gold, onSecondary = Color(0xFF1A1405),
    secondaryContainer = Palette.VioletDeep, onSecondaryContainer = Color(0xFFEDE8DC),
    tertiary = Palette.Violet,
    background = Palette.Ink, onBackground = Color(0xFFEDE8DC),
    surface = Palette.Ink, onSurface = Color(0xFFEDE8DC),
    surfaceVariant = Palette.Card, onSurfaceVariant = Palette.Muted,
    surfaceContainerHighest = Palette.Card, surfaceContainerHigh = Palette.Card, surfaceContainer = Palette.Card,
    outline = Color(0xFF7A7388), outlineVariant = Color(0xFF3A3448),
    error = Palette.Danger, onError = Color.Black
)

private val LavenderColors = lightColorScheme(
    primary = Color(0xFF6C4CC9), onPrimary = Color.White,
    primaryContainer = Color(0xFFE6DEFA), onPrimaryContainer = Color(0xFF2A1F4A),
    secondary = Color(0xFF8A5CD6), onSecondary = Color.White,
    secondaryContainer = Color(0xFFEFEAFB), onSecondaryContainer = Color(0xFF2A1F4A),
    tertiary = Color(0xFFD9453B),
    background = Color(0xFFF6F4FD), onBackground = Color(0xFF1E1B2E),
    surface = Color(0xFFFFFFFF), onSurface = Color(0xFF1E1B2E),
    surfaceVariant = Color(0xFFEFEBFA), onSurfaceVariant = Color(0xFF6E6A80),
    surfaceContainerHighest = Color(0xFFFFFFFF), surfaceContainerHigh = Color(0xFFFFFFFF), surfaceContainer = Color(0xFFFFFFFF),
    outline = Color(0xFFB8B1CC), outlineVariant = Color(0xFFE3DEF1),
    error = Color(0xFFD93B3B), onError = Color.White
)

/** يبحث عن خط Tajawal المضمَّن في res/font (يُنزَّل أثناء البناء)، وإلا يستعمل خط النظام. */
@Composable
private fun rememberAppFontFamily(): FontFamily {
    val ctx = LocalContext.current
    return remember(ctx) {
        val pkg = ctx.packageName
        val fonts = listOf(
            "tajawal_regular" to FontWeight.Normal,
            "tajawal_medium" to FontWeight.Medium,
            "tajawal_bold" to FontWeight.Bold,
            "tajawal_extrabold" to FontWeight.ExtraBold
        ).mapNotNull { (name, weight) ->
            val id = ctx.resources.getIdentifier(name, "font", pkg)
            if (id != 0) Font(id, weight) else null
        }
        if (fonts.isEmpty()) FontFamily.Default else FontFamily(fonts)
    }
}

private fun appTypography(f: FontFamily): Typography {
    val b = Typography()
    return Typography(
        displayLarge = b.displayLarge.copy(fontFamily = f),
        displayMedium = b.displayMedium.copy(fontFamily = f),
        displaySmall = b.displaySmall.copy(fontFamily = f),
        headlineLarge = b.headlineLarge.copy(fontFamily = f, fontWeight = FontWeight.ExtraBold),
        headlineMedium = b.headlineMedium.copy(fontFamily = f, fontWeight = FontWeight.ExtraBold),
        headlineSmall = b.headlineSmall.copy(fontFamily = f, fontWeight = FontWeight.Bold),
        titleLarge = b.titleLarge.copy(fontFamily = f, fontWeight = FontWeight.Bold, fontSize = 22.sp, lineHeight = 30.sp),
        titleMedium = b.titleMedium.copy(fontFamily = f, fontWeight = FontWeight.Bold, fontSize = 17.sp, lineHeight = 26.sp),
        titleSmall = b.titleSmall.copy(fontFamily = f, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 22.sp),
        bodyLarge = b.bodyLarge.copy(fontFamily = f, fontSize = 16.sp, lineHeight = 26.sp),
        bodyMedium = b.bodyMedium.copy(fontFamily = f, fontSize = 15.sp, lineHeight = 23.sp),
        bodySmall = b.bodySmall.copy(fontFamily = f, fontSize = 13.sp, lineHeight = 20.sp),
        labelLarge = b.labelLarge.copy(fontFamily = f, fontWeight = FontWeight.Bold, fontSize = 15.sp),
        labelMedium = b.labelMedium.copy(fontFamily = f, fontWeight = FontWeight.Medium),
        labelSmall = b.labelSmall.copy(fontFamily = f)
    )
}

/**
 * الثيم العام. اتجاه الواجهة RTL دائمًا (اللعبة عربية) بغض النظر عن لغة الهاتف.
 * dark=false: لافندر فاتح (الرئيسية والقوائم) · dark=true: «نوار» داكن (داخل اللعبة).
 */
@Composable
fun MafiaTheme(dark: Boolean = false, content: @Composable () -> Unit) {
    val family = rememberAppFontFamily()
    CompositionLocalProvider(
        LocalLayoutDirection provides LayoutDirection.Rtl,
        LocalAppColors provides (if (dark) DarkAppColors else LightAppColors)
    ) {
        MaterialTheme(
            colorScheme = if (dark) NoirColors else LavenderColors,
            typography = appTypography(family),
            shapes = Shapes(
                extraSmall = RoundedCornerShape(8.dp),
                small = RoundedCornerShape(12.dp),
                medium = RoundedCornerShape(16.dp),
                large = RoundedCornerShape(24.dp)
            ),
            content = content
        )
    }
}

/** مؤقت دائري: ذهبي، ويتحول للأحمر في آخر 5 ثوانٍ. */
@Composable
fun PhaseTimer(left: Long, total: Int, modifier: Modifier = Modifier) {
    val frac = if (total > 0) (left.toFloat() / total).coerceIn(0f, 1f) else 0f
    val color = if (left <= 5) Palette.Danger else Palette.Gold
    Box(modifier.size(64.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 6.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            val topLeft = Offset(inset, inset)
            drawArc(color = Color(0x33FFFFFF), startAngle = -90f, sweepAngle = 360f, useCenter = false,
                topLeft = topLeft, size = arcSize, style = Stroke(stroke))
            drawArc(color = color, startAngle = -90f, sweepAngle = 360f * frac, useCenter = false,
                topLeft = topLeft, size = arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Text(left.toString(), color = color, fontWeight = FontWeight.Bold)
    }
}
