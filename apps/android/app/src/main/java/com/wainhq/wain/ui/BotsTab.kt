package com.wainhq.wain.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.wainhq.wain.model.botOrder
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.botChat
import com.wainhq.wain.store.botRank
import com.wainhq.wain.store.shownBots

/** The roster: every bot on the shown machines, waiting ones first. + makes a new one. */
@Composable
fun BotsTab(list: LazyListState, nav: TabNav, sheets: TabSheets, machineButton: Boolean) {
    val store = LocalStore.current
    val connected = store.shown.any { store.serverState[it.id] == ConnState.Connected }
    val bots = botOrder(store.shownBots) { (s, b) -> store.botRank(s, b) }
    Column(Modifier.fillMaxSize()) {
        TabBar("Bots", sheets, machineButton) {
            if (connected) BarAction("New bot", sheets.newBot) { plusGlyph(Wain.text) }
        }
        if (bots.isEmpty()) {
            val where = store.shown.singleOrNull()?.name?.let { "$it has none yet." } ?: "None of your machines has one yet."
            EmptyScreen({ BotArt() }, "No bots yet", "A bot is one chat that hands work to tasks and tells you when they're done. $where") {
                if (connected) LightButton("New bot", leading = { Glyph24(18.dp) { plusGlyph(Wain.onPrimary) } }, onClick = sheets.newBot)
            }
            return
        }
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(top = 4.dp, bottom = 24.dp)) {
            items(bots, key = { (s, b) -> "$s/${b.id}" }) { (server, bot) ->
                BotListRow(server, bot, store.botChat(server, bot).lastOrNull()) { store.openBot(nav, server, bot) }
            }
        }
    }
}

/** A bot's face inside two rings, the empty roster's drawing. */
@Composable
private fun BotArt() {
    Box(Modifier.size(180.dp), contentAlignment = Alignment.Center) {
        val ring = Wain.hairline
        Canvas(Modifier.size(180.dp)) {
            drawCircle(ring, size.minDimension / 2 - 1, style = Stroke(1.dp.toPx()))
            drawCircle(ring, size.minDimension / 3, style = Stroke(1.dp.toPx()))
        }
        BotFace("wain", size = 64.dp)
    }
}

fun androidx.compose.ui.graphics.drawscope.DrawScope.plusGlyph(c: androidx.compose.ui.graphics.Color) {
    val w = 2f
    drawLine(c, androidx.compose.ui.geometry.Offset(12f, 5f), androidx.compose.ui.geometry.Offset(12f, 19f), w, androidx.compose.ui.graphics.StrokeCap.Round)
    drawLine(c, androidx.compose.ui.geometry.Offset(5f, 12f), androidx.compose.ui.geometry.Offset(19f, 12f), w, androidx.compose.ui.graphics.StrokeCap.Round)
}
