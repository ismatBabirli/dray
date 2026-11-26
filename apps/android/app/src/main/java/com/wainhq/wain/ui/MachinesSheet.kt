package com.wainhq.wain.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.MachineDot
import com.wainhq.wain.model.plural
import com.wainhq.wain.model.usageChips
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.Server
import com.wainhq.wain.store.atLimit
import com.wainhq.wain.store.botChat
import com.wainhq.wain.store.machineDot
import com.wainhq.wain.store.shownUsage

/**
 * Machines, where the gear was: which machines every tab shows (all, or exactly one), each
 * with its health and Retry; then Usage, Pair a machine and Settings.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MachinesSheet(nav: TabNav, openUsage: () -> Unit, dismiss: () -> Unit) {
    val store = LocalStore.current
    val picked = store.shownMachine
    ModalBottomSheet(dismiss, containerColor = Wain.card, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 32.dp)) {
            Text("Machines", Modifier.padding(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 12.dp), style = TitleStyle())
            Text("Show tasks and bots from", Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
                style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.secondary))
            Choice(picked == null, "All machines", { Text("${store.live.size} paired", style = Detail) }) { store.showMachine(null); dismiss() }
            for (s in store.live) MachineChoice(s, picked == s.id, nav) { store.showMachine(s.id); dismiss() }
            HorizontalDivider(color = Wain.hairline)
            val worst = usageChips(store.shownUsage).firstOrNull()
            val spent = store.atLimit
            Action("Usage", { Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { UsageRing(worst?.percent ?: 0.0, worst?.limited == true, 22.dp, Wain.connector) } }, openUsage) {
                if (spent > 0) Text("$spent at limit", style = Detail.copy(color = Wain.destructive))
            }
            Action("Pair a machine", { Glyph24 { qrGlyph(Wain.text) } }, { dismiss(); nav.addServer(false) })
            Action("Settings", { Glyph24 { gearGlyph(Wain.text) } }, { dismiss(); nav.openSettings(null) })
            Text("Turning a machine off, or removing it, lives in Settings › Servers. Its tasks keep running there.",
                Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = Wain.Font.footnote.copy(color = Wain.tertiary))
        }
    }
}

private val Detail get() = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.secondary)

@Composable
private fun Choice(picked: Boolean, title: String, detail: @Composable () -> Unit, trailing: @Composable () -> Unit = {}, pick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(64.dp).selectable(picked, role = Role.RadioButton, onClick = pick).padding(start = 16.dp, end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        RadioButton(picked, null, Modifier.size(40.dp), colors = RadioButtonDefaults.colors(selectedColor = Wain.text, unselectedColor = Wain.secondary))
        Column(Modifier.weight(1f)) {
            Text(title, style = Wain.Font.body.copy(lineHeight = 24.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            detail()
        }
        trailing()
    }
}

@Composable
private fun MachineChoice(s: Server, picked: Boolean, nav: TabNav, pick: () -> Unit) {
    val store = LocalStore.current
    val connected = store.serverState[s.id] == ConnState.Connected
    val health = store.health(s.id)
    val dot = when (store.machineDot(s.id)) {
        MachineDot.NeedsYou -> Wain.mark
        MachineDot.Unreachable -> Wain.tertiary
        MachineDot.Fine -> if (connected) Wain.add else Wain.tertiary
    }
    Choice(picked, s.name, {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
            val line = if (connected && health == null) {
                val chats = store.bots[s.id].orEmpty().flatMap { store.botChat(s.id, it) }.toSet()
                val tasks = store.items.count { (k, v) -> k.server == s.id && k !in chats && v.archived != true && v.hidden != true && v.routineRun == null }
                val bots = store.bots[s.id].orEmpty().size
                listOfNotNull(
                    "This Mac".takeIf { store.connection(s.id)?.welcome?.macApp == true },
                    plural(tasks, "task"),
                    plural(bots, "bot").takeIf { bots > 0 },
                ).joinToString(" · ")
            } else health?.let { h -> h.until?.let { "${h.title} · ${countdown(it).replaceFirstChar { c -> c.lowercase() }}" } ?: h.title } ?: store.stateLabel(s.id)
            Text(line, style = Detail, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }, trailing = {
        health?.action?.let { a ->
            Text(if (a == Health.Action.Fix) "Fix" else "Retry",
                Modifier.clip(RoundedCornerShape(Wain.Radius.md)).clickable { if (a == Health.Action.Fix) nav.openSettings(s.id) else store.retry(s.id) }
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.link))
        }
    }, pick = pick)
}

@Composable
private fun Action(label: String, icon: @Composable () -> Unit, onClick: () -> Unit, trailing: @Composable () -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).clickable(onClick = onClick).padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        icon()
        Text(label, Modifier.weight(1f), style = Wain.Font.body.copy(lineHeight = 24.sp))
        trailing()
    }
}
