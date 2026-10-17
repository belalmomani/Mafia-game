package com.mafia.game.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.startapp.sdk.ads.banner.Banner

/** بانر Start.io صغير أسفل الشاشة، خارج المحتوى فلا يغطي شيئًا. */
@Composable
fun AdBanner(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { ctx -> Banner(ctx) },
        modifier = modifier.fillMaxWidth().wrapContentHeight()
    )
}
