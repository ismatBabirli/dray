package com.wainhq.wain

import com.wainhq.wain.push.PushAlert
import com.wainhq.wain.ui.OrbFrame
import com.wainhq.wain.voice.Dictation
import com.wainhq.wain.voice.TranscribeOutcome
import com.wainhq.wain.voice.loudness
import com.wainhq.wain.wire.wireJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PushAndVoiceTest {
    /** An FCM message's `data` exactly as the relay sent it for a real question from `wain-serve`. */
    private val question = mapOf(
        "title" to "Pick a size",
        "body" to "Which size should I use?",
        "tag" to "53a9a953-7c73-424d-a3ec-a25a6344d555",
        "wain" to """{"kind":"question","server":"44E2F783-4EE0-4302-B495-C9E8BB5657CD","session":"01a1fcdf-a6e1-705e-980c-3444ebe3e519","request":"53a9a953-7c73-424d-a3ec-a25a6344d555","question":{"text":"Which size should I use?","options":["Small","Medium","Large"],"freeText":true}}""",
    )

    @Test fun readsTheRelaysQuestion() {
        val a = PushAlert.parse(question)!!
        assertEquals("question", a.kind)
        assertEquals("53a9a953-7c73-424d-a3ec-a25a6344d555", a.request)
        assertEquals(listOf("Small", "Medium", "Large"), a.question?.options)
        assertTrue(a.question!!.freeText)
        // No `open`: a tap opens the task itself.
        assertEquals("01a1fcdf-a6e1-705e-980c-3444ebe3e519", a.key.id)
    }

    @Test fun aBotsTaskOpensTheBotsChat() {
        val a = PushAlert.parse(mapOf("title" to "T", "body" to "B",
            "wain" to """{"kind":"permission","server":"S","session":"task","open":"chat","request":"r","allow":"once","deny":"no"}"""))!!
        assertEquals("chat", a.key.id)
        assertEquals("task", a.session)
        // An action's intent carries the alert back through `data`, and reads the same.
        assertEquals(a, PushAlert.parse(a.data()))
    }

    @Test fun anAlertMissingWhatItNeedsIsNone() {
        assertNull(PushAlert.parse(mapOf("title" to "T")))
        assertNull(PushAlert.parse(mapOf("wain" to """{"kind":"done","server":"S"}""")))
        assertNull(PushAlert.parse(mapOf("wain" to "not json")))
    }

    @Test fun readsEveryTranscribeOutcome() {
        fun read(s: String) = TranscribeOutcome.decode(wireJson.parseToJsonElement(s))
        assertEquals(TranscribeOutcome.Text("hi"), read("""{"kind":"text","value":"hi"}"""))
        assertEquals(TranscribeOutcome.NeedsModel, read("""{"kind":"needsModel","value":{"audioPath":null}}"""))
        assertEquals(TranscribeOutcome.NoAudio, read("""{"kind":"noAudio"}"""))
        assertEquals(TranscribeOutcome.Failed("boom"), read("""{"kind":"failed","value":{"message":"boom","audioPath":"/x"}}"""))
        assertEquals(TranscribeOutcome.Failed("The server answered later"), read("""{"kind":"later"}"""))
    }

    @Test fun loudnessIsADecibelScale() {
        assertEquals(0f, loudness(0.002f), 0.01f)
        assertEquals(1f, loudness(1f), 0.01f)
        assertTrue(loudness(0.05f) in 0.6f..0.9f)
    }

    @Test fun theOrbitFinishesItsLapBeforeUncurling() {
        var f = OrbFrame()
        repeat(60) { f = f.next(1 / 60.0, Dictation.Transcribing, 0f) }
        assertTrue(f.spin > 0 && f.curl > 0.9)
        f = f.next(1 / 60.0, Dictation.Idle, 0f)
        // Still curled while it winds home.
        assertTrue(f.curl > 0.9)
        repeat(240) { f = f.next(1 / 60.0, Dictation.Idle, 0f) }
        assertEquals(0.0, f.spin, 0.0)
        assertTrue(f.curl < 0.01)
    }
}
