package com.wainhq.wain.ui

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wainhq.wain.model.BranchList
import com.wainhq.wain.model.Model
import com.wainhq.wain.model.Picks
import com.wainhq.wain.store.NewTask
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.jsonOf
import com.wainhq.wain.wire.wireJson
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

// The pieces every picks sheet is built from: the new task's pages, This task, the start box,
// the bot sheet. They were Run with's, which the new task sheet replaced (#35).

/** The shortlist lives on this phone, per agent; null until edited, which draws every model the server doesn't mark secondary. */
private fun shortlist(context: Context, harness: String): List<String>? =
    context.getSharedPreferences("new", Context.MODE_PRIVATE).getString("shortlist.$harness", null)
        ?.let { runCatching { wireJson.decodeFromString(ListSerializer(String.serializer()), it) }.getOrNull() }

private fun saveShortlist(context: Context, harness: String, ids: List<String>) =
    context.getSharedPreferences("new", Context.MODE_PRIVATE).edit()
        .putString("shortlist.$harness", wireJson.encodeToString(ListSerializer(String.serializer()), ids)).apply()

private fun listed(m: Model, list: List<String>?) = list?.contains(m.id) ?: (m.secondary != true)

/** The models a picker offers, id to label: the shortlist, the picked one, and "Default" where the agent runs its own. */
@Composable
fun shortlisted(models: List<Model>, harness: String, selected: String): List<Pair<String, String>> {
    val context = LocalContext.current
    val list = remember(harness, models) { shortlist(context, harness) }
    // pi and fx run their own default where nothing is picked, so that is a choice too.
    return (if (Picks.defaultModel[harness] == "") listOf("" to "Default") else emptyList()) +
        models.filter { listed(it, list) || it.id == selected }.map { it.id to it.label }
}

/** An agent's shortlisted models as chips, and More models to edit the list. */
@Composable
fun ModelChips(models: List<Model>, harness: String, selected: String, pick: (String) -> Unit, more: () -> Unit) {
    val choices = shortlisted(models, harness, selected)
    ChipRow(focus = choices.indexOfFirst { it.first == selected }) {
        items(choices, key = { it.first }) { (id, label) -> PickChip(label, id == selected) { pick(id) } }
        if (models.isNotEmpty()) item("more") { PickChip("More models", false, onClick = more) }
    }
}

/** Every model the agent has, each switched on or off the shortlist. */
@Composable
fun ModelLibrary(models: List<Model>, harness: String, back: () -> Unit) {
    val context = LocalContext.current
    var list by remember(harness) { mutableStateOf(shortlist(context, harness)) }
    PickSheet("Models", back = back) {
        PickSection(null, footer = "Models switched on show in the picker.") {
            PickCard {
                models.forEachIndexed { i, m ->
                    if (i > 0) PickDivider()
                    PickRow(m.label) {
                        PickSwitch(listed(m, list)) { on ->
                            val ids = (list ?: models.filter { it.secondary != true }.map { it.id }).filter { it != m.id } + listOfNotNull(m.id.takeIf { on })
                            list = ids
                            saveShortlist(context, harness, ids)
                        }
                    }
                }
            }
        }
    }
}

// Pieces

/** A picks sheet's frame: the title over Done on the right (or Back on the left), then sections 24dp apart. */
@Composable
fun PickSheet(title: String, done: (() -> Unit)? = null, back: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(horizontal = Wain.Space.l)) {
        Box(Modifier.fillMaxWidth().height(44.dp), contentAlignment = Alignment.Center) {
            Text(title, style = Wain.Font.headline)
            back?.let {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", Modifier.align(Alignment.CenterStart).clip(CircleShape).clickable(onClick = it).padding(6.dp), tint = Wain.text)
            }
            done?.let {
                Text("Done", Modifier.align(Alignment.CenterEnd).clip(RoundedCornerShape(Wain.Radius.sm)).clickable(onClick = it).padding(horizontal = 6.dp, vertical = 4.dp), style = Wain.Font.headline)
            }
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(top = Wain.Space.m, bottom = Wain.Space.xxl),
            verticalArrangement = Arrangement.spacedBy(Wain.Space.xl),
            content = content,
        )
    }
}

/** A grey label over its content, with an optional note under it. */
@Composable
fun PickSection(label: String?, footer: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        label?.let { PickNote(it) }
        content()
        footer?.let { PickNote(it) }
    }
}

@Composable
fun PickNote(line: String, color: androidx.compose.ui.graphics.Color = Wain.tertiary) {
    Text(line, Modifier.padding(horizontal = Wain.Space.l), style = Wain.Font.footnote.copy(color = color))
}

@Composable
fun PickCard(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Wain.Radius.lg)).background(Wain.raised), content = content)
}

@Composable
fun PickDivider() {
    Box(Modifier.padding(start = Wain.Space.l).fillMaxWidth().height(1.dp).background(Wain.hairline))
}

/** A card row's 52dp height and its 16/14 insets. */
fun Modifier.rowFrame(): Modifier = fillMaxWidth().heightIn(min = 52.dp).padding(start = 16.dp, end = 14.dp)

/** A 52dp card row: the label, a grey note beside it where there is one, and what it holds. */
@Composable
fun PickRow(label: String, modifier: Modifier = Modifier, detail: String? = null, trailing: @Composable RowScope.() -> Unit) {
    Row(modifier.rowFrame(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (detail == null) Wain.Space.s else 6.dp)) {
        Text(label, if (detail == null) Modifier.weight(1f) else Modifier, style = Wain.Font.body, maxLines = 1)
        detail?.let { Text(it, Modifier.weight(1f), style = Wain.Font.body.copy(color = Wain.tertiary), maxLines = 1, overflow = TextOverflow.Ellipsis) }
        trailing()
    }
}

/**
 * A card row whose value is picked from a menu, a check by the current one. [extra] adds rows
 * under the choices, handed the menu's close.
 */
@Composable
fun <T> PickMenu(
    label: String, value: String, choices: List<Pair<T, String>>, selected: T?, pick: (T) -> Unit,
    extra: (@Composable (close: () -> Unit) -> Unit)? = null,
) {
    var open by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    Box {
        PickRow(label, Modifier.clickable { open = true }) {
            Text(value, Modifier.widthIn(max = 200.dp), style = Wain.Font.body.copy(color = Wain.secondary, textAlign = TextAlign.End),
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Filled.UnfoldMore, null, Modifier.size(16.dp), tint = Wain.tertiary)
        }
        Box(Modifier.align(Alignment.BottomEnd).padding(end = 14.dp)) {
            DropdownMenu(open, { open = false }, containerColor = Wain.tile, shape = RoundedCornerShape(Wain.Radius.lg)) {
                for ((v, text) in choices) MenuItem(text, v == selected) {
                    open = false
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    pick(v)
                }
                extra?.invoke { open = false }
            }
        }
    }
}

@Composable
private fun MenuItem(text: String, checked: Boolean, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    DropdownMenuItem(
        { Text(text, style = Wain.Font.body, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        onClick,
        leadingIcon = leading ?: { Box(Modifier.width(18.dp)) { if (checked) Icon(Icons.Filled.Check, null, Modifier.size(18.dp), tint = Wain.text) } },
        contentPadding = PaddingValues(start = 12.dp, end = 20.dp),
    )
}

/** The picks' switch: light with a dark knob when on, grey when off, as the iOS frames draw it. */
@Composable
fun PickSwitch(on: Boolean, enabled: Boolean = true, set: (Boolean) -> Unit) {
    val haptics = LocalHapticFeedback.current
    Switch(on, { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); set(it) }, enabled = enabled, colors = SwitchDefaults.colors(
        checkedTrackColor = Wain.primary, checkedThumbColor = Wain.onPrimary, uncheckedTrackColor = Wain.off,
        uncheckedThumbColor = Wain.secondary, uncheckedBorderColor = Wain.off))
}

/** Chips in one sideways line running to the sheet's edges, scrolled to the chip at [focus] when it moves off screen. */
@Composable
fun ChipRow(focus: Int? = null, content: LazyListScope.() -> Unit) {
    val state = rememberLazyListState()
    LaunchedEffect(focus) {
        if (focus == null || focus < 0) return@LaunchedEffect
        val info = state.layoutInfo
        val shown = info.visibleItemsInfo.firstOrNull { it.index == focus }
        if (shown == null || shown.offset < info.viewportStartOffset || shown.offset + shown.size > info.viewportEndOffset) {
            state.animateScrollToItem(maxOf(0, focus - 1))
        }
    }
    LazyRow(
        Modifier.layout { measurable, constraints ->
            // Wider than the sheet's padding by its inset each side, so chips scroll out to the edge.
            val bleed = Wain.Space.l.roundToPx()
            val placeable = measurable.measure(constraints.copy(minWidth = constraints.maxWidth + 2 * bleed, maxWidth = constraints.maxWidth + 2 * bleed))
            layout(constraints.maxWidth, placeable.height) { placeable.place(-bleed, 0) }
        },
        state = state,
        contentPadding = PaddingValues(horizontal = Wain.Space.l),
        horizontalArrangement = Arrangement.spacedBy(Wain.Space.s),
        content = content,
    )
}

/** One choice in a chip row: light when picked. An agent carries its mark. */
@Composable
fun PickChip(label: String, selected: Boolean, harness: String? = null, onClick: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    Row(
        Modifier.height(36.dp).clip(CircleShape).background(if (selected) Wain.text else Wain.tile)
            .clickable { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); onClick() }
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        harness?.let {
            AgentMark(it, 13.dp, if (selected) Wain.page else Wain.text)
            Spacer(Modifier.width(6.dp))
        }
        Text(label, style = (if (selected) Wain.Font.pill else Wain.Font.subhead).copy(color = if (selected) Wain.page else Wain.text), maxLines = 1)
    }
}
