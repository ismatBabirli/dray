package com.wainhq.wain.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.core.content.ContextCompat
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.voice.Dictation
import com.wainhq.wain.voice.Dictations
import com.wainhq.wain.voice.dictationEngine
import com.wainhq.wain.voice.typesOnly
import kotlinx.coroutines.delay

/** The composer to focus once it is on screen: "Ask Wain" opening a bot's chat ready to type. */
object ComposerFocus {
    var key by mutableStateOf<SessionKey?>(null)
}

/** The draft a held mic is talking into, until the finger lifts. */
private object MicHold {
    var draft: SessionKey? = null
}

/** On whatever holds the mic and its strip: letting go of a held mic is Done. */
fun Modifier.releaseEndsHold(draft: SessionKey, store: com.wainhq.wain.store.Store): Modifier = pointerInput(draft) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        do { val e = awaitPointerEvent(PointerEventPass.Initial) } while (e.changes.any { it.pressed })
        if (MicHold.draft == draft) {
            MicHold.draft = null
            // Idle where Android asked for the microphone first: there is nothing to stop.
            if (Dictations.state(draft) == Dictation.Recording) Dictations.stop(store, draft)
        }
    }
}

/** How long a press on the mic waits before it counts as hold-to-talk. */
private const val HOLD_MS = 300L

/**
 * Every composer: the field with the mic inside at its end, which turns to Send once there are
 * words; Stop beside it while a turn runs. Dictating grows the field into the strip — the words
 * as they come, Cancel, the level, the time and Done — and the words land in the field to edit.
 * Tap the mic for hands-free, hold it to talk while held. Where nothing can transcribe there is
 * no mic. The words are `store.drafts[draft]`, so they outlive the screen.
 */
@Composable
fun Composer(
    draft: SessionKey,
    placeholder: String,
    /** A turn is running: Stop shows, and the field queues. */
    busy: Boolean,
    sending: Boolean,
    canSend: Boolean,
    send: () -> Unit,
    stop: (() -> Unit)? = null,
    focus: Boolean = false,
    modifier: Modifier = Modifier,
    chips: (@Composable RowScope.() -> Unit)? = null,
) {
    val store = LocalStore.current
    val text = store.drafts[draft].orEmpty()
    val state = Dictations.state(draft)
    val dictating = state != Dictation.Idle
    val note = Dictations.notes[draft]
    // Leaving mid-recording keeps what was said in this draft, the desktop's rule.
    DisposableEffect(draft) { onDispose { if (Dictations.state(draft) == Dictation.Recording) Dictations.stop(store, draft) } }

    Column(modifier.fillMaxWidth().releaseEndsHold(draft, store).padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        note?.let { KeptNote(it, draft, Modifier.padding(horizontal = 8.dp)) }
        if (dictating) DictationStrip(draft, text)
        else Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Field(draft, text, if (busy) "Queue a message" else placeholder, sending, canSend && text.isNotBlank(), send, focus, Modifier.weight(1f))
            if (busy && stop != null) StopButton(stop)
        }
        chips?.let { Row(Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), content = it) }
    }
}

@Composable
private fun Field(
    draft: SessionKey, text: String, placeholder: String, sending: Boolean, sendable: Boolean, send: () -> Unit, focus: Boolean, modifier: Modifier,
) {
    val store = LocalStore.current
    val focuser = remember { FocusRequester() }
    LaunchedEffect(focus) { if (focus) focuser.requestFocus() }
    Row(
        modifier.heightIn(min = 52.dp).clip(RoundedCornerShape(28.dp)).background(Wain.card).padding(start = 16.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.weight(1f).padding(vertical = 14.dp)) {
            if (text.isEmpty()) Text(placeholder, style = Wain.Font.body.copy(lineHeight = 20.sp, color = Wain.tertiary))
            BasicTextField(
                text, { store.drafts[draft] = it }, Modifier.fillMaxWidth().heightIn(max = 140.dp).focusRequester(focuser),
                textStyle = Wain.Font.body.copy(lineHeight = 20.sp), cursorBrush = SolidColor(Wain.text),
            )
        }
        Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) {
            when {
                sending -> CircularProgressIndicator(Modifier.size(18.dp), color = Wain.secondary, strokeWidth = 2.dp)
                text.isNotBlank() -> SendButton(sendable, send)
                !store.typesOnly -> MicButton(draft)
            }
        }
    }
}

@Composable
private fun SendButton(enabled: Boolean, send: () -> Unit) {
    Box(
        Modifier.size(34.dp).clip(CircleShape).background(Wain.primary).alpha(if (enabled) 1f else 0.35f)
            .clickable(enabled = enabled, onClickLabel = "Send", onClick = send),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Filled.ArrowUpward, "Send", Modifier.size(18.dp), tint = Wain.onPrimary) }
}

@Composable
private fun StopButton(stop: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    Box(
        Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(Wain.primary)
            .clickable(onClickLabel = "Stop") { haptics.performHapticFeedback(HapticFeedbackType.LongPress); stop() }
            .semantics { contentDescription = "Stop" },
        contentAlignment = Alignment.Center,
    ) { Box(Modifier.size(13.dp).clip(RoundedCornerShape(3.dp)).background(Wain.onPrimary)) }
}

/**
 * The mic: a tap starts hands-free dictation, a press held past [HOLD_MS] talks until let go.
 * A kept recording waits on Retry or Discard, never a new press.
 */
@Composable
fun MicButton(draft: SessionKey, size: androidx.compose.ui.unit.Dp = 34.dp, fill: androidx.compose.ui.graphics.Color? = null) {
    val store = LocalStore.current
    val haptics = LocalHapticFeedback.current
    val withMic = rememberWithMic(draft)
    fun begin(): Boolean {
        if (Dictations.state(draft) != Dictation.Idle || Dictations.kept[draft] != null) return false
        val engine = store.dictationEngine() ?: run { Dictations.notes[draft] = "Nothing can transcribe right now. Type instead."; return false }
        Dictations.dismiss(draft)
        withMic {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            Dictations.start(store, engine, draft)
        }
        return true
    }
    Box(
        Modifier.size(size).clip(CircleShape).then(if (fill != null) Modifier.background(fill) else Modifier)
            .semantics {
                role = Role.Button
                contentDescription = "Dictate"
                onClick("Dictate") { begin(); true }
            }
            .pointerInput(draft) {
                awaitEachGesture {
                    awaitFirstDown()
                    val up = withTimeoutOrNull(HOLD_MS) { waitForUpOrCancellation() }
                    if (up != null) { begin(); return@awaitEachGesture }
                    // Held: talk until let go. The strip takes the mic's place at once, so the
                    // release is seen by `releaseEndsHold` around it, never by this button.
                    if (begin()) MicHold.draft = draft
                }
            },
        contentAlignment = Alignment.Center,
    ) { Glyph24(19.dp) { micGlyph(Wain.secondary) } }
}

/** The field grown to dictate: the words so far over Cancel, the level, the time and Done. */
@Composable
internal fun DictationStrip(draft: SessionKey, typed: String) {
    val store = LocalStore.current
    val haptics = LocalHapticFeedback.current
    val state = Dictations.state(draft)
    val reading = state == Dictation.Transcribing
    val heard = Dictations.heard(draft)
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(Wain.raised).animateContentSize()
            .padding(start = 20.dp, end = 6.dp, top = 14.dp, bottom = 6.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            buildAnnotatedString {
                append(typed)
                val live = heard.ifEmpty { if (reading) "Transcribing…" else if (typed.isEmpty()) "Listening…" else "" }
                if (live.isNotEmpty()) withStyle(SpanStyle(color = Wain.tertiary)) { append(if (typed.isEmpty() || typed.endsWith(' ')) live else " $live") }
            },
            Modifier.padding(end = 14.dp).heightIn(max = 168.dp),
            style = Wain.Font.body.copy(lineHeight = 24.sp),
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(Wain.tile).clickable(onClickLabel = "Cancel") {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    Dictations.cancel(draft)
                }.semantics { contentDescription = "Cancel dictation" },
                contentAlignment = Alignment.Center,
            ) { Glyph24(18.dp) { crossGlyph(Wain.text) } }
            Row(Modifier.weight(1f).height(40.dp), verticalAlignment = Alignment.CenterVertically) {
                LevelMeter(draft, state == Dictation.Recording, Modifier.weight(1f))
                Elapsed(Dictations.since[draft])
            }
            Box(
                Modifier.size(48.dp).clip(RoundedCornerShape(16.dp)).background(Wain.primary)
                    .clickable(enabled = state == Dictation.Recording, onClickLabel = "Done") { Dictations.stop(store, draft) }
                    .semantics { contentDescription = "Done" },
                contentAlignment = Alignment.Center,
            ) {
                if (reading || state == Dictation.Starting) CircularProgressIndicator(Modifier.size(18.dp), color = Wain.onPrimary, strokeWidth = 2.dp)
                else Glyph24(22.dp) { checkGlyph(Wain.onPrimary) }
            }
        }
    }
}

/** The last couple of seconds of the voice as bars, newest on the right; dim stubs until there is sound. */
@Composable
private fun LevelMeter(draft: SessionKey, live: Boolean, modifier: Modifier) {
    val bars = remember { mutableStateListOf<Float>().apply { repeat(BARS) { add(0f) } } }
    LaunchedEffect(live) {
        var last = 0L
        while (live) withFrameMillis { t ->
            if (t - last >= 80) {
                last = t
                bars.removeAt(0)
                bars.add(Dictations.level(draft))
            }
        }
    }
    val loud = Wain.text
    val quiet = Wain.dim
    Canvas(modifier.height(40.dp)) {
        val w = 3.dp.toPx()
        val step = 6.dp.toPx()
        val n = minOf(BARS, (size.width / step).toInt())
        for (i in 0 until n) {
            val v = bars[BARS - n + i]
            val h = (4.dp.toPx() + v * 22.dp.toPx()).coerceAtMost(size.height)
            drawRoundRect(if (v > 0.05f) loud else quiet, Offset(i * step, (size.height - h) / 2), Size(w, h), CornerRadius(2.dp.toPx()))
        }
    }
}

private const val BARS = 40

@Composable
private fun Elapsed(since: Long?) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(since) { while (since != null) { now = System.currentTimeMillis(); delay(500) } }
    val s = since?.let { ((now - it) / 1000).coerceAtLeast(0) } ?: return
    Text("%d:%02d".format(s / 60, s % 60), Modifier.padding(start = 8.dp, end = 6.dp),
        style = Wain.Font.footnote.copy(color = Wain.secondary, fontFeatureSettings = "tnum"))
}

/** A chip under the composer: the model with its effort, or the stance; the model's carries the usage ring. */
@Composable
fun ComposerChip(label: String, detail: String? = null, percent: Double? = null, onClick: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier.height(32.dp).clip(shape).border(1.dp, Wain.outline, shape).clickable(onClick = onClick).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        percent?.let { UsageRing(it, it >= 100, 14.dp) }
        Text(label, style = Wain.Font.footnote.copy(lineHeight = 16.sp, fontWeight = FontWeight.Medium), maxLines = 1)
        detail?.let { Text(it, style = Wain.Font.footnote.copy(lineHeight = 16.sp, color = Wain.secondary), maxLines = 1) }
    }
}

/** What dictation said instead of words, under the resting orb; Retry and Discard beside it while the audio is kept. */
@Composable
internal fun KeptNote(line: String, draft: SessionKey, modifier: Modifier = Modifier) {
    val store = LocalStore.current
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(line, Modifier.weight(1f, fill = false), style = Wain.Font.footnote.copy(color = Wain.tertiary), textAlign = TextAlign.Center)
        if (Dictations.kept[draft] != null) {
            Text("Retry", Modifier.clickable { Dictations.retry(store, draft) }, style = Wain.Font.footnoteStrong)
            Text("Discard", Modifier.clickable { Dictations.dismiss(draft) }, style = Wain.Font.footnoteStrong.copy(color = Wain.destructive))
        }
    }
}

/**
 * Runs what it is handed with the microphone allowed, asking Android first where it hasn't been.
 * A refusal is said in the draft's note, where a failed dictation would say it.
 */
@Composable
internal fun rememberWithMic(draft: SessionKey): (() -> Unit) -> Unit {
    val context = LocalContext.current
    var waiting by remember { mutableStateOf<(() -> Unit)?>(null) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val then = waiting
        waiting = null
        if (granted) then?.invoke()
        else Dictations.notes[draft] = "Wain can't use the microphone. Allow it in Android's settings, under Apps, Wain, Permissions."
    }
    return { then ->
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) then()
        else {
            waiting = then
            ask.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
}
