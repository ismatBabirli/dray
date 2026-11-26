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

/** The window a chip and the composer's ring read: five-hour, or the first window where there is none. */
val UsageReading.headline: UsageWindow? get() = windows.firstOrNull { it.kind == "five_hour" } ?: windows.firstOrNull()

/** Spent: the server said so, or a window is full. */
val UsageReading.atLimit: Boolean get() = limited || windows.any { it.usedPercent >= 100 }

/** One chip per agent with a reading, its highest five-hour across machines; spent ones first, then fullest. */
fun usageChips(readings: List<UsageReading>): List<UsageChip> =
    readings.groupBy { it.harness }.mapNotNull { (harness, list) ->
        val worst = list.filter { it.headline != null }.maxWithOrNull(
            compareBy<UsageReading>({ it.atLimit }, { it.headline!!.usedPercent }),
        ) ?: return@mapNotNull null
        val window = worst.headline!!
        // What comes back last is what holds the agent: a spent weekly outlasts the five-hour.
        val spent = worst.windows.filter { it.usedPercent >= 100 }.maxByOrNull { parseDate(it.resetsAt) ?: 0L }
        UsageChip(harness, window.usedPercent, worst.atLimit, (spent ?: window).resetsAt)
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
