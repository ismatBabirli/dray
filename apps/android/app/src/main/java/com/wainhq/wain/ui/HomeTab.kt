package com.wainhq.wain.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.HomeEntry
import com.wainhq.wain.model.HomeSection
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.model.previewLine
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.HomeItem
import com.wainhq.wain.store.Stall
import com.wainhq.wain.store.Store
import com.wainhq.wain.wire.Bot
import com.wainhq.wain.wire.parseDate
import com.wainhq.wain.wire.shortAge

/**
 * Home: what waits on the reader, what is working, and what is new since they looked, across
 * the shown machines. Each section hides when empty; all empty is All clear.
 */
@Composable
fun HomeTab(home: Map<HomeSection, List<HomeEntry<HomeItem>>>, list: LazyListState, nav: TabNav, sheets: TabSheets, machineButton: Boolean) {
    val store = LocalStore.current
    Column(Modifier.fillMaxSize()) {
        TabBar("Home", sheets, machineButton)
        UsageChips(sheets.usage)
        val connected = store.shown.any { store.serverState[it.id] == ConnState.Connected }
        if (home.isEmpty() && store.shown.none { store.health(it.id) != null }) {
            if (store.servers.isEmpty()) FirstRun(nav)
            else if (connected) EmptyScreen(EmptyArtKind.Tasks, "All clear", "Nothing waits on you, and nothing is running.")
            else EmptyScreen(EmptyArtKind.Connecting, "Connecting", store.shown.joinToString(", ") { it.name })
            return
        }
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (s in store.shown) {
                val h = store.health(s.id) ?: continue
                item("health-${s.id}") { HealthBanner(h, retry = { store.retry(s.id) }, fix = { nav.openSettings(s.id) }) }
            }
            home[HomeSection.Waiting]?.let { rows ->
                item("waiting") { SectionHeading("Waiting on you", rows.size, needsYou = true) }
                for (e in rows) item(key(e)) { WaitingCard(e.value, nav) }
            }
            home[HomeSection.Working]?.let { rows ->
                item("working") { SectionHeading("Working", modifier = Modifier.padding(top = 12.dp)) }
                for (e in rows) item(key(e)) { HomeRow(e.value, nav) }
            }
            home[HomeSection.Fresh]?.let { rows ->
                item("fresh") { SectionHeading("New since you looked", modifier = Modifier.padding(top = 8.dp)) }
                for (e in rows) item(key(e)) { HomeRow(e.value, nav) }
            }
        }
    }
}

private fun key(e: HomeEntry<HomeItem>): String = when (val v = e.value) {
    is HomeItem.Ask -> "ask-${v.event.id}"
    is HomeItem.Merge -> "merge-${v.stall.task}"
    is HomeItem.Idle -> "idle-${v.stall.id}"
    is HomeItem.Task -> "task-${v.key}"
    is HomeItem.BotRow -> "bot-${v.server}-${v.bot.id}"
}

/** No machine paired yet: the whole tab is the way to pair one. */
@Composable
private fun FirstRun(nav: TabNav) {
    EmptyScreen(EmptyArtKind.Connect, "Pair a machine", "Your agents run on a Mac or a server. Pair one to start.") {
        CapsuleButton("Scan the code", light = true) { nav.addServer(true) }
        CapsuleButton("Enter an address") { nav.addServer(false) }
        Text("On your Mac: Settings › Servers › Pair a phone. On a server, run wain server pair.",
            Modifier.padding(top = 12.dp), style = Wain.Font.footnote.copy(color = Wain.tertiary), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

private fun Store.where(key: SessionKey): String =
    listOfNotNull(items[key]?.project?.takeIf { it.isNotEmpty() }, parseDate(items[key]?.modified)?.let { shortAge(it) }).joinToString(" · ")

/** A card on Home: a question or permission answered in place, a PR to merge, a bot task gone quiet. */
@Composable
private fun WaitingCard(item: HomeItem, nav: TabNav) {
    val store = LocalStore.current
    val shape = RoundedCornerShape(12.dp)
    when (item) {
        is HomeItem.Ask -> Column(Modifier.fillMaxWidth().clip(shape).background(Wain.card).padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().clickable { nav.openSession(item.key) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(Wain.mark))
                Text(store.bot(item.key)?.name ?: store.items[item.key]?.title?.ifEmpty { "Untitled" } ?: "Task", Modifier.weight(1f),
                    style = CardTitle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(store.where(item.key), style = Small)
            }
            AskCard(item.key, item.event)
        }
        is HomeItem.Merge -> StallCard(item.stall, item.chat, nav, merge = true)
        is HomeItem.Idle -> StallCard(item.stall, item.chat, nav, merge = false)
        else -> HomeRow(item, nav)
    }
}

@Composable
private fun StallCard(s: Stall, chat: SessionKey?, nav: TabNav, merge: Boolean) {
    val store = LocalStore.current
    val bot = chat?.let { store.bot(it) }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Wain.card)
            .clickable { if (!merge && chat != null) nav.openSession(chat) else if (!s.offline) nav.openSession(s.task) }
            .padding(start = 14.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (bot != null) BotFace(bot, 32.dp)
        else Box(Modifier.size(32.dp).clip(CircleShape).background(Wain.raised), contentAlignment = Alignment.Center) { s.pr?.let { PrGlyph(it, 15.dp) } }
        Column(Modifier.weight(1f)) {
            Text(s.item.title.ifEmpty { "Untitled" }, style = CardTitle, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val need = s.judged?.need ?: s.item.need?.text
            Text(
                when {
                    merge -> "#${s.pr?.number} · " + if (s.checking) "Checking…" else "Ready to merge"
                    need != null -> need
                    else -> "Waiting for your reply"
                },
                style = Wain.Font.footnote.copy(color = Wain.secondary), maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
        val pr = s.pr
        if (merge && pr != null && !s.checking) {
            val repo = s.judged?.repo
            when {
                s.offline && repo != null && chat != null -> MergeTaskButton(chat.server, s.task.id, "github:$repo", pr.number, pr.headRefName)
                !s.offline -> MergeTaskButton(s.task.server, s.task.id, s.item.projectPath, pr.number, pr.headRefName)
            }
        }
    }
}

/** A row under Working or New since you looked: a task with its orb or mark, or a bot with its face and newest line. */
@Composable
private fun HomeRow(item: HomeItem, nav: TabNav) {
    val store = LocalStore.current
    when (item) {
        is HomeItem.Task -> {
            val row = store.items[item.key] ?: return
            Row(
                Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(Wain.Radius.md)).clickable { nav.openSession(item.key) }.padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Box(Modifier.width(32.dp), contentAlignment = Alignment.Center) {
                    if (row.busy) Orb(OrbKind.Working, label = "Working")
                    else Box(Modifier.size(8.dp).clip(CircleShape).background(Wain.add))
                }
                Text(row.title.ifEmpty { "Untitled" }, Modifier.weight(1f), style = Wain.Font.body.copy(lineHeight = 24.sp,
                    fontWeight = if (row.busy) FontWeight.Normal else FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
                parseDate(row.modified)?.let { Text(shortAge(it), style = Small) }
            }
        }
        is HomeItem.BotRow -> BotHomeRow(item.server, item.bot, item.chat, nav)
        else -> {}
    }
}

@Composable
private fun BotHomeRow(server: String, bot: Bot, chat: SessionKey?, nav: TabNav) {
    val store = LocalStore.current
    val row = chat?.let { store.items[it] }
    val preview = chat?.let { store.botState.previews[it] }
    val unread = row?.status == "completed"
    Row(
        Modifier.fillMaxWidth().height(64.dp).clip(RoundedCornerShape(Wain.Radius.md)).clickable { store.openBot(nav, server, bot) }.padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box {
            BotFace(bot, 32.dp)
            if (unread && (preview?.replies ?: 0) > 0) UnreadCount(preview!!.replies, Modifier.align(Alignment.TopEnd).offset(x = 7.dp, y = (-7).dp))
        }
        Column(Modifier.weight(1f)) {
            Text(bot.name, style = Wain.Font.body.copy(fontWeight = if (unread) FontWeight.Bold else FontWeight.Medium), maxLines = 1)
            if (row?.busy == true) Box(Modifier.heightIn(min = 20.dp), contentAlignment = Alignment.CenterStart) { TypingDots() }
            else {
                val line = preview?.takeIf { it.plain }?.text ?: previewLine(preview?.text ?: "")
                if (line.isNotEmpty()) Text(line, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        parseDate(row?.modified)?.let { Text(shortAge(it), style = Small) }
    }
}

/** The red count on a face, ringed in the page's colour. */
@Composable
fun UnreadCount(n: Int, modifier: Modifier = Modifier) {
    Box(modifier.clip(CircleShape).background(Wain.page).padding(2.dp).heightIn(min = 16.dp).clip(CircleShape).background(Wain.unread).padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center) {
        Text("$n", style = Wain.Font.footnote.copy(fontSize = 11.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold, color = Wain.onColor))
    }
}

private val CardTitle get() = Wain.Font.subhead.copy(fontWeight = FontWeight.Medium)
private val Small get() = Wain.Font.footnote.copy(fontSize = 12.sp, lineHeight = 16.sp, color = Wain.tertiary)
