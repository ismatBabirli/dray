package com.wainhq.wain.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.HomeSection
import com.wainhq.wain.model.MachineDot
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.model.machineDot
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.botChat
import com.wainhq.wain.store.home
import com.wainhq.wain.store.machineDot
import com.wainhq.wain.store.unreadBots
import com.wainhq.wain.wire.Bot
import kotlinx.coroutines.delay

/** The four tabs, always all four, in this order. A tab never does an action. */
enum class Tab(val label: String) { Home("Home"), Bots("Bots"), Tasks("Tasks"), Routines("Routines") }

/** Where the tabs send the reader: pushes on the app's stack. */
class TabNav(
    val openSession: (SessionKey) -> Unit,
    val startBot: (server: String, botId: String) -> Unit,
    val openSettings: (String?) -> Unit,
    val addServer: (scan: Boolean) -> Unit,
    val openPulls: () -> Unit,
    val openIssues: () -> Unit,
)

/** What a tab can open over itself, all held by the scaffold. */
class TabSheets(val machines: () -> Unit, val usage: () -> Unit, val newBot: () -> Unit, val newTask: () -> Unit)

/** A bot's chat, or its first-message screen where it has none yet. */
fun com.wainhq.wain.store.Store.openBot(nav: TabNav, server: String, bot: Bot) {
    botChat(server, bot).lastOrNull()?.let(nav.openSession) ?: nav.startBot(server, bot.id)
}

/** The stall card's dismissals, shared with Home so a stall waved off stays off. */
fun dismissedStalls(context: Context): Set<String> =
    context.getSharedPreferences("bots", Context.MODE_PRIVATE).getString("dismissedStalls", "").orEmpty().split("\n").toSet()

/**
 * The app's root: the four tabs over a navigation bar on a phone; at 600dp and wider a
 * navigation rail with New task at its top, the tab's list beside `detail`.
 */
@Composable
fun TabsScreen(tab: Tab, pick: (Tab) -> Unit, nav: TabNav, wide: Boolean, detail: (@Composable () -> Unit)? = null) {
    val store = LocalStore.current
    val context = LocalContext.current
    var machines by remember { mutableStateOf(false) }
    var usage by remember { mutableStateOf(false) }
    var newTask by remember { mutableStateOf(false) }
    var newBot by remember { mutableStateOf(false) }
    // Stalls ripen with time alone, so Home looks again each minute.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(60_000); now = System.currentTimeMillis() } }
    val home = store.home(now, dismissedStalls(context))
    val waiting = home[HomeSection.Waiting]?.size ?: 0
    val unread = store.unreadBots
    val lists = Tab.entries.associateWith { rememberLazyListState() }
    val sheets = TabSheets({ machines = true }, { usage = true }, { newBot = true }, { newTask = true })
    val canStart = store.live.any { store.serverState[it.id] == ConnState.Connected }

    val content: @Composable () -> Unit = {
        val list = lists.getValue(tab)
        when (tab) {
            Tab.Home -> HomeTab(home, list, nav, sheets, machineButton = !wide)
            Tab.Bots -> BotsTab(list, nav, sheets, machineButton = !wide)
            Tab.Tasks -> ListScreen(list, nav, sheets, machineButton = !wide)
            Tab.Routines -> RoutinesTab(list, nav, sheets, machineButton = !wide)
        }
    }

    if (wide) {
        Row(Modifier.fillMaxSize().background(Wain.page)) {
            Rail(tab, pick, waiting, unread, sheets, if (canStart) ({ newTask = true }) else null)
            Box(Modifier.width(400.dp).fillMaxHeight()) { content() }
            VerticalDivider(color = Wain.hairline)
            Box(Modifier.weight(1f).fillMaxHeight()) { detail?.invoke() ?: NothingOpen() }
        }
    } else {
        Column(Modifier.fillMaxSize().background(Wain.page)) {
            Box(Modifier.weight(1f)) {
                content()
                if (canStart && (tab == Tab.Home || tab == Tab.Tasks)) {
                    val list = lists.getValue(tab)
                    val atTop by remember(list) { derivedStateOf { list.firstVisibleItemIndex == 0 } }
                    NewTaskFab(atTop, Modifier.align(Alignment.BottomEnd).padding(16.dp)) { newTask = true }
                }
            }
            Bar(tab, pick, waiting, unread)
        }
    }
    if (machines) MachinesSheet(nav, openUsage = { machines = false; usage = true }) { machines = false }
    if (usage) UsageSheet { usage = false }
    if (newTask) NewTaskSheet(nav.openSession) { newTask = false }
    if (newBot) BotSheet(editing = null, close = { newBot = false }, started = nav.openSession)
}

/** The tablet's detail with nothing picked. */
@Composable
private fun NothingOpen() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Pick a task or a bot.", style = Wain.Font.subhead.copy(color = Wain.tertiary))
    }
}

@Composable
private fun TabIcon(tab: Tab, picked: Boolean) {
    val ink = if (picked) Wain.text else Wain.secondary
    Glyph24 {
        when (tab) {
            Tab.Home -> homeGlyph(ink, picked)
            Tab.Bots -> botsGlyph(ink, picked, Wain.tile)
            Tab.Tasks -> tasksGlyph(ink, picked)
            Tab.Routines -> routinesGlyph(ink, picked)
        }
    }
}

@Composable
private fun TabLabel(tab: Tab, picked: Boolean) {
    Text(tab.label, style = Wain.Font.footnote.copy(fontSize = 12.sp, lineHeight = 16.sp, letterSpacing = 0.04.em,
        fontWeight = if (picked) FontWeight.Bold else FontWeight.Medium, color = if (picked) Wain.text else Wain.secondary))
}

/** Yellow counts what waits on the reader, red the bots with unread replies. */
@Composable
private fun TabBadge(tab: Tab, waiting: Int, unread: Int, content: @Composable () -> Unit) {
    val (count, fill, ink) = when (tab) {
        Tab.Home -> Triple(waiting, Wain.accent, Color(0xFF171717))
        Tab.Bots -> Triple(unread, Wain.unread, Wain.onColor)
        else -> Triple(0, Color.Transparent, Color.Transparent)
    }
    BadgedBox(badge = {
        if (count > 0) Badge(containerColor = fill, contentColor = ink) {
            Text("$count", style = Wain.Font.footnote.copy(fontSize = 11.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold, color = ink))
        }
    }) { content() }
}

@Composable
private fun Bar(tab: Tab, pick: (Tab) -> Unit, waiting: Int, unread: Int) {
    NavigationBar(containerColor = Wain.card, tonalElevation = 0.dp) {
        for (t in Tab.entries) {
            val picked = t == tab
            NavigationBarItem(
                picked, { pick(t) },
                icon = { TabBadge(t, waiting, unread) { TabIcon(t, picked) } },
                label = { TabLabel(t, picked) },
                colors = NavigationBarItemDefaults.colors(indicatorColor = Wain.tile),
            )
        }
    }
}

@Composable
private fun Rail(tab: Tab, pick: (Tab) -> Unit, waiting: Int, unread: Int, sheets: TabSheets, newTask: (() -> Unit)?) {
    NavigationRail(
        Modifier.width(96.dp),
        containerColor = Wain.card,
        header = {
            Column(Modifier.statusBarsPadding().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                MachineButton(sheets.machines, ring = Wain.card)
                newTask?.let {
                    FloatingActionButton(it, containerColor = Wain.primary, contentColor = Wain.onPrimary, shape = RoundedCornerShape(16.dp),
                        elevation = FloatingActionButtonDefaults.elevation(2.dp), modifier = Modifier.semantics { contentDescription = "New task" }) {
                        Glyph24 { pencilGlyph(Wain.onPrimary) }
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        },
    ) {
        for (t in Tab.entries) {
            val picked = t == tab
            NavigationRailItem(
                picked, { pick(t) },
                icon = { TabBadge(t, waiting, unread) { TabIcon(t, picked) } },
                label = { TabLabel(t, picked) },
                colors = NavigationRailItemDefaults.colors(indicatorColor = Wain.tile),
            )
        }
    }
}

/** New task, the screen's one main action: extended at the top of the list, a square once it scrolls. */
@Composable
private fun NewTaskFab(expanded: Boolean, modifier: Modifier, onClick: () -> Unit) {
    ExtendedFloatingActionButton(
        text = { Text("New task", style = Wain.Font.body.copy(lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.onPrimary)) },
        icon = { Glyph24 { pencilGlyph(Wain.onPrimary) } },
        onClick = onClick,
        modifier = modifier,
        expanded = expanded,
        shape = RoundedCornerShape(16.dp),
        containerColor = Wain.primary,
        contentColor = Wain.onPrimary,
    )
}

/**
 * Every tab's top bar: the machine button, the title — a menu on Tasks — and that tab's actions.
 * On a tablet the rail holds the machine button.
 */
@Composable
fun TabBar(title: String, sheets: TabSheets, machineButton: Boolean, menu: (@Composable () -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().height(64.dp).padding(start = 4.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (machineButton) MachineButton(sheets.machines)
        Box(Modifier.weight(1f).padding(start = if (machineButton) 4.dp else 20.dp)) {
            menu?.invoke() ?: Text(title, style = TitleStyle())
        }
        actions()
    }
}

@Composable
fun TitleStyle() = Wain.Font.title.copy(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Normal)

/** The machines glyph with the worst of the shown machines as its dot; opens the Machines sheet. */
@Composable
fun MachineButton(open: () -> Unit, ring: Color = Wain.page) {
    val store = LocalStore.current
    val dot = machineDot(store.shown.map { store.machineDot(it.id) })
    Box(
        Modifier.size(48.dp).clip(CircleShape).clickable(onClickLabel = "Machines", onClick = open).semantics {
            contentDescription = "Machines" + when (dot) {
                MachineDot.NeedsYou -> ", one needs you"
                MachineDot.Unreachable -> ", one is out of reach"
                else -> ""
            }
        },
        contentAlignment = Alignment.Center,
    ) {
        Glyph24 { machinesGlyph(Wain.text) }
        dot?.let {
            val fill = when (it) { MachineDot.Fine -> Wain.add; MachineDot.NeedsYou -> Wain.mark; MachineDot.Unreachable -> Wain.tertiary }
            Box(Modifier.align(Alignment.BottomEnd).offset(x = (-7).dp, y = (-7).dp).size(13.dp).clip(CircleShape).background(ring).padding(2.dp).clip(CircleShape).background(fill))
        }
    }
}

/** A top bar's icon action, 48dp. */
@Composable
fun BarAction(label: String, onClick: () -> Unit, glyph: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit) {
    Box(Modifier.size(48.dp).clip(CircleShape).clickable(onClickLabel = label, onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Glyph24(22.dp) { glyph() }
    }
}

/** A section heading on Home: yellow for what waits on the reader, with its count. */
@Composable
fun SectionHeading(text: String, count: Int? = null, needsYou: Boolean = false, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(4.dp)) {
        Text(text, Modifier.weight(1f), style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium,
            letterSpacing = if (needsYou) 0.01.em else 0.em, color = if (needsYou) Wain.mark else Wain.secondary))
        count?.let { Text("$it", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.tertiary)) }
    }
}

/** A light capsule: an empty state's one action. */
@Composable
fun LightButton(label: String, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Row(
        Modifier.height(40.dp).clip(CircleShape).background(Wain.primary).clickable(onClick = onClick).padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        leading?.invoke()
        Text(label, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.onPrimary))
    }
}

/** An outlined chip, picked filled with a check: the Tasks tab's projects. */
@Composable
fun FilterPill(label: String, picked: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier.height(32.dp).clip(shape)
            .then(if (picked) Modifier.background(Wain.tile) else Modifier.border(1.dp, Wain.outline, shape))
            .clickable(onClick = onClick).padding(start = if (picked) 8.dp else 14.dp, end = if (picked) 12.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (picked) Glyph24(16.dp) { checkGlyph(Wain.text) }
        Text(label, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium,
            color = if (picked) Wain.text else Wain.secondary))
    }
}
