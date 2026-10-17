package com.mafia.game

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import com.mafia.game.ui.AdBanner
import com.mafia.game.ui.ConnectionScreen
import com.mafia.game.ui.GameScreen
import com.mafia.game.ui.HomeScreen
import com.mafia.game.ui.LobbyScreen

private sealed interface Screen {
    data object Home : Screen
    data object Debug : Screen
    data class Lobby(val roomId: String) : Screen
    data class Game(val gameId: String, val roomId: String) : Screen
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // إعلانات تجريبية في نسخ debug (عبر reflection كي لا يتعطل البناء إن تغيّر اسم الدالة في SDK)
        runCatching {
            Class.forName("com.startapp.sdk.adsbase.StartAppSDK")
                .getMethod("setTestAdsEnabled", Boolean::class.javaPrimitiveType)
                .invoke(null, BuildConfig.DEBUG)
        }
        val client = SupabaseClient(applicationContext)
        setContent { MaterialTheme { Surface(Modifier.fillMaxSize()) { App(client) } } }
    }
}

@Composable
private fun App(client: SupabaseClient) {
    var screen by remember { mutableStateOf<Screen>(Screen.Home) }
    BackHandler(enabled = screen != Screen.Home) { screen = Screen.Home }

    Column(Modifier.safeDrawingPadding()) {
      Box(Modifier.weight(1f).padding(16.dp)) {
        when (val s = screen) {
            Screen.Home -> HomeScreen(client, onOpenRoom = { screen = Screen.Lobby(it) }, onDebug = { screen = Screen.Debug })
            Screen.Debug -> ConnectionScreen(client, onBack = { screen = Screen.Home })
            is Screen.Lobby -> LobbyScreen(client, s.roomId, onBack = { screen = Screen.Home },
                onGame = { screen = Screen.Game(it, s.roomId) })
            is Screen.Game -> GameScreen(client, s.gameId, onExit = { screen = Screen.Home })
        }
      }
      AdBanner(Modifier.fillMaxWidth())
    }
}
