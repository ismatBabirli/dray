package com.wainhq.wain.model

// The tabs' shared rules (mobile-tabs-rules.md, restated by the iPhone app): Home's three
// sections, the Bots tab's order and the Machines button's dot.

enum class HomeSection { Waiting, Working, Fresh }

/**
 * One thing Home could draw: what it is (`value`), the task or bot it belongs to (`owner`),
 * where it goes and when it last moved.
 */
data class HomeEntry<T>(val owner: String, val section: HomeSection, val at: Long, val value: T)

/**
 * Home's sections, newest first in each. An owner keeps only its most urgent place: a task
 * waiting on the reader is never also under Working. Waiting keeps every entry, since a card
 * and a merge on one task are two things to do. Empty sections are absent.
 */
fun <T> homeSections(entries: List<HomeEntry<T>>): Map<HomeSection, List<HomeEntry<T>>> {
    val top = entries.groupBy { it.owner }.mapValues { (_, same) -> same.minOf { it.section.ordinal } }
    val kept = entries.filter { it.section.ordinal == top[it.owner] }
        .let { list -> list.filter { it.section == HomeSection.Waiting } + list.filter { it.section != HomeSection.Waiting }.sortedByDescending { it.at }.distinctBy { it.owner } }
    return kept.sortedByDescending { it.at }.groupBy { it.section }.toSortedMap()
}

/** Where a bot sits in the roster: waiting on the reader, unread, working, then the rest. */
data class BotRank(val waiting: Boolean, val unread: Boolean, val working: Boolean, val at: Long) {
    val tier: Int get() = when { waiting -> 0; unread -> 1; working -> 2; else -> 3 }
}

/** The roster's order: by tier, then the latest activity first. */
fun <T> botOrder(bots: List<T>, rank: (T) -> BotRank): List<T> =
    bots.sortedWith(compareBy<T> { rank(it).tier }.thenByDescending { rank(it).at })

enum class MachineDot { Fine, Unreachable, NeedsYou }

/** The worst of the shown machines: yellow where one needs the reader, grey where one is out of reach, green otherwise. */
fun machineDot(states: List<MachineDot>): MachineDot? = states.maxByOrNull { it.ordinal }
