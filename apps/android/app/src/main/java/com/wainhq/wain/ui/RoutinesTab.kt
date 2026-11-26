package com.wainhq.wain.ui

import android.text.format.DateFormat
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.nextRunLabel
import com.wainhq.wain.model.routineOrder
import com.wainhq.wain.model.scheduleLabel
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.Store
import com.wainhq.wain.store.botChat
import com.wainhq.wain.store.shownBots
import com.wainhq.wain.wire.Bot
import com.wainhq.wain.wire.Routine
import com.wainhq.wain.wire.decodeList
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.jsonOf
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Date

/** A routine with the bot it belongs to. */
private data class Owned(val server: String, val bot: Bot, val routine: Routine)

/**
 * Every routine of every bot on the shown machines, soonest first and paused last. The switch
 * pauses one, a long press deletes it, a tap opens its bot's chat. Making or changing one is the
 * bot's to do, since the wire has list, pause and delete only.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun RoutinesTab(list: LazyListState, nav: TabNav, sheets: TabSheets, machineButton: Boolean) {
    val store = LocalStore.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    // Per bot, so a bot whose read fails keeps what it last said.
    val read = remember { mutableStateMapOf<String, List<Routine>>() }
    var error by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf<Owned?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val bots = store.shownBots
    val up = bots.filter { (s, _) -> store.serverState[s] == ConnState.Connected }

    // On every `routines_changed`, on a machine coming up, and once a minute, as the desktop does.
    LaunchedEffect(store.routinesRevision, up.map { it.second.id }) {
        while (true) {
            for ((server, bot) in up) {
                runCatching { decodeList<Routine>(store.call(server, "list_routines", jsonOf("botId" to bot.id))) }
                    .onSuccess { read["$server/${bot.id}"] = it }
            }
            now = System.currentTimeMillis()
            delay(60_000)
        }
    }

    val rows = routineOrder(bots.flatMap { (s, b) -> read["$s/${b.id}"].orEmpty().map { Owned(s, b, it) } }) { it.routine }
    val asked = bots.firstOrNull { it.second.name.equals("Wain", ignoreCase = true) } ?: bots.firstOrNull()
    val time = { ms: Long -> DateFormat.getTimeFormat(context).format(Date(ms)) }
    val day = { ms: Long -> DateFormat.format("MMM d", ms).toString() }

    fun act(server: String, cmd: String, args: Map<String, Any?>, fail: String, undo: () -> Unit = {}) = scope.launch {
        runCatching { store.call(server, cmd, jsonOf(*args.toList().toTypedArray())) }
            .onSuccess { error = null; store.routinesRevision++ }
            .onFailure { error = "$fail. ${sentence(it.message ?: "The server didn't answer.")}"; undo() }
    }

    fun setPaused(o: Owned, paused: Boolean) {
        val key = "${o.server}/${o.bot.id}"
        // The switch moves at once and goes back where the server refused.
        val set = { to: Boolean -> read[key] = read[key].orEmpty().map { if (it.id == o.routine.id) it.copy(paused = to) else it } }
        set(paused)
        act(o.server, "set_routine_paused", mapOf("id" to o.routine.id, "paused" to paused), if (paused) "Couldn't pause it" else "Couldn't resume it") { set(o.routine.paused) }
    }

    Column(Modifier.fillMaxSize()) {
        TabBar("Routines", sheets, machineButton)
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = 24.dp)) {
            item("intro") {
                Text(
                    if (rows.isEmpty()) "No routines yet. A routine is a check a bot runs on a schedule; a run that finds something tells its bot, and the bot tells you."
                    else "Checks your bots run on a schedule. A run that finds something tells its bot, and the bot tells you.",
                    Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp),
                    style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.secondary),
                )
            }
            error?.let { item("error") { Text(it, Modifier.padding(horizontal = 16.dp, vertical = 4.dp), style = Wain.Font.footnote.copy(color = Wain.destructive)) } }
            items(rows, key = { "${it.server}/${it.routine.id}" }) { o ->
                val r = o.routine
                Row(
                    Modifier.fillMaxWidth().height(72.dp)
                        .combinedClickable(onClick = { store.openBot(nav, o.server, o.bot) }, onLongClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            deleting = o
                        })
                        .semantics { contentDescription = "${r.name}, ${scheduleLabel(r)}" }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    BotFace(o.bot, 32.dp)
                    Column(Modifier.weight(1f)) {
                        Text(r.name, style = Wain.Font.body.copy(lineHeight = 24.sp, color = if (r.paused) Wain.secondary else Wain.text),
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${scheduleLabel(r)} · ${nextRunLabel(r, now, time, day)}", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp,
                            color = Wain.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Switch(
                        !r.paused, { on -> haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); setPaused(o, !on) },
                        enabled = store.serverState[o.server] == ConnState.Connected,
                        colors = SwitchDefaults.colors(checkedTrackColor = Wain.add, checkedThumbColor = Wain.onColor, checkedBorderColor = Wain.add,
                            uncheckedTrackColor = Wain.page, uncheckedThumbColor = Wain.tertiary, uncheckedBorderColor = Wain.tertiary),
                        modifier = Modifier.semantics { contentDescription = if (r.paused) "Turn on ${r.name}" else "Turn off ${r.name}" },
                    )
                }
            }
            item("foot") {
                Column(Modifier.padding(top = 8.dp)) {
                    if (rows.isNotEmpty()) HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = Wain.hairline)
                    Text(
                        "To add or change one, ask the bot in its chat, for example “check the deploy every morning at nine”.",
                        Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 12.dp),
                        style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.secondary),
                    )
                    asked?.let { (server, bot) -> AskChip(store, nav, server, bot) }
                }
            }
        }
    }
    deleting?.let { o ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            containerColor = Wain.card,
            title = { Text("Delete ${o.routine.name}?", style = Wain.Font.headline) },
            text = { Text("${o.bot.name} stops running it. Ask the bot to set it up again.", style = Wain.Font.subhead.copy(color = Wain.secondary)) },
            confirmButton = {
                TextButton({
                    deleting = null
                    val key = "${o.server}/${o.bot.id}"
                    read[key] = read[key].orEmpty().filter { it.id != o.routine.id }
                    act(o.server, "delete_routine", mapOf("id" to o.routine.id), "Couldn't delete it")
                }) { Text("Delete", color = Wain.destructive) }
            },
            dismissButton = { TextButton({ deleting = null }) { Text("Cancel", color = Wain.secondary) } },
        )
    }
}

/** "Ask Wain": the bot's chat with its field focused, where a routine is made. */
@Composable
private fun AskChip(store: Store, nav: TabNav, server: String, bot: Bot) {
    Row(
        Modifier.padding(start = 16.dp).height(40.dp).clip(CircleShape).background(Wain.raised).clickable {
            ComposerFocus.key = store.botChat(server, bot).lastOrNull() ?: botStartDraft(server, bot.id)
            store.openBot(nav, server, bot)
        }.padding(start = 8.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        BotFace(bot, 24.dp)
        Text("Ask ${bot.name}", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium))
    }
}
