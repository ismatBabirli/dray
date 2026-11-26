package com.wainhq.wain

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.net.PairLink
import com.wainhq.wain.push.Alerts
import com.wainhq.wain.push.Push
import com.wainhq.wain.push.PushAlert
import com.wainhq.wain.wire.str
import com.wainhq.wain.wire.wireJson
import kotlinx.serialization.json.JsonObject
import com.wainhq.wain.ui.App
import com.wainhq.wain.ui.Wain
import com.wainhq.wain.ui.WainTheme
import com.wainhq.wain.ui.LocalStore

class MainActivity : ComponentActivity() {
    /** A `wain://connect` link the app was opened with, waiting for the add screen to take it. */
    private var incoming by mutableStateOf<PairLink?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        // Read once: a change of system theme recreates the activity, as nothing here handles `uiMode`.
        Wain.dark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) != Configuration.UI_MODE_NIGHT_NO
        val bars = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
        enableEdgeToEdge(bars, bars)
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) take(intent)
        val store = (application as WainApplication).store
        setContent {
            WainTheme {
                CompositionLocalProvider(LocalStore provides store) {
                    App(incoming) { incoming = null }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        take(intent)
    }

    private fun take(intent: Intent?) {
        intent?.dataString?.let { PairLink.parse(it) }?.let { incoming = it }
        // A tapped alert opens its chat.
        if (intent?.action == Alerts.OPEN) {
            val server = intent.getStringExtra(Alerts.EXTRA_SERVER)
            val chat = intent.getStringExtra(Alerts.EXTRA_CHAT)
            if (server != null && chat != null) Push.opening = SessionKey(server, chat)
        }
        if (BuildConfig.DEBUG) debugPush(intent)
    }

    /**
     * A debug build's stand-ins for what FCM can't do here: `pushRelay` points sealing at a local
     * relay, and `pushPayload` is an FCM message's `data` as the relay sent it, drawn in 3s as
     * `PushService` would, so the app can be sent to the background first.
     */
    private fun debugPush(intent: Intent?) {
        intent?.getStringExtra("pushRelay")?.let { Push.useRelay(it) }
        val payload = intent?.getStringExtra("pushPayload") ?: return
        val data = runCatching {
            (wireJson.parseToJsonElement(payload) as JsonObject).mapValues { (_, v) -> v.str ?: v.toString() }
        }.getOrNull() ?: return
        val alert = PushAlert.parse(data) ?: return
        android.os.Handler(mainLooper).postDelayed({ Alerts.show(applicationContext, alert) }, 3000)
    }
}
