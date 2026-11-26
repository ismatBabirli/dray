package com.wainhq.wain.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Every colour, size, radius and font the app draws with, and nowhere else: the iOS app's
 * Theme.swift, which is the desktop's dark tokens, its one yellow and its radius scale, and
 * Paper's `--color-phone-light-*` for light mode, which follows the system.
 * Yellow means *needs you* — a card, a refused token — and nothing else: `accent` fills,
 * `mark` for a small yellow dot or word, deeper in light so it reads on white.
 */
object Wain {
    /** Set by the activity before its first frame; a theme change recreates it. */
    var dark by mutableStateOf(true)
    private fun pick(dark: Long, light: Long) = Color(if (this.dark) dark else light)

    val page get() = pick(0xFF0A0A0A, 0xFFFFFFFF)
    val well get() = pick(0xFF141414, 0xFFFFFFFF)
    val lifted get() = pick(0xFF171717, 0xFFF2F2F2)
    val card get() = pick(0xFF1A1A1A, 0xFFF2F2F2)
    val raised get() = pick(0xFF262626, 0xFFE6E6E6)
    val selected get() = pick(0xFF2B2B2B, 0xFFDEDEDE)
    val tile get() = pick(0xFF333333, 0xFFE6E6E6)
    val off get() = pick(0xFF3A3A3A, 0xFFD4D4D4)
    val dim get() = pick(0xFF525252, 0xFFBDBDBD)

    val text get() = pick(0xFFFAFAFA, 0xFF171717)
    val secondary get() = pick(0xFFA1A1A1, 0xFF5C5C5C)
    val tertiary get() = pick(0xFF737373, 0xFF767676)
    val primary get() = pick(0xFFEBEBEB, 0xFF292929)
    val onPrimary get() = pick(0xFF171717, 0xFFFFFFFF)
    /** The reader's own bubble, specified in Display P3 as the iOS app draws it. */
    val sent = Color(0.192f, 0.454f, 0.806f, 1f, ColorSpaces.DisplayP3)
    val onSent = Color(0xFFFCFCFC)
    /** White on a coloured fill whatever the mode: a merge button, an unread count. */
    val onColor = Color.White

    val hairline get() = if (dark) Color.White.copy(alpha = 0.06f) else Color.Black.copy(alpha = 0.09f)
    val border get() = if (dark) Color.White.copy(alpha = 0.10f) else Color.Black.copy(alpha = 0.10f)
    val connector get() = pick(0xFF404040, 0xFFD6D6D6)
    /** A chip's 1dp outline: the connector grey in dark, a hairline in light. */
    val outline get() = if (dark) Color(0xFF404040) else Color.Black.copy(alpha = 0.09f)
    val accent = Color(0xFFE5C057)
    val mark get() = pick(0xFFE5C057, 0xFFBD8200)
    val add get() = pick(0xFF09BB83, 0xFF009A5D)
    val destructive get() = pick(0xFFFF6467, 0xFFCC272E)
    val unread = Color(0xFFCC272E)
    val merged = Color(0xFFA855F7)
    val merge = Color(0xFF238636)
    val link get() = pick(0xFF5AD3FF, 0xFF0077C7)
    /** Linear's urgent priority, and nothing else. */
    val urgent = Color(0xFFF2994A)
    val claude = Color(0xFFD97757)
    /** What a lifted surface's shadow is drawn in. */
    val shadow get() = Color.Black.copy(alpha = if (dark) 0.35f else 0.18f)

    object Radius {
        val sm = 8.dp
        val md = 10.dp
        val tile = 12.dp
        val lg = 14.dp
        val group = 18.dp
        val xl = 20.dp
    }

    object Space {
        val xs = 4.dp
        val s = 8.dp
        val m = 12.dp
        val l = 16.dp
        val xl = 24.dp
        val xxl = 32.dp
    }

    /** One type scale, five rungs, regular and semibold only. */
    object Font {
        val title get() = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, color = text)
        val headline get() = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = text)
        val body get() = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, color = text)
        val subhead get() = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, color = text)
        val pill get() = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = text)
        val footnote get() = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, color = text)
        val footnoteStrong get() = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, color = text)
        val code get() = TextStyle(fontSize = 12.sp, lineHeight = 17.sp, fontFamily = FontFamily.Monospace, color = text)
    }
}

private fun scheme() = (if (Wain.dark) darkColorScheme() else lightColorScheme()).copy(
    primary = Wain.primary,
    onPrimary = Wain.onPrimary,
    secondary = Wain.secondary,
    background = Wain.page,
    onBackground = Wain.text,
    surface = Wain.page,
    onSurface = Wain.text,
    surfaceVariant = Wain.raised,
    onSurfaceVariant = Wain.secondary,
    surfaceContainer = Wain.card,
    surfaceContainerLow = Wain.card,
    surfaceContainerHigh = Wain.raised,
    surfaceContainerHighest = Wain.tile,
    outline = Wain.border,
    outlineVariant = Wain.hairline,
    error = Wain.destructive,
)

@Composable
fun WainTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme(), content = content)
}

/** Code and tool output sit in this: the well fill, its radius and a hairline. */
fun Modifier.well(): Modifier = clip(RoundedCornerShape(Wain.Radius.md))
    .background(Wain.well)
    .border(1.dp, Wain.hairline, RoundedCornerShape(Wain.Radius.md))

fun Modifier.card(radius: androidx.compose.ui.unit.Dp = Wain.Radius.lg): Modifier = clip(RoundedCornerShape(radius))
    .background(Wain.card)
    .border(1.dp, Wain.hairline, RoundedCornerShape(radius))

/** A server error opens lowercase, written to follow a colon; a sentence here stands on its own. */
fun sentence(s: String): String = s.replaceFirstChar { it.uppercase() }
