package com.wainhq.wain

import com.wainhq.wain.model.BotRank
import com.wainhq.wain.model.HomeEntry
import com.wainhq.wain.model.HomeSection
import com.wainhq.wain.model.MachineDot
import com.wainhq.wain.model.botOrder
import com.wainhq.wain.model.homeSections
import com.wainhq.wain.model.machineDot
import com.wainhq.wain.model.nextRunLabel
import com.wainhq.wain.model.routineOrder
import com.wainhq.wain.model.scheduleLabel
import com.wainhq.wain.model.usageChips
import com.wainhq.wain.model.windowLabel
import com.wainhq.wain.wire.Routine
import com.wainhq.wain.wire.RoutineSchedule
import com.wainhq.wain.wire.UsageReading
import com.wainhq.wain.wire.UsageWindow
import com.wainhq.wain.wire.parseDate
import com.wainhq.wain.wire.wireJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TabsTest {
    private fun e(owner: String, s: HomeSection, at: Long) = HomeEntry(owner, s, at, "$owner/$s")

    @Test fun homeKeepsTheMostUrgentPlace() {
        val out = homeSections(listOf(
            e("a", HomeSection.Working, 5), e("a", HomeSection.Waiting, 1),
            e("b", HomeSection.Fresh, 9), e("b", HomeSection.Working, 2),
            e("c", HomeSection.Fresh, 3),
        ))
        assertEquals(listOf("a"), out[HomeSection.Waiting]!!.map { it.owner })
        assertEquals(listOf("b"), out[HomeSection.Working]!!.map { it.owner })
        assertEquals(listOf("c"), out[HomeSection.Fresh]!!.map { it.owner })
    }

    @Test fun waitingKeepsEveryCardNewestFirst() {
        val out = homeSections(listOf(e("a", HomeSection.Waiting, 1), e("a", HomeSection.Waiting, 7), e("b", HomeSection.Waiting, 4)))
        assertEquals(listOf(7L, 4L, 1L), out[HomeSection.Waiting]!!.map { it.at })
        assertNull(out[HomeSection.Working])
        assertTrue(homeSections(emptyList<HomeEntry<String>>()).isEmpty())
    }

    @Test fun botsSortWaitingUnreadWorkingThenRecent() {
        val ranks = mapOf(
            "idle-new" to BotRank(false, false, false, 90), "working" to BotRank(false, false, true, 10),
            "unread" to BotRank(false, true, false, 5), "waiting" to BotRank(true, true, true, 1),
            "idle-old" to BotRank(false, false, false, 2),
        )
        assertEquals(listOf("waiting", "unread", "working", "idle-new", "idle-old"), botOrder(ranks.keys.toList()) { ranks[it]!! })
    }

    @Test fun machineDotIsTheWorst() {
        assertNull(machineDot(emptyList()))
        assertEquals(MachineDot.Fine, machineDot(listOf(MachineDot.Fine, MachineDot.Fine)))
        assertEquals(MachineDot.Unreachable, machineDot(listOf(MachineDot.Fine, MachineDot.Unreachable)))
        assertEquals(MachineDot.NeedsYou, machineDot(listOf(MachineDot.Unreachable, MachineDot.NeedsYou, MachineDot.Fine)))
    }

    private fun r(name: String, every: Int? = null, at: String? = null, days: List<Int> = emptyList(), paused: Boolean = false, next: String? = null) =
        Routine("id-$name", name = name, schedule = RoutineSchedule(every, at, days), paused = paused, nextRun = next)

    @Test fun schedulesReadAsTheServerSaysThem() {
        assertEquals("Every 2h", scheduleLabel(r("x", every = 120)))
        assertEquals("Every 1d", scheduleLabel(r("x", every = 1440)))
        assertEquals("Every 45m", scheduleLabel(r("x", every = 45)))
        assertEquals("Daily at 18:00", scheduleLabel(r("x", at = "18:00")))
        assertEquals("Weekdays at 09:00", scheduleLabel(r("x", at = "09:00", days = listOf(4, 3, 2, 1, 0))))
        assertEquals("Weekends at 10:00", scheduleLabel(r("x", at = "10:00", days = listOf(5, 6))))
        assertEquals("Mon, Fri at 16:00", scheduleLabel(r("x", at = "16:00", days = listOf(4, 0))))
    }

    @Test fun nextRunWords() {
        val now = parseDate("2026-11-13T12:00:00Z")!!
        val t = { _: Long -> "T" }
        val d = { _: Long -> "D" }
        assertEquals("Paused", nextRunLabel(r("x", paused = true), now, t, d))
        assertEquals("Not scheduled", nextRunLabel(r("x"), now, t, d))
        assertEquals("Due now", nextRunLabel(r("x", next = "2026-11-13T11:59:00Z"), now, t, d))
        assertEquals("Next in 34m", nextRunLabel(r("x", next = "2026-11-13T12:34:00Z"), now, t, d))
        assertTrue(nextRunLabel(r("x", next = "2026-11-20T12:34:00Z"), now, t, d).endsWith("on D"))
    }

    @Test fun routinesSoonestFirstPausedLast() {
        val list = listOf(
            r("paused", paused = true), r("later", next = "2026-11-13T18:00:00Z"),
            r("soon", next = "2026-11-13T12:30:00Z"), r("unscheduled"),
        )
        assertEquals(listOf("soon", "later", "unscheduled", "paused"), routineOrder(list) { it }.map { it.name })
    }

    private fun reading(h: String, five: Double?, limited: Boolean = false, weekly: Double? = null) = UsageReading(
        h, limited = limited, at = "2026-11-26T12:00:00Z",
        windows = listOfNotNull(
            five?.let { UsageWindow("five_hour", it, "2026-11-26T14:00:00Z", 300) },
            weekly?.let { UsageWindow("weekly", it, "2026-12-01T09:00:00Z", 10080) },
        ),
    )

    @Test fun chipsTakeEachAgentsWorstMachineLimitedFirst() {
        val chips = usageChips(listOf(
            reading("codex", 49.0), reading("claude_code", 30.0), reading("claude_code", 84.0),
            reading("pi", null), reading("grok", 10.0, limited = true),
        ))
        assertEquals(listOf("grok", "claude_code", "codex"), chips.map { it.harness })
        assertEquals(84.0, chips[1].percent, 0.0)
        assertTrue(chips[0].limited)
    }

    @Test fun aSpentWeeklyHoldsTheChipUntilItResets() {
        val chip = usageChips(listOf(reading("claude_code", 40.0, weekly = 100.0))).single()
        assertTrue(chip.limited)
        assertEquals("2026-12-01T09:00:00Z", chip.back)
    }

    @Test fun windowNames() {
        assertEquals("5-hour", windowLabel(UsageWindow("five_hour")))
        assertEquals("Weekly", windowLabel(UsageWindow("weekly")))
        assertEquals("30-day", windowLabel(UsageWindow("other", minutes = 43200)))
    }

    @Test fun readingsDecodeLeniently() {
        val list = UsageReading.list(wireJson.parseToJsonElement("""
            [{"harness":"claude_code","limited":null,"at":"2026-11-26T12:04:00Z","windows":[{"kind":"five_hour","usedPercent":84.0,"resetsAt":"2026-11-26T14:00:00Z","minutes":300},{"kind":"mystery"}]},
             {"plan":"plus"},
             {"harness":"codex","plan":"plus","windows":[]}]
        """))
        assertEquals(listOf("claude_code", "codex"), list.map { it.harness })
        assertEquals(2, list[0].windows.size)
        assertEquals("plus", list[1].plan)
    }
}
