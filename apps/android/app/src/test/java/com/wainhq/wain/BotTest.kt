package com.wainhq.wain

import com.wainhq.wain.model.Blobatar
import com.wainhq.wain.model.BotItem
import com.wainhq.wain.model.BotRow
import com.wainhq.wain.model.SentTo
import com.wainhq.wain.model.Unread
import com.wainhq.wain.model.botItems
import com.wainhq.wain.model.botRows
import com.wainhq.wain.model.chatTime
import com.wainhq.wain.model.currentTool
import com.wainhq.wain.model.inReviewTurn
import com.wainhq.wain.model.lessonKind
import com.wainhq.wain.model.previewLine
import com.wainhq.wain.model.prStatus
import com.wainhq.wain.model.sentMessages
import com.wainhq.wain.model.unquoted
import com.wainhq.wain.model.unreadStart
import com.wainhq.wain.wire.AgentEvent
import com.wainhq.wain.wire.BotAvatar
import com.wainhq.wain.wire.Lesson
import com.wainhq.wain.wire.PrMark
import com.wainhq.wain.wire.arr
import com.wainhq.wain.wire.double
import com.wainhq.wain.wire.get
import com.wainhq.wain.wire.str
import com.wainhq.wain.wire.wireJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset

class BotTest {
    private fun ev(id: String, payload: String) =
        AgentEvent.decode(wireJson.parseToJsonElement("""{"id":"$id","sessionId":"s","ts":"2026-11-21T10:00:00Z","subagent":null,"payload":$payload}"""))!!

    private fun q(s: String) = kotlinx.serialization.json.JsonPrimitive(s).toString()

    private fun user(id: String, text: String, kickoff: Boolean = false) =
        ev(id, """{"type":"user_message","text":${q(text)},"kickoff":$kickoff}""")

    private fun said(id: String, text: String) = ev(id, """{"type":"assistant_text","text":"$text"}""")

    private fun bash(id: String, call: String, cmd: String) =
        ev(id, """{"type":"tool_call_started","callId":"$call","name":"Bash","toolType":"command","input":{"command":${q(cmd)}}}""")

    private fun done(id: String, call: String, text: String) =
        ev(id, """{"type":"tool_call_completed","callId":"$call","result":{"text":${q(text)},"isError":false}}""")

    @Test
    fun aRoutineReportLabelsTheReplyAndATaskReportDoesNot() {
        fun report(id: String, from: String, title: String) =
            ev(id, """{"type":"user_message","text":"done","from":{"sessionId":"$from","title":"$title"}}""")
        val items = botItems(listOf(
            report("r1", "run-1", "Morning PR sweep"), said("a1", "Two PRs wait on you."),
            report("r2", "task-1", "Fix login"), said("a2", "Login is fixed."),
            user("u1", "thanks"), said("a3", "Any time."),
        ), routineRuns = setOf("run-1"))
        val replies = items.filterIsInstance<BotItem.Assistant>()
        assertEquals("Morning PR sweep", replies[0].routine?.name)
        assertEquals(listOf(null, null), replies.drop(1).map { it.routine })
        assertEquals(1, items.count { it is BotItem.User })
    }

    @Test
    fun anIssueCardKnowsWhatWasStartedFromIt() {
        val card = """{"type":"issue_card","repo":"acme/app","issues":[
            {"number":1,"title":"Fix login","url":"u1","closed":false,"labels":[{"name":"bug","color":"d73a4a"}],"excerpt":"Nothing happens."},
            {"number":2,"title":"Old","url":"u2","closed":true,"labels":[],"author":{"name":"a","avatar":null}}]}"""
        val items = botItems(listOf(
            ev("c1", card),
            ev("x1", """{"type":"issue_approved","cardId":"c1","number":1}"""),
            ev("x2", """{"type":"issue_approved","cardId":"other","number":2}"""),
        ))
        val issues = items.single() as BotItem.Issues
        assertEquals("acme/app", issues.card.repo)
        assertEquals(listOf(1, 2), issues.card.issues.map { it.number })
        assertEquals("d73a4a", issues.card.issues[0].labels.single().color)
        assertTrue(issues.card.issues[1].closed)
        assertEquals(setOf(1), issues.started)
        assertEquals("s", issues.sessionId)
    }

    @Test
    fun drawsTheConversationAndNotTheWork() {
        val items = botItems(listOf(
            user("u1", "Kick off", kickoff = true),
            user("u2", "Fix the login"),
            said("a1", "On it."),
            bash("t1", "c1", "ls -la"),
            done("t2", "c1", "file"),
            ev("r1", """{"type":"reaction","messageId":"u2","emoji":"👀"}"""),
            ev("r2", """{"type":"reaction","messageId":"u2","emoji":"✅"}"""),
        ))
        assertEquals(listOf("u2", "a1"), items.map { it.id })
        assertEquals("✅", (items[0] as BotItem.User).reaction)
    }

    @Test
    fun theReadersReactionSitsOnTheReplyAndItsNoteDrawsNothing() {
        val items = botItems(listOf(
            user("u1", "Fix the login"),
            said("a1", "Fixed."),
            ev("r1", """{"type":"reaction","messageId":"a1","emoji":"👍","byUser":true}"""),
            ev("r2", """{"type":"reaction","messageId":"a1","emoji":"❤️","byUser":true}"""),
            user("u2", "The user reacted ❤️ (love) to your message", kickoff = true),
            said("a2", "Glad it works!"),
        ))
        assertEquals(listOf("u1", "a1", "a2"), items.map { it.id })
        assertNull((items[0] as BotItem.User).reaction)
        assertEquals("❤️", (items[1] as BotItem.Assistant).reaction)
        assertEquals("s", (items[1] as BotItem.Assistant).sessionId)
    }

    @Test
    fun aFailedTurnDrawsItsSentenceOnce() {
        val items = botItems(listOf(
            user("u1", "Go"),
            said("a1", "Usage limit reached"),
            ev("t", """{"type":"turn_completed","status":"error","stopReason":"stop_sequence","finalText":"Usage limit reached"}"""),
        ))
        assertEquals(listOf("u1", "t"), items.map { it.id })
        assertEquals("Usage limit reached", (items[1] as BotItem.Notice).text)
    }

    @Test
    fun readsStartsAndSendsFromTheBotsCommands() {
        val id = "3f0c2a9e-1b2c-4d5e-8f90-123456789abc"
        val items = botItems(listOf(
            bash("t1", "c1", "wain session new --title x 'do it'"),
            done("t2", "c1", "$id\n"),
            bash("t3", "c2", "wain session send aaaa1111 'hi' && wain session send bbbb2222 \"yo\""),
            done("t4", "c2", "sent"),
            bash("t5", "c3", "wain bot send Ops 'ship it'"),
            done("t6", "c3", "Sent to bot \"Ops\" (9d3e5a1c-0000-4000-8000-000000000001)."),
        ))
        assertEquals(BotItem.Task("c1", id, null, "2026-11-21T10:00:00Z"), items[0])
        val rows = botRows(items)
        assertEquals(listOf("aaaa1111", "bbbb2222"), (rows[1] as BotRow.Talk).targets)
        val sent = (rows[2] as BotRow.One).item as BotItem.BotSent
        assertEquals("Ops", sent.name)
        assertEquals("9d3e5a1c-0000-4000-8000-000000000001", sent.botId)
    }

    @Test
    fun aServerLoggedTaskWinsOverTheShellCall() {
        val id = "3f0c2a9e-1b2c-4d5e-8f90-123456789abc"
        val items = botItems(listOf(
            bash("t1", "c1", "wain session new 'do it'"),
            ev("ts", """{"type":"task_started","taskId":"$id","title":"Do it"}"""),
            done("t2", "c1", "$id\n"),
        ))
        assertEquals(listOf("ts"), items.map { it.id })
    }

    @Test
    fun aHiddenReviewDrawsNothingAndLessonsDrawEach() {
        val items = botItems(listOf(
            user("u1", "Review: The user just corrected you.", kickoff = true),
            said("a1", "Nothing to keep."),
            ev("l", """{"type":"learned","commit":"abc","files":[{"path":"AGENTS.md","kind":"instructions","change":"changed","summary":"Check"},{"path":"s.md","kind":"skill","change":"added","summary":"Fork"}]}"""),
            ev("x", """{"type":"learned_undone","commit":"abc","path":"s.md"}"""),
        ))
        assertEquals(listOf("l:AGENTS.md", "l:s.md"), items.map { it.id })
        assertFalse((items[0] as BotItem.Learned).undone)
        assertTrue((items[1] as BotItem.Learned).undone)
        assertEquals("New skill", lessonKind(Lesson("p", "skill", "added", "")))
        assertEquals("Rule", lessonKind(Lesson("p", "instructions", "changed", "")))
        assertTrue(inReviewTurn(listOf(user("u1", "Review: x", kickoff = true))))
    }

    @Test
    fun readsSendsOutOfEachShellQuoting() {
        assertEquals(listOf(SentTo("abc12345", false)), sentMessages("wain send abc12345 'it'\\''s done'", unquoted("wain send abc12345 'it'\\''s done'")))
        fun sends(cmd: String) = sentMessages(cmd, unquoted(cmd)).map { it.target }
        assertEquals(listOf("abc12345"), sends("wain session send abc12345 \"$(cat <<'EOF'\nline one\nEOF\n)\""))
        assertEquals(emptyList<String>(), sends("wain session ls"))
        assertEquals(listOf("Release Ops", "Research"), sends("wain bot send \"Release Ops\" \"ship it\" && wain bot send Research 'look'"))
        assertEquals(emptyList<String>(), sends("wain bot send Ops"))
        assertEquals(listOf("Ops", "Keeper"), sends("wain bot send Ops 'Reply with wain bot send Research \"done\"' && wain bot send Keeper hi"))
        assertEquals(emptyList<String>(), sends("for id in aaa bbb; do wain session send \"\$id\" \"hello\"; done"))
        assertEquals(listOf("aaaa1111", "cccc3333"), sends("wain session send aaaa1111 \"$(cat <<'EOF'\nthen run wain session send bbbb2222 \"x\"\nEOF\n)\" && wain session send cccc3333 ok"))
        assertEquals(listOf("aaaa1111", "cccc3333"), sends("cat <<'EOF' >/tmp/brief; wain session send aaaa1111 hi\nsay wain session send bbbb2222 no\nEOF\nwain session send cccc3333 ok"))
        assertEquals(listOf("aaaa1111"), sends("cat <<< \"hello\"\nwain session send aaaa1111 hi"))
        assertEquals(listOf("cccc3333"), sends("cat <<END-TEXT\nwain session send bbbb2222 no\nEND-TEXT\nwain session send cccc3333 ok"))
        assertEquals(emptyList<String>(), sends("printf '' <<EOF\nwain session send aaaa1111 \"example only\""))
        assertEquals(listOf("aaaa1111", "bbbb2222"), sends("wain send aaaa1111 \"Explain <<EOF\nsyntax\"; wain send bbbb2222 hi\ncat <<EOF\nbody\nEOF"))
    }

    @Test
    fun theNewDividerWaitsForTheReadersLastMessage() {
        val items = listOf(
            BotItem.User("u", "hi", emptyList(), null, null),
            BotItem.Assistant("a1", "one", null),
            BotItem.Assistant("a2", "two", null),
        )
        assertEquals(Unread("a1"), unreadStart(items, "a2", complete = false))
        assertNull(unreadStart(items.drop(1), "a2", complete = false))
        assertEquals(Unread("a1"), unreadStart(items.drop(1), "a2", complete = true))
        assertEquals(Unread(null), unreadStart(items.take(1), "u", complete = false))
    }

    @Test
    fun theOrbLineNamesTheOpenCall() {
        val events = listOf(user("u", "go"), bash("t1", "c1", "wain session new 'x'"))
        assertTrue(currentTool(events)!!.contains("wain session new"))
        assertNull(currentTool(events + done("t2", "c1", "ok") + ev("e", """{"type":"turn_completed","status":"success"}""")))
    }

    @Test
    fun previewIsOnePlainLine() {
        assertEquals("Done. See the PR and ship.", previewLine("## Done.\n\nSee **the** [PR](http://x)\n```\ncode\n```\nand `ship`."))
    }

    @Test
    fun statusReadsChecksBeforeTheMergeState() {
        val pr = PrMark(1, "b", state = "OPEN", mergeable = "MERGEABLE", mergeStateStatus = "BLOCKED")
        assertEquals("blocked", prStatus(pr))
        assertEquals("checksFailing", prStatus(pr.copy(checksState = "FAILING")))
        assertEquals("ready", prStatus(pr.copy(mergeStateStatus = "CLEAN")))
        assertEquals("conflict", prStatus(pr.copy(mergeable = "CONFLICTING", checksState = "FAILING")))
        assertEquals("merged", prStatus(pr.copy(state = "MERGED")))
    }

    @Test
    fun chatTimeSaysTodayYesterdayAndTheDay() {
        val zone = ZoneOffset.UTC
        val now = LocalDateTime.of(2026, 11, 21, 12, 0).toInstant(zone).toEpochMilli()
        fun at(d: Int, h: Int) = LocalDateTime.of(2026, 11, d, h, 5).toInstant(zone).toEpochMilli()
        assertEquals("Today 09:05", chatTime(at(21, 9), now, zone))
        assertEquals("Yesterday 18:05", chatTime(at(20, 18), now, zone))
        assertTrue(chatTime(at(10, 18), now, zone).endsWith("18:05"))
    }

    /** Held to Blobatar's own output: `blobatar_faces.gen.js` wrote the file from the island's `botface.js`. */
    @Test
    fun facesMatchTheJavaScript() {
        val text = javaClass.classLoader!!.getResource("blobatar_faces.json")!!.readText()
        val cases = wireJson.parseToJsonElement(text).arr
        assertTrue(cases.size > 30)
        for (c in cases) {
            val (seed, pick, svg) = c.arr
            val avatar = pick["shape"].str?.let { BotAvatar(it, pick["hue"].double!!) }
            val body = svg.str!!.substringAfter("height=\"64\">").removeSuffix("</svg>")
            assertEquals("${seed.str} $avatar", body, Blobatar.svg(Blobatar.face(seed.str!!, avatar)))
        }
    }

    @Test
    fun seededFacesAreStable() {
        assertEquals(Blobatar.seededAvatar("abc"), Blobatar.seededAvatar("abc"))
        assertTrue(Blobatar.shapes.any { it.first == Blobatar.seededAvatar("3f0c2a9e").shape })
    }
}
