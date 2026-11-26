package com.wainhq.wain.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// The tabs' glyphs, Paper's "Mobile navigation" icons on a 24-unit grid: outlined at rest,
// filled (or heavier) when their tab is picked.

private val paths = mutableMapOf<String, androidx.compose.ui.graphics.Path>()
private fun path(d: String) = paths.getOrPut(d) { PathParser().parsePathString(d).toPath() }

/** A 24-unit drawing at `size`. */
@Composable
fun Glyph24(size: Dp = 24.dp, modifier: Modifier = Modifier, draw: DrawScope.() -> Unit) {
    Canvas(modifier.size(size)) { scale(this.size.width / 24f, pivot = Offset.Zero) { draw() } }
}

private fun DrawScope.line(d: String, c: Color, w: Float = 1.8f) =
    drawPath(path(d), c, style = Stroke(w, cap = StrokeCap.Round, join = StrokeJoin.Round))

private fun DrawScope.box(x: Float, y: Float, w: Float, h: Float, r: Float, c: Color, stroke: Float? = 1.8f) =
    drawRoundRect(c, Offset(x, y), Size(w, h), CornerRadius(r), style = stroke?.let { Stroke(it) } ?: androidx.compose.ui.graphics.drawscope.Fill)

fun DrawScope.homeGlyph(c: Color, picked: Boolean) {
    if (picked) drawPath(path("M4 20V9.6c0-.3.1-.6.4-.8l7-5.3c.4-.3.9-.3 1.2 0l7 5.3c.3.2.4.5.4.8V20a1 1 0 0 1-1 1h-4.5v-6.5h-5V21H5a1 1 0 0 1-1-1z"), c)
    else line("M4.5 20V9.9c0-.2.1-.4.3-.5l6.8-5.1c.3-.2.6-.2.8 0l6.8 5.1c.2.1.3.3.3.5V20a.5.5 0 0 1-.5.5h-4.5v-6h-5v6H5a.5.5 0 0 1-.5-.5z", c)
}

/** `hole` is what the eyes are cut in when filled: the pill behind the glyph. */
fun DrawScope.botsGlyph(c: Color, picked: Boolean, hole: Color) {
    if (picked) {
        box(2.5f, 4f, 19f, 16f, 8f, c, null)
        box(8.5f, 9.4f, 2.3f, 4.4f, 1.15f, hole, null)
        box(13.2f, 9.4f, 2.3f, 4.4f, 1.15f, hole, null)
    } else {
        box(3f, 4.5f, 18f, 15f, 7.5f, c)
        box(8.6f, 9.6f, 2.1f, 4f, 1.05f, c, null)
        box(13.3f, 9.6f, 2.1f, 4f, 1.05f, c, null)
    }
}

fun DrawScope.tasksGlyph(c: Color, picked: Boolean) {
    if (picked) box(3.5f, 9f, 17f, 11.5f, 2.5f, c, null)
    box(3.5f, 9f, 17f, 11.5f, 2.5f, c, if (picked) 1.9f else 1.8f)
    line("M5.8 6h12.4", c, if (picked) 1.9f else 1.8f)
    line("M8 3.2h8", c, if (picked) 1.9f else 1.8f)
}

fun DrawScope.routinesGlyph(c: Color, picked: Boolean) {
    val w = if (picked) 2.3f else 1.8f
    line("M4.6 12a7.6 7.6 0 1 0 2.3-5.4", c, w)
    line("M4.2 3.8v3.6h3.6", c, w)
    line("M12 8.2v4.1l2.7 1.7", c, w)
}

fun DrawScope.machinesGlyph(c: Color) {
    box(3f, 3.5f, 18f, 7f, 2f, c)
    box(3f, 13.5f, 18f, 7f, 2f, c)
    line("M7 7h.01M7 17h.01", c)
}

fun DrawScope.pencilGlyph(c: Color) {
    line("M12 20h9", c, 2f)
    line("M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z", c, 2f)
}

fun DrawScope.issuesGlyph(c: Color) {
    drawCircle(c, 8.5f, Offset(12f, 12f), style = Stroke(1.9f))
    drawCircle(c, 2f, Offset(12f, 12f))
}

fun DrawScope.prGlyph(c: Color) {
    drawCircle(c, 2.5f, Offset(6f, 6f), style = Stroke(1.9f))
    drawCircle(c, 2.5f, Offset(18f, 18f), style = Stroke(1.9f))
    line("M6 8.5V21M18 15.5V9a3 3 0 0 0-3-3h-4", c, 1.9f)
}

fun DrawScope.micGlyph(c: Color) {
    line("M12 19v3M19 10v2a7 7 0 0 1-14 0v-2", c, 2f)
    box(9f, 2f, 6f, 13f, 3f, c, 2f)
}

fun DrawScope.checkGlyph(c: Color, w: Float = 2.6f) = line("M5 12.5l4.5 4.5L19 7.5", c, w)

fun DrawScope.crossGlyph(c: Color) = line("M6 6l12 12M18 6 6 18", c, 2.4f)

fun DrawScope.qrGlyph(c: Color) = line("M4 4h5v5H4zM15 4h5v5h-5zM4 15h5v5H4zM15 15h2v2h-2zM19 19h1v1h-1zM15 20h1M20 15v1", c)

fun DrawScope.gearGlyph(c: Color) {
    drawCircle(c, 3f, Offset(12f, 12f), style = Stroke(1.8f))
    line("M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1", c)
}
