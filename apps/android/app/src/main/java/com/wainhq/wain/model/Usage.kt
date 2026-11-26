package com.wainhq.wain.model

import com.wainhq.wain.wire.UsageReading
import com.wainhq.wain.wire.UsageWindow
import com.wainhq.wain.wire.parseDate

// Usage readings as the phones draw them: the Home chips, the Usage sheet, the composer's ring.
// The rules are mobile-tabs-rules.md's, shared with the iPhone app.

/** One chip on Home: an agent's worst five-hour reading across the machines shown. */
data class UsageChip(
    val harness: String,
    val percent: Double,
    val limited: Boolean,
    /** When the spent window comes back, RFC3339; drawn as "back HH:MM". */
    val back: String?,
)

/**
 * A window's figure as the phones read it. Claude's older `rejected` line sends none: on a
 * limited reading that window is spent (100); on any other it has no figure at all.
 */
fun UsageReading.used(w: UsageWindow): Double? = w.usedPercent ?: if (limited) 100.0 else null

/** The window a chip and the composer's ring read: five-hour, else the fullest window with a figure. */
val UsageReading.headline: UsageWindow?
    get() = windows.firstOrNull { it.kind == "five_hour" && used(it) != null }
        ?: windows.filter { used(it) != null }.maxByOrNull { used(it)!! }

/** The headline's figure. */
val UsageReading.headlinePercent: Double? get() = headline?.let { used(it) }

/** Spent: the server said so, or a window is full. */
val UsageReading.atLimit: Boolean get() = limited || windows.any { (used(it) ?: 0.0) >= 100 }

/**
 * One chip per agent with a reading: the one reading that is its worst across the shown machines
 * (spent first, then the fullest headline) speaks for it, nothing mixed in from the others.
 * "back" is the latest reset among that reading's spent windows, else its headline's.
 */
fun usageChips(readings: List<UsageReading>): List<UsageChip> =
    readings.groupBy { it.harness }.mapNotNull { (harness, list) ->
        val worst = list.filter { it.headline != null }.maxWithOrNull(
            compareBy<UsageReading>({ it.atLimit }, { it.headlinePercent }),
        ) ?: return@mapNotNull null
        val window = worst.headline!!
        // What comes back last is what holds the agent: a spent weekly outlasts the five-hour.
        val spent = worst.windows.filter { (worst.used(it) ?: 0.0) >= 100 }.maxByOrNull { parseDate(it.resetsAt) ?: 0L }
        UsageChip(harness, worst.headlinePercent!!, worst.atLimit, (spent ?: window).resetsAt)
    }.sortedWith(compareByDescending<UsageChip> { it.limited }.thenByDescending { it.percent })

/** "5-hour", "Weekly", or "N-day" for any other window. */
fun windowLabel(w: UsageWindow): String = when (w.kind) {
    "five_hour" -> "5-hour"
    "weekly" -> "Weekly"
    else -> w.minutes?.let { m -> if (m >= 1440) "${(m + 720) / 1440}-day" else "${maxOf(1, m / 60)}-hour" } ?: "Window"
}

/** The chip's short agent name: Claude rather than Claude Code, which a 32dp chip has no room for. */
fun usageAgent(harness: String): String = if (harness == "claude_code") "Claude" else Picks.agentLabels[harness] ?: harness

/** A plan as the sheet says it: "Max", "Plus". */
fun planLabel(plan: String?): String? = plan?.takeIf { it.isNotBlank() }?.replace('_', ' ')?.replaceFirstChar { it.uppercase() }
