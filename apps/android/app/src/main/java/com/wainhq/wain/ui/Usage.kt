package com.wainhq.wain.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.Picks
import com.wainhq.wain.model.UsageChip
import com.wainhq.wain.model.atLimit
import com.wainhq.wain.model.planLabel
import com.wainhq.wain.model.usageAgent
import com.wainhq.wain.model.usageChips
import com.wainhq.wain.model.windowLabel
import com.wainhq.wain.store.shownUsage
import com.wainhq.wain.wire.UsageWindow
import com.wainhq.wain.wire.parseDate
import com.wainhq.wain.wire.shortAge
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** How full a window is, as a ring filling clockwise from the top; a spent one is a whole red ring. */
@Composable
fun UsageRing(percent: Double, limited: Boolean, size: Dp = 18.dp, track: Color = Wain.tile) {
    Canvas(Modifier.size(size)) {
        val u = this.size.width / 18f
        val stroke = 2.5f * u
        val r = 7f * u
        val c = Offset(this.size.width / 2, this.size.height / 2)
        if (limited) return@Canvas drawCircle(Wain.destructive, r, c, style = Stroke(stroke))
        drawCircle(track, r, c, style = Stroke(stroke))
        val sweep = (percent.coerceIn(0.0, 100.0) / 100 * 360).toFloat()
        if (sweep > 0) drawArc(Wain.text, -90f, sweep, false, Offset(c.x - r, c.y - r), androidx.compose.ui.geometry.Size(2 * r, 2 * r),
            style = Stroke(stroke, cap = StrokeCap.Round))
    }
}

/** A reset as the sheet says it: the time today, else the day and time, 24-hour as the design writes it. */
fun resetLabel(iso: String?, now: Long = System.currentTimeMillis()): String? {
    val at = parseDate(iso) ?: return null
    val a = Calendar.getInstance().apply { timeInMillis = at }
    val b = Calendar.getInstance().apply { timeInMillis = now }
    val sameDay = a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    val pattern = when {
        sameDay -> "HH:mm"
        at - now < 6 * 86_400_000L -> "EEE HH:mm"
        else -> "MMM d"
    }
    return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(at))
}

/** Home's strip: one chip per agent with a reading on the shown machines. */
@Composable
fun UsageChips(open: () -> Unit) {
    val chips = usageChips(LocalStore.current.shownUsage)
    if (chips.isEmpty()) return
    LazyRow(
        Modifier.fillMaxWidth().padding(bottom = 8.dp),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) { items(chips, key = { it.harness }) { UsageChipView(it, open) } }
}

@Composable
private fun UsageChipView(chip: UsageChip, open: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    val name = usageAgent(chip.harness)
    val back = if (chip.limited) resetLabel(chip.back)?.let { "back $it" } ?: "at limit" else null
    Row(
        Modifier.height(32.dp).clip(shape)
            .then(if (chip.limited) Modifier.background(Wain.destructive.copy(alpha = if (Wain.dark) 0.16f else 0.12f)) else Modifier.border(1.dp, Wain.outline, shape))
            .clickable(onClick = open)
            .semantics { contentDescription = "$name, ${back ?: "${chip.percent.toInt()}% of five hours"}" }
            .padding(start = 8.dp, end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        UsageRing(chip.percent, chip.limited)
        val ink = if (chip.limited) Wain.destructive else Wain.text
        Text(name, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = ink))
        Text(back ?: "${chip.percent.toInt()}%", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp,
            color = if (chip.limited) Wain.destructive else Wain.secondary))
    }
}

/** Every reading by machine: each agent's plan, how old the reading is, and every window as a bar. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UsageSheet(dismiss: () -> Unit) {
    val store = LocalStore.current
    val machines = store.shown.filter { store.usage[it.id].orEmpty().isNotEmpty() }
    ModalBottomSheet(dismiss, containerColor = Wain.card, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom = 32.dp)) {
            Text("Usage", Modifier.padding(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 8.dp), style = Wain.Font.title.copy(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Normal))
            if (machines.isEmpty()) Text("No readings yet.", Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = Wain.Font.body.copy(color = Wain.secondary))
            machines.forEachIndexed { i, s ->
                if (i > 0) HorizontalDivider(Modifier.padding(top = 4.dp), color = Wain.hairline)
                val mac = store.connection(s.id)?.welcome?.macApp == true
                Text(if (mac) "${s.name} · This Mac" else s.name, Modifier.padding(start = 24.dp, end = 24.dp, top = 12.dp, bottom = 4.dp),
                    style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.secondary))
                for (r in store.usage[s.id].orEmpty()) {
                    Column(Modifier.padding(horizontal = 24.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(Picks.agentLabels[r.harness] ?: r.harness, Modifier.weight(1f), style = Wain.Font.body.copy(lineHeight = 24.sp))
                            val age = parseDate(r.at)?.let { shortAge(it).let { a -> if (a == "now") "just now" else "$a ago" } }
                            Text(listOfNotNull(planLabel(r.plan), age).joinToString(" · "), style = Wain.Font.footnote.copy(fontSize = 12.sp, lineHeight = 16.sp, color = Wain.tertiary))
                        }
                        for (w in r.windows) WindowBar(w, w.usedPercent >= 100)
                        when {
                            r.usingOverage -> Text("Using extra usage.", style = Wain.Font.footnote.copy(color = Wain.tertiary))
                            r.atLimit && r.overage == "rejected" -> Text("Extra usage is off for this account.", style = Wain.Font.footnote.copy(color = Wain.tertiary))
                        }
                    }
                }
            }
            Text(
                "Readings come in while a task on that agent runs. Grok, fx, pi and OpenCode don't report usage.",
                Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = Wain.Font.footnote.copy(color = Wain.tertiary),
            )
        }
    }
}

@Composable
private fun WindowBar(w: UsageWindow, spent: Boolean) {
    val reset = resetLabel(w.resetsAt)
    val label = windowLabel(w) + when {
        spent -> " · limit reached" + (reset?.let { " · back $it" } ?: "")
        else -> reset?.let { " · resets $it" } ?: ""
    }
    val ink = if (spent) Wain.destructive else Wain.secondary
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row {
            Text(label, Modifier.weight(1f), style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = ink))
            Text("${w.usedPercent.toInt()}%", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium,
                color = if (spent) Wain.destructive else Wain.text))
        }
        val f = (w.usedPercent / 100).coerceIn(0.0, 1.0).toFloat()
        Row(Modifier.fillMaxWidth().height(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (spent) Box(Modifier.weight(1f).height(4.dp).clip(RoundedCornerShape(2.dp)).background(Wain.destructive))
            else {
                if (f > 0f) Box(Modifier.weight(f).height(4.dp).clip(RoundedCornerShape(2.dp)).background(Wain.text))
                if (f < 1f) Box(Modifier.weight(1f - f).height(4.dp).clip(RoundedCornerShape(2.dp)).background(Wain.tile))
            }
        }
    }
}
