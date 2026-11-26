package com.wainhq.wain.store

import com.wainhq.wain.model.BotRank
import com.wainhq.wain.model.HomeEntry
import com.wainhq.wain.model.HomeSection
import com.wainhq.wain.model.MachineDot
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.model.atLimit
import com.wainhq.wain.model.headline
import com.wainhq.wain.model.prStatus
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.ui.health
import com.wainhq.wain.wire.AgentEvent
import com.wainhq.wain.wire.Bot
import com.wainhq.wain.wire.parseDate

// What the four tabs read off the store, over the machines the Machines pick shows.

/** One thing on Home. */
sealed interface HomeItem {
    /** A permission or question card, answered in place. */
    data class Ask(val key: SessionKey, val event: AgentEvent) : HomeItem
    /** A PR ready to merge, merged from the card; `chat` is the bot's whose task it is. */
    data class Merge(val stall: Stall, val chat: SessionKey?) : HomeItem
    /** A bot's task gone quiet on the reader, from its stall card. */
    data class Idle(val stall: Stall, val chat: SessionKey) : HomeItem
    data class Task(val key: SessionKey) : HomeItem
    data class BotRow(val server: String, val bot: Bot, val chat: SessionKey?) : HomeItem
}

/** Home's sections. `dismissed` is the stall card's own list, so a stall waved off there stays off here. */
fun Store.home(now: Long, dismissed: Set<String>): Map<HomeSection, List<HomeEntry<HomeItem>>> {
    val on = shown.map { it.id }.toSet()
    val entries = mutableListOf<HomeEntry<HomeItem>>()
    val chats = mutableMapOf<SessionKey, String>()
    for ((server, bot) in shownBots) {
        val owner = "bot:$server/${bot.id}"
        val chat = botChat(server, bot)
        chat.forEach { chats[it] = owner }
        val last = chat.lastOrNull()
        val tasks = botTasks(chat)
        for (s in (judgedStalls(server, bot.id, tasks, now) ?: stalls(tasks, now)).filter { it.id !in dismissed }) {
            val at = parseDate(s.item.modified) ?: 0L
            when {
                s.ready -> entries += HomeEntry(s.task.toString(), HomeSection.Waiting, at, HomeItem.Merge(s, last))
                last != null -> entries += HomeEntry(s.task.toString(), HomeSection.Waiting, at, HomeItem.Idle(s, last))
            }
        }
        val item = last?.let { items[it] } ?: continue
        val at = parseDate(item.modified) ?: 0L
        when {
            item.busy -> entries += HomeEntry(owner, HomeSection.Working, at, HomeItem.BotRow(server, bot, last))
            item.status == "completed" -> entries += HomeEntry(owner, HomeSection.Fresh, at, HomeItem.BotRow(server, bot, last))
        }
    }
    for ((key, list) in asks) {
        if (key.server !in on) continue
        val moved = parseDate(items[key]?.modified) ?: 0L
        for (e in list) entries += HomeEntry(chats[key] ?: key.toString(), HomeSection.Waiting, parseDate(e.ts) ?: moved, HomeItem.Ask(key, e))
    }
    val hidden = covered
    for ((key, item) in items) {
        // A bot's task is under its bot; its chat is the bot's row.
        if (key.server !in on || key.server in hidden || item.archived == true || item.hidden == true || key in chats || item.routineRun != null) continue
        val at = parseDate(item.modified) ?: 0L
        val mark = prMark(key, item)
        if (!item.busy && mark != null && prStatus(mark) == "ready") entries += HomeEntry(key.toString(), HomeSection.Waiting, at, HomeItem.Merge(Stall(key, item, mark, true), null))
        when {
            item.busy -> entries += HomeEntry(key.toString(), HomeSection.Working, at, HomeItem.Task(key))
            item.status == "completed" -> entries += HomeEntry(key.toString(), HomeSection.Fresh, at, HomeItem.Task(key))
        }
    }
    return com.wainhq.wain.model.homeSections(entries)
}

/** A bot's place in the roster. */
fun Store.botRank(server: String, bot: Bot): BotRank {
    val chat = botChat(server, bot)
    val item = chat.lastOrNull()?.let { items[it] }
    val waiting = chat.any { isAsking(it) } || hiddenAsks(botTasks(chat)).isNotEmpty()
    return BotRank(waiting, item?.status == "completed", item?.busy == true, parseDate(item?.modified) ?: 0L)
}

/** The Bots tab's red badge: bots on the shown machines with a reply the reader hasn't seen. */
val Store.unreadBots: Int
    get() = shownBots.count { (s, b) -> botChat(s, b).lastOrNull()?.let { items[it]?.status == "completed" } == true }

/** One machine's dot: yellow where it needs the reader, grey once it is out of reach, green otherwise. */
fun Store.machineDot(id: String): MachineDot {
    val h = health(id)
    return when {
        h?.needsYou == true -> MachineDot.NeedsYou
        serverState[id] != ConnState.Connected && h != null -> MachineDot.Unreachable
        else -> MachineDot.Fine
    }
}

/** Every reading on the shown machines. */
val Store.shownUsage get() = shown.flatMap { usage[it.id].orEmpty() }

/** Readings at their limit on any live machine, for the Machines sheet's Usage row. */
val Store.atLimit: Int get() = live.sumOf { s -> usage[s.id].orEmpty().count { it.atLimit } }

/** The five-hour figure the composer's ring shows for a session: its own machine's, for its own agent. */
fun Store.usagePercent(key: SessionKey, harness: String): Double? =
    usage[key.server]?.firstOrNull { it.harness == harness }?.headline?.usedPercent
