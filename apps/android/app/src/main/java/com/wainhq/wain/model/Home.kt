package com.wainhq.wain.model

// The tabs' shared rules (mobile-tabs-rules.md, restated by the iPhone app): Home's three
// sections, the Bots tab's order and the Machines button's dot.

enum class HomeSection { Waiting, Working, Fresh }

/** Why a session is on Home, most urgent first: a card, a ready PR, a stall, then working, then new. */
enum class HomeKind(val section: HomeSection) {
    Card(HomeSection.Waiting), Merge(HomeSection.Waiting), Stall(HomeSection.Waiting),
    Working(HomeSection.Working), Fresh(HomeSection.Fresh),
}

/** One reason a session could be on Home: what it is (`value`), the session it belongs to, and when it last moved. */
data class HomeEntry<T>(val session: String, val kind: HomeKind, val at: Long, val value: T)

/**
 * Home's sections, newest first in each: every session once, at its most urgent place. The
 * Waiting count, Home's yellow badge, counts these rows. Empty sections are absent.
 */
fun <T> homeSections(entries: List<HomeEntry<T>>): Map<HomeSection, List<HomeEntry<T>>> =
    entries.groupBy { it.session }.values.map { same -> same.minWith(compareBy({ it.kind.ordinal }, { -it.at })) }
        .sortedByDescending { it.at }.groupBy { it.kind.section }.toSortedMap()

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
