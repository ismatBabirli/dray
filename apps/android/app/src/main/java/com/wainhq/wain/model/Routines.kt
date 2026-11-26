package com.wainhq.wain.model

import com.wainhq.wain.wire.Routine
import com.wainhq.wain.wire.parseDate
import java.util.Calendar

// The Routines tab's words and order: the desktop's routines.ts and BotMore.swift's `Routine`.

private val dayNames = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

/** "Every 2h", "Weekdays at 09:00", as the server's `describe` says it. */
fun scheduleLabel(r: Routine): String {
    val m = r.schedule.everyMinutes
    if (m != null && m > 0) return "Every " + when {
        m % 1440 == 0 -> "${m / 1440}d"
        m % 60 == 0 -> "${m / 60}h"
        else -> "${m}m"
    }
    val days = r.schedule.days.filter { it in 0..6 }.distinct().sorted()
    val whenLabel = when (days) {
        emptyList<Int>(), (0..6).toList() -> "Daily"
        (0..4).toList() -> "Weekdays"
        listOf(5, 6) -> "Weekends"
        else -> days.joinToString(", ") { dayNames[it] }
    }
    return "$whenLabel at ${r.schedule.at ?: "?"}"
}

/** "Paused", "Next in 34m", "Next 9:00 AM tomorrow" or "Due now": the desktop's `nextRunLabel`. */
fun nextRunLabel(r: Routine, now: Long, time: (Long) -> String, date: (Long) -> String): String {
    if (r.paused) return "Paused"
    val at = parseDate(r.nextRun) ?: return "Not scheduled"
    val min = Math.round((at - now) / 60_000.0)
    if (min <= 0) return "Due now"
    if (min < 60) return "Next in ${min}m"
    return when (daysBetween(now, at)) {
        0 -> "Next ${time(at)}"
        1 -> "Next ${time(at)} tomorrow"
        else -> "Next ${time(at)} on ${date(at)}"
    }
}

private fun daysBetween(a: Long, b: Long): Int {
    fun day(ms: Long) = Calendar.getInstance().apply {
        timeInMillis = ms
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    return Math.round((day(b) - day(a)) / 86_400_000.0).toInt()
}

/** Soonest next run first, paused ones last, each group's ties by name. */
fun <T> routineOrder(list: List<T>, routine: (T) -> Routine): List<T> =
    list.sortedWith(compareBy<T>({ routine(it).paused }, { parseDate(routine(it).nextRun) ?: Long.MAX_VALUE }, { routine(it).name.lowercase() }))
