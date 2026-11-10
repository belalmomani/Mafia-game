package com.mafia.game.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.math.abs

/** ورقة الدور تنقلب من الخلف إلى الوجه عند الكشف. */
@Composable
fun FlipCard(role: String) {
    var flipped by remember { mutableStateOf(false) }
    LaunchedEffect(role) { delay(250); flipped = true }
    val rot by animateFloatAsState(if (flipped) 0f else 180f, animationSpec = tween(900), label = "flip")
    val density = LocalDensity.current.density
    Box(Modifier.fillMaxWidth().graphicsLayer { rotationY = rot; cameraDistance = 12f * density }) {
        if (abs(rot) > 90f) {
            Box(
                Modifier.fillMaxWidth().aspectRatio(1.45f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF14141C))
                    .border(2.dp, Palette.Gold, RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center
            ) { Text("؟", style = MaterialTheme.typography.displayLarge, color = Palette.Gold) }
        } else {
            Image(painterResource(Roles.cardRes(role)), contentDescription = Roles.nameAr(role),
                modifier = Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth)
        }
    }
}
