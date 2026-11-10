package com.mafia.game

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.ui.unit.dp
import com.mafia.game.data.SupabaseClient
import com.mafia.game.ui.AccountScreen
import com.mafia.game.ui.Atmosphere
import com.mafia.game.ui.MafiaTheme
import com.mafia.game.ui.backdropBrush
import com.mafia.game.ui.AdminScreen
import com.mafia.game.ui.StatsScreen
import com.mafia.game.ui.AdBanner
import com.mafia.game.ui.ConnectionScreen
import com.mafia.game.ui.GameScreen
import com.mafia.game.ui.LabGameScreen
import com.mafia.game.ui.LabHomeScreen
import com.mafia.game.ui.HomeScreen
import com.mafia.game.ui.LobbyScreen
import com.mafia.game.ui.RulesScreen
import com.mafia.game.util.AppState
import com.mafia.game.util.Notifier
import com.mafia.game.util.findActivity

private sealed interface Screen {
    data object Home : Screen
    data object Debug : Screen
    data object Account : Screen
    data object Rules : Screen
    data object Stats : Screen
    data object Admin : Screen
    data object Lab : Screen
    data class LabGame(val gameId: String) : Screen
    data class Lobby(val roomId: String) : Screen
    data class Game(val gameId: String, val roomId: String) : Screen
}

class MainActivity : ComponentActivity() {
    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // إعلانات تجريبية في نسخ debug (عبر reflection كي لا يتعطل البناء إن تغيّر اسم الدالة في SDK)
        runCatching {
            Class.forName("com.startapp.sdk.adsbase.StartAppSDK")
                .getMethod("setTestAdsEnabled", Boolean::class.javaPrimitiveType)
                .invoke(null, BuildConfig.DEBUG)
        }
        Notifier.init(applicationContext)
        if (Build.VERSION.SDK_INT >= 33) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        val client = SupabaseClient(applicationContext)
        setContent { App(client) }
    }

    override fun onStart() { super.onStart(); AppState.foreground = true }
    override fun onStop() { super.onStop(); AppState.foreground = false }
}

@Composable
private fun App(client: SupabaseClient) {
    var screen by remember { mutableStateOf<Screen>(Screen.Home) }
    BackHandler(enabled = screen != Screen.Home) { screen = Screen.Home }

    // القوائم والإعدادات: لافندر فاتح · داخل اللعبة: «نوار» داكن بأجواء المراحل
    val dark = screen is Screen.Game || screen is Screen.LabGame
    val view = LocalView.current
    SideEffect {
        val window = view.context.findActivity()?.window
        if (window != null) {
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = !dark
            controller.isAppearanceLightNavigationBars = !dark
        }
    }

    MafiaTheme(dark = dark) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize().background(backdropBrush(dark, Atmosphere.phase)).safeDrawingPadding()) {
                Box(Modifier.weight(1f).padding(16.dp)) {
                    when (val s = screen) {
                        Screen.Home -> HomeScreen(client, onOpenRoom = { screen = Screen.Lobby(it) },
                            onDebug = { screen = Screen.Debug }, onAccount = { screen = Screen.Account },
                            onRules = { screen = Screen.Rules }, onStats = { screen = Screen.Stats },
                            onAdmin = { screen = Screen.Admin })
                        Screen.Debug -> ConnectionScreen(client, onBack = { screen = Screen.Home })
                        Screen.Account -> AccountScreen(client, onBack = { screen = Screen.Home })
                        Screen.Rules -> RulesScreen(onBack = { screen = Screen.Home })
                        Screen.Stats -> StatsScreen(client, onBack = { screen = Screen.Home })
                        Screen.Admin -> AdminScreen(client, onLab = { screen = Screen.Lab }, onBack = { screen = Screen.Home })
                        Screen.Lab -> LabHomeScreen(client, onOpen = { screen = Screen.LabGame(it) }, onBack = { screen = Screen.Admin })
                        is Screen.LabGame -> LabGameScreen(client, s.gameId, onBack = { screen = Screen.Lab })
                        is Screen.Lobby -> LobbyScreen(client, s.roomId, onBack = { screen = Screen.Home },
                            onGame = { screen = Screen.Game(it, s.roomId) })
                        is Screen.Game -> GameScreen(client, s.gameId, onExit = { screen = Screen.Home })
                    }
                }
                AdBanner(Modifier.fillMaxWidth())
            }
        }
    }
}
