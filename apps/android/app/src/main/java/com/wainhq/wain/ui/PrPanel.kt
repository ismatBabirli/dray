package com.wainhq.wain.ui

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wainhq.wain.model.MergeMethod
import com.wainhq.wain.model.MergeVerdict
import com.wainhq.wain.model.PrCheck
import com.wainhq.wain.model.PrComment
import com.wainhq.wain.model.PrUnavailable
import com.wainhq.wain.model.PullRequest
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.model.WorkStatus
import com.wainhq.wain.model.commentMarkdown
import com.wainhq.wain.model.commentText
import com.wainhq.wain.model.readiness
import com.wainhq.wain.model.sessionBranch
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.Store
import com.wainhq.wain.wire.ImageRef
import com.wainhq.wain.wire.bool
import com.wainhq.wain.wire.decodeList
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.jsonOf
import com.wainhq.wain.wire.parseDate
import com.wainhq.wain.wire.shortAge
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

// PrPanel.swift: a task's pull request, read and moved from the phone.

/**
 * Pull requests read from one server, and the actions that move them: a task's PR sheet, or one
 * PR's page on the pull requests list.
 */
@Stable
abstract class PrSource(val server: String) {
    var prs by mutableStateOf(listOf<PullRequest>())
    var unavailable by mutableStateOf<PrUnavailable?>(null)
    var acting by mutableStateOf(false)
    var actionError by mutableStateOf<String?>(null)

    abstract suspend fun load(store: Store)

    /** The checkout or `github:` slug an action runs against. */
    protected abstract fun cwd(store: Store): String?

    /** Brings what else shows this PR in line once an action lands. */
    protected abstract suspend fun moved(store: Store)

    /**
     * Runs on the store's scope, not a composable's: the button that asked leaves the screen the
     * moment Working… replaces it, and its own scope would cancel the read-back mid-flight.
     */
    fun act(store: Store, cmd: String, number: Int, extra: Map<String, Any?> = emptyMap(), done: (Boolean) -> Unit = {}) {
        val cwd = cwd(store) ?: return
        acting = true
        actionError = null
        store.scope.launch {
            try {
                store.call(server, cmd, JsonObject(jsonOf("cwd" to cwd, "number" to number) + jsonOf(*extra.toList().toTypedArray())))
            } catch (e: CancellationException) {
                acting = false
                throw e
            } catch (e: Exception) {
                actionError = e.message ?: "Failed"
            }
            load(store)
            moved(store)
            acting = false
            done(actionError == null)
        }
    }
}

/** What the server says about a session's pull requests. Lives with the task screen, so its button knows whether there is anything to open. */
@Stable
class PrModel(val key: SessionKey) : PrSource(key.server) {
    var branch by mutableStateOf<String?>(null)
    private var generation = 0

    /** The button stays for the two states the reader can fix; every other error with no rows hides it, as the desktop's tab does. */
    val visible: Boolean get() = prs.isNotEmpty() || unavailable?.keepsButton == true

    override fun cwd(store: Store) = store.items[key]?.cwd

    override suspend fun moved(store: Store) {
        store.items[key]?.let { store.refreshMarks(key.server, it.projectPath) }
    }

    override suspend fun load(store: Store) {
        val item = store.items[key] ?: return
        val gen = ++generation
        try {
            val status = decodeOrNull<WorkStatus>(store.call(key.server, "work_status", jsonOf("cwd" to item.cwd)))
            val branch = sessionBranch(item.branch, item.worktreeName, item.worktreeRemoved ?: false, status?.branch)
            if (branch == null) {
                if (gen == generation) { this.branch = null; prs = emptyList(); unavailable = null }
                return
            }
            val prs = decodeList<PullRequest>(store.call(key.server, "prs_for_branch", jsonOf("cwd" to item.cwd, "branch" to branch)))
            if (gen != generation) return
            this.branch = branch
            this.prs = prs
            unavailable = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Rows already on screen stay under the sentence, which says what failed to update.
            if (gen == generation) unavailable = PrUnavailable.from(e)
        }
    }
}

/**
 * The PR button in a task's title bar and the sheet it opens. Re-read on arriving, on every turn
 * edge, since a turn is what opens a PR, and on reconnect, where a read that failed with the
 * socket down would otherwise never retry.
 */
@Composable
fun PrButton(key: SessionKey) {
    val store = LocalStore.current
    val model = remember(key) { PrModel(key) }
    var showing by remember { mutableStateOf(false) }
    val busy = store.items[key]?.busy == true
    val connected = store.serverState[key.server] == ConnState.Connected
    LaunchedEffect(key, busy, connected) { if (connected) model.load(store) }
    if (!model.visible) return
    IconButton({ showing = true }) {
        // The list row's own glyph, so the button says the PR's state before it is opened.
        val pr = model.prs.firstOrNull()
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
            if (pr != null) PrGlyph(pr.mark, 20.dp) else PrOutline(Wain.text, 20.dp)
        }
    }
    if (showing) PrSheet(model) { showing = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PrSheet(model: PrModel, dismiss: () -> Unit) {
    val store = LocalStore.current
    // The desktop's poll: quicker while GitHub is still working something out.
    LaunchedEffect(model) {
        while (true) {
            model.load(store)
            delay(if (model.prs.any { it.settling }) 15_000 else 60_000)
        }
    }
    ModalBottomSheet(dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = Wain.card) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Pull request", Modifier.weight(1f), style = Wain.Font.headline)
                TextButton(dismiss) { Text("Done", style = Wain.Font.pill) }
            }
            val u = model.unavailable
            // No loading or no-PR state: the button that opens this shows only once a read found one.
            if (model.prs.isEmpty() && u != null && u.keepsButton) {
                MissingCli(u.kind, model)
            } else {
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, top = 14.dp, bottom = Wain.Space.xl),
                    verticalArrangement = Arrangement.spacedBy(28.dp),
                ) {
                    if (u != null || model.actionError != null) item("errors") {
                        Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
                            u?.let { Text(inlineMarkdown(it.sentence), style = Wain.Font.footnote.copy(color = Wain.destructive)) }
                            model.actionError?.let { Text(sentence(it), style = Wain.Font.footnote.copy(color = Wain.destructive)) }
                        }
                    }
                    for (pr in model.prs) item("pr-${pr.number}") { PrSection(pr, model) }
                }
            }
        }
    }
}

/** One pull request: what it is, whether it can land and the one action that moves it, then its checks and what people said. */
@Composable
private fun PrSection(pr: PullRequest, model: PrSource) {
    val uri = LocalUriHandler.current
    Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.clickable { runCatching { uri.openUri(pr.url) } }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.padding(top = 3.dp)) { PrGlyph(pr.mark, 20.dp) }
                    Text(pr.title, style = Wain.Font.title)
                }
                Row(Modifier.padding(start = 30.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val foot = Wain.Font.footnote
                    Text("#${pr.number} · ${pr.author}", Modifier.weight(1f, fill = false), style = foot.copy(color = Wain.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("+${pr.additions}", style = foot.copy(color = Wain.add), maxLines = 1)
                    Text("−${pr.deletions}", style = foot.copy(color = Wain.destructive), maxLines = 1)
                    Text("· ${pr.changedFiles} ${if (pr.changedFiles == 1) "file" else "files"}", style = foot.copy(color = Wain.secondary), maxLines = 1)
                }
            }
            PrReadiness(pr, model)
        }
        PrChecks(pr)
        PrComments(pr)
    }
}

/** Whether the PR can land, why not, and the one action that moves it. */
@Composable
fun PrReadiness(pr: PullRequest, model: PrSource) {
    val (label, detail) = readiness(pr)
    Column(Modifier.prGroup(), verticalArrangement = Arrangement.spacedBy(Wain.Space.m)) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                Text(label, style = Wain.Font.subhead.copy(color = tone(pr)))
                if (pr.state == "OPEN") {
                    Text("into ${pr.baseRefName}", style = Wain.Font.subhead.copy(color = Wain.tertiary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            detail?.let { Text(it, style = Wain.Font.footnote.copy(color = Wain.secondary)) }
        }
        Action(pr, model)
    }
}

/** The tip commit's checks under their summary, failing first. Nothing where there are none. */
@Composable
fun PrChecks(pr: PullRequest) {
    if (pr.checks.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        Row(Modifier.padding(horizontal = Wain.Space.xs)) {
            Text("Checks", Modifier.weight(1f), style = Wain.Font.footnote.copy(color = Wain.tertiary))
            Text(checksSummary(pr), style = Wain.Font.footnote.copy(color = Wain.tertiary))
        }
        Column(Modifier.prGroup(0.dp).padding(vertical = Wain.Space.xs)) {
            // Failing first, then running: what the reader opened the sheet to find.
            val rank = mapOf("failure" to 0, "pending" to 1)
            for (c in pr.checks.withIndex().sortedWith(compareBy({ rank[it.value.state] ?: 2 }, { it.index })).map { it.value }) CheckRow(c)
        }
    }
}

/** Comments, reviews and threads, oldest first. Nothing where there are none. */
@Composable
fun PrComments(pr: PullRequest) {
    if (pr.comments.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        Text("Comments", Modifier.padding(horizontal = Wain.Space.xs), style = Wain.Font.footnote.copy(color = Wain.tertiary))
        for (c in pr.comments) CommentCard(c)
    }
}

fun checksSummary(pr: PullRequest): String {
    val failing = pr.failingChecks
    if (failing > 0) return "$failing failing"
    val done = pr.checks.count { it.state != "pending" }
    if (done < pr.checks.size) return "$done of ${pr.checks.size} done"
    // Cancelled, skipped and neutral finish without passing.
    return if (pr.checks.all { it.state == "success" }) "All passed" else "All done"
}

private fun tone(pr: PullRequest): Color {
    if (pr.checksHold) return Wain.mark
    return when (pr.verdict) {
        MergeVerdict.Ready -> Wain.add
        MergeVerdict.Conflict -> Wain.destructive
        MergeVerdict.Behind, MergeVerdict.Blocked, MergeVerdict.Unstable, MergeVerdict.Unknown -> Wain.mark
        MergeVerdict.Merged -> Wain.merged
        MergeVerdict.Closed, MergeVerdict.Draft -> Wain.secondary
    }
}

/** Reopen, mark ready, or merge — and no close or branch delete, as on the desktop. */
@Composable
private fun Action(pr: PullRequest, model: PrSource) {
    val store = LocalStore.current
    when {
        model.acting -> Row(Modifier.heightIn(min = 44.dp), horizontalArrangement = Arrangement.spacedBy(Wain.Space.s), verticalAlignment = Alignment.CenterVertically) {
            Orb(OrbKind.Working)
            Text("Working…", Modifier.shimmer(), style = Wain.Font.subhead.copy(color = Wain.secondary))
        }
        pr.state == "CLOSED" -> Pill("Reopen", Wain.tile, Wain.text) { model.act(store, "reopen_pr", pr.number) }
        pr.state == "OPEN" && pr.isDraft -> Pill("Ready for review", Wain.primary, Wain.onPrimary) { model.act(store, "mark_pr_ready", pr.number) }
        pr.state == "OPEN" -> MergeButton(pr, model)
    }
}

@Composable
private fun Pill(label: String, fill: Color, ink: Color, height: Dp = 44.dp, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(height).clip(CircleShape).background(fill).alpha(if (enabled) 1f else 0.5f)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(label, style = Wain.Font.headline.copy(color = ink)) }
}

private fun savedMethod(context: Context): MergeMethod {
    val wire = context.getSharedPreferences("store", Context.MODE_PRIVATE).getString("pr.mergeMethod", null)
    return MergeMethod.entries.firstOrNull { it.wire == wire } ?: MergeMethod.Squash
}

/**
 * One green pill with a seam, the desktop's split button: the left merges after a confirm, the
 * chevron picks how. The pick is kept on the phone.
 */
@Composable
private fun MergeButton(pr: PullRequest, model: PrSource) {
    val store = LocalStore.current
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var method by remember { mutableStateOf(savedMethod(context)) }
    var confirming by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf(false) }
    // A poll can start or fail a check while the confirm is open; the hold covers it too.
    LaunchedEffect(pr.checksHold) { if (pr.checksHold) confirming = false }
    val live = !pr.checksHold
    Row(
        // Dim while GitHub would refuse it; inert while checks run or fail, as the line above says.
        Modifier.fillMaxWidth().height(44.dp).clip(CircleShape).background(Wain.merge)
            .alpha(if (pr.verdict == MergeVerdict.Ready && live) 1f else 0.6f),
    ) {
        Box(Modifier.weight(1f).fillMaxHeight().clickable(enabled = live) { confirming = true }.padding(start = 52.dp), contentAlignment = Alignment.Center) {
            // The leading pad centres the label on the whole pill, not on what the chevron leaves.
            Text(method.label, style = Wain.Font.headline.copy(color = Color.White), maxLines = 1)
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(Color.Black.copy(alpha = 0.25f)))
        Box(Modifier.width(52.dp).fillMaxHeight().clickable(enabled = live) { picking = true }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.KeyboardArrowDown, "Merge method", tint = Color.White)
            DropdownMenu(picking, { picking = false }, containerColor = Wain.raised) {
                for (m in MergeMethod.entries) DropdownMenuItem(
                    text = {
                        Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(m.label, style = Wain.Font.body)
                            Text(m.detail, style = Wain.Font.footnote.copy(color = Wain.secondary))
                        }
                    },
                    leadingIcon = { Box(Modifier.size(18.dp)) { if (m == method) Icon(Icons.Filled.Check, null, tint = Wain.text) } },
                    onClick = {
                        method = m
                        context.getSharedPreferences("store", Context.MODE_PRIVATE).edit().putString("pr.mergeMethod", m.wire).apply()
                        picking = false
                    },
                    colors = MenuDefaults.itemColors(textColor = Wain.text),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                )
            }
        }
    }
    if (confirming) {
        val (label, _) = readiness(pr)
        AlertDialog(
            onDismissRequest = { confirming = false },
            containerColor = Wain.raised,
            title = { Text("${method.label} #${pr.number}?", style = Wain.Font.headline) },
            text = {
                Text(
                    if (pr.verdict == MergeVerdict.Ready) method.landing(pr.baseRefName)
                    else "${method.landing(pr.baseRefName)} $label, so GitHub may refuse it.",
                    style = Wain.Font.subhead.copy(color = Wain.secondary),
                )
            },
            confirmButton = {
                TextButton({
                    confirming = false
                    // Read the model, not this composable's copy, which can trail a refresh by a frame.
                    if (model.prs.firstOrNull { it.number == pr.number }?.checksHold != false) return@TextButton
                    model.act(store, "merge_pr", pr.number, mapOf("method" to method.wire)) { ok ->
                        if (ok) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    }
                }) { Text(method.label, style = Wain.Font.pill.copy(color = Wain.add)) }
            },
            dismissButton = { TextButton({ confirming = false }) { Text("Cancel", style = Wain.Font.pill.copy(color = Wain.secondary)) } },
        )
    }
}

@Composable
fun CheckRow(check: PrCheck) {
    val uri = LocalUriHandler.current
    Row(
        Modifier.fillMaxWidth().height(44.dp)
            .then(if (check.url != null) Modifier.clickable { runCatching { uri.openUri(check.url) } } else Modifier)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Wain.Space.m),
    ) {
        Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
            when (check.state) {
                "success" -> Icon(Icons.Filled.CheckCircle, "Passed", Modifier.size(20.dp), tint = Wain.add)
                "failure" -> Icon(Icons.Filled.Cancel, "Failed", Modifier.size(20.dp), tint = Wain.destructive)
                "pending" -> ChecksSpinner(20.dp)
                else -> Icon(Icons.Outlined.RemoveCircleOutline, check.state, Modifier.size(20.dp), tint = Wain.tertiary)
            }
        }
        Text(check.name, Modifier.weight(1f), style = Wain.Font.body, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (check.url != null) OutArrow()
    }
}

/** "Opens on GitHub", trailing a row that does. */
@Composable
fun OutArrow() {
    Icon(Icons.AutoMirrored.Filled.CallMade, null, Modifier.size(14.dp), tint = Wain.tertiary)
}

/**
 * A comment or review as a card: three lines of it, and a tap opens it whole in place with its
 * replies and inline threads, since the page reads and never replies. Another tap folds it.
 */
@Composable
fun CommentCard(comment: PrComment) {
    var open by rememberSaveable(comment.id) { mutableStateOf(false) }
    Column(
        Modifier.prGroup(0.dp).clickable { open = !open }.padding(14.dp).alpha(if (comment.resolved && !open) 0.6f else 1f),
        verticalArrangement = Arrangement.spacedBy(Wain.Space.s),
    ) {
        CommentHead(comment)
        comment.path?.let { Text(if (open) it else it.substringAfterLast('/'), style = Wain.Font.footnote.copy(color = Wain.tertiary)) }
        if (open) {
            val body = remember(comment.body) { commentMarkdown(comment.body) }
            if (body.isNotEmpty()) MarkdownText(body, style = Wain.Font.subhead)
            for (r in comment.replies) Reply(r)
        } else {
            val text = remember(comment.body) { commentText(comment.body) }
            // Plain while folded: three lines of markdown would cut a table or a fence mid-way.
            if (text.isNotEmpty()) Text(text, style = Wain.Font.subhead.copy(color = Wain.secondary), maxLines = 3, overflow = TextOverflow.Ellipsis)
            if (comment.replies.isNotEmpty()) Text("${comment.replies.size} more", style = Wain.Font.footnote.copy(color = Wain.tertiary))
        }
    }
}

@Composable
private fun CommentHead(comment: PrComment) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        Avatar(comment.avatar, 20, comment.author)
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
            Text(comment.author, Modifier.weight(1f, fill = false), style = Wain.Font.subhead, maxLines = 1, overflow = TextOverflow.Ellipsis)
            verb(comment.kind)?.let { (v, c) -> Text(v, style = Wain.Font.subhead.copy(color = c), maxLines = 1) }
        }
        if (comment.resolved) Text("Resolved", style = Wain.Font.subhead.copy(color = Wain.tertiary))
        parseDate(comment.createdAt)?.let { Text(shortAge(it), style = Wain.Font.subhead.copy(color = Wain.tertiary)) }
    }
}

/** A reply or inline thread in an opened comment, under a hairline; a thread's own replies step in. */
@Composable
private fun Reply(reply: PrComment) {
    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Wain.hairline))
        CommentHead(reply)
        reply.path?.let { Text(it, style = Wain.Font.footnote.copy(color = Wain.tertiary)) }
        val body = remember(reply.body) { commentMarkdown(reply.body) }
        if (body.isNotEmpty()) MarkdownText(body, style = Wain.Font.subhead)
        if (reply.replies.isNotEmpty()) Column(Modifier.padding(start = Wain.Space.m), verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
            for (r in reply.replies) Reply(r)
        }
    }
}

private fun verb(kind: String): Pair<String, Color>? = when (kind) {
    "approved" -> "approved" to Wain.add
    "changes_requested" -> "requested changes" to Wain.destructive
    "reviewed" -> "reviewed" to Wain.secondary
    else -> null
}

/** `gh` missing or logged out on the server: the command to run there, and a way to look again once it has. The desktop's `MissingCli`. */
@Composable
fun MissingCli(kind: String, model: PrSource) {
    val store = LocalStore.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var copied by remember { mutableStateOf(false) }
    var checking by remember { mutableStateOf(false) }
    var stillMissing by remember { mutableStateOf(false) }
    val installing = kind == "no_cli"
    val command = if (installing) "wain setup" else "gh auth login"
    val server = store.name(model.server)
    Column(
        Modifier.fillMaxWidth().fillMaxHeight().padding(horizontal = 20.dp).padding(bottom = 120.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
    ) {
        PrOutline(Wain.mark, 36.dp)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Wain.Space.xs)) {
            Text(if (installing) "GitHub CLI isn't installed" else "GitHub CLI is logged out", style = Wain.Font.title, textAlign = TextAlign.Center)
            Text(
                if (stillMissing) "Still not found on $server." else "Run this on $server, then check again.",
                style = Wain.Font.subhead.copy(color = Wain.secondary), textAlign = TextAlign.Center,
            )
        }
        Row(
            Modifier.padding(top = 6.dp).fillMaxWidth().clip(RoundedCornerShape(Wain.Radius.lg)).background(Wain.raised)
                .clickable { clipboard.setText(AnnotatedString(command)); copied = true }
                .padding(horizontal = 14.dp, vertical = Wain.Space.m),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(command, Modifier.weight(1f), style = Wain.Font.footnote.copy(fontFamily = Wain.Font.code.fontFamily))
            Icon(if (copied) Icons.Filled.Check else Icons.Outlined.ContentCopy, "Copy $command", Modifier.size(18.dp), tint = Wain.secondary)
        }
        Pill("Check again", Wain.primary, Wain.onPrimary, height = 48.dp, enabled = !checking) {
            scope.launch {
                checking = true
                try {
                    // Logging in moves nothing about where `gh` is, so that half only reads again;
                    // an install needs the server to drop its cached absence first.
                    if (installing) {
                        val found = runCatching { store.call(model.server, "recheck_gh").bool }.getOrNull() == true
                        stillMissing = !found
                        if (!found) return@launch
                    }
                    model.load(store)
                } finally {
                    checking = false
                }
            }
        }
    }
}

/** The open-PR glyph in one tone: the title bar's button before a PR is read, and the notice's mark. */
@Composable
fun PrOutline(tone: Color, size: Dp, label: String? = null) {
    Canvas(Modifier.size(size).then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier)) {
        val p = Path().apply {
            addOval(Rect(3f, 3f, 9f, 9f))
            moveTo(6f, 9f); lineTo(6f, 21f)
            addOval(Rect(15f, 15f, 21f, 21f))
            moveTo(13f, 6f); lineTo(16f, 6f)
            arcTo(Rect(14f, 6f, 18f, 10f), 270f, 90f, false)
            lineTo(18f, 15f)
        }
        scale(this.size.width / 24f, pivot = Offset.Zero) {
            drawPath(p, tone, style = Stroke(1.5f, cap = StrokeCap.Round))
        }
    }
}

/** A raised group on the sheet: the readiness card, the checks, each comment. */
fun Modifier.prGroup(padding: Dp = Wain.Space.l): Modifier =
    fillMaxWidth().clip(RoundedCornerShape(Wain.Radius.group)).background(Wain.raised).padding(padding)
