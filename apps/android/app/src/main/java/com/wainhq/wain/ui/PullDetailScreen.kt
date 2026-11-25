package com.wainhq.wain.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.PrDetail
import com.wainhq.wain.model.PrReviewer
import com.wainhq.wain.model.PrUnavailable
import com.wainhq.wain.model.ProjectKey
import com.wainhq.wain.model.PullRequest
import com.wainhq.wain.model.PullRow
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.model.Shot
import com.wainhq.wain.model.marksRepo
import com.wainhq.wain.model.prBodyMarkdown
import com.wainhq.wain.model.trackerColor
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.Store
import com.wainhq.wain.store.botOf
import com.wainhq.wain.wire.ImageRef
import com.wainhq.wain.wire.PrListing
import com.wainhq.wain.wire.PrMark
import com.wainhq.wain.wire.decodeList
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.jsonOf
import com.wainhq.wain.wire.parseDate
import com.wainhq.wain.wire.shortAge
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What a PR's page opens: enough to read it before any list holds it, as a rotation restores the route. */
data class PullTarget(val server: String, val key: String, val repo: String, val number: Int, val url: String, val branch: String)

/** Each PR's last read this launch, by link, so going back to one draws it at once. */
private val held = mutableStateMapOf<String, Pair<PullRequest, PrDetail?>>()

/** One PR read by number through `pr_detail`, or through its branch on a server from before that. */
@Stable
class PullDetailModel(private val target: PullTarget) : PrSource(target.server) {
    var detail by mutableStateOf<PrDetail?>(null)
    /** The server predates `pr_detail`: the page says why the description and reviewers are missing. */
    var older by mutableStateOf(false)
    /** The last `pr_detail` failed with nothing of it held: the description says so rather than reading forever. */
    var extrasFailed by mutableStateOf(false)

    init {
        held[target.url]?.let { (pr, d) -> prs = listOf(pr); detail = d }
    }

    override fun cwd(store: Store) = target.key

    override suspend fun moved(store: Store) {
        if (!target.key.startsWith("github:")) store.pulls.loadMarks(listOf(ProjectKey(target.server, target.key)), force = true)
    }

    /**
     * The PR through its head branch, as a task's sheet reads it, and its description, labels and
     * reviewers by number beside it. A failed `pr_detail` keeps what it last said.
     */
    override suspend fun load(store: Store): Unit = coroutineScope {
        val extras = async {
            try {
                decodeOrNull<PrDetail>(store.call(server, "pr_detail", jsonOf("cwd" to target.key, "number" to target.number)))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (e.message?.contains("unknown command") == true) older = true else extrasFailed = detail == null
                null
            }
        }
        try {
            val pr = decodeList<PullRequest>(store.call(server, "prs_for_branch", jsonOf("cwd" to target.key, "branch" to target.branch)))
                .firstOrNull { it.number == target.number }
            if (pr == null) {
                unavailable = PrUnavailable("other", "GitHub no longer lists #${target.number} on ${target.branch}.")
            } else {
                prs = listOf(pr)
                unavailable = null
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            unavailable = PrUnavailable.from(e)
        }
        extras.await()?.let { detail = it; extrasFailed = false }
        prs.firstOrNull()?.let { held[target.url] = it to detail }
    }
}

/**
 * A pull request picked on the pull requests page: what it is and where it stands, its
 * description, labels, reviewers, checks and conversation, the tasks it has had, and the one
 * action that moves it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PullDetailScreen(target: PullTarget, back: () -> Unit, openSession: (SessionKey) -> Unit) {
    val store = LocalStore.current
    val model = remember(target) { PullDetailModel(target) }
    val connected = store.serverState[target.server] == ConnState.Connected
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    // The PR sheet's poll: quicker while GitHub is still working something out.
    LaunchedEffect(model, connected) {
        if (!connected) return@LaunchedEffect
        while (true) {
            model.load(store)
            delay(if (model.prs.any { it.settling }) 15_000 else 60_000)
        }
    }
    val pr = model.prs.firstOrNull()
    val detail = model.detail
    // A row no list holds any more, rebuilt from the route: `repo` in `marksRepo`'s spelling, as remotes compare.
    val row = store.pulls.row(target.url) ?: PullRow(
        target.server, target.key, marksRepo(target.url) ?: target.repo,
        PrMark(number = target.number, headRefName = target.branch, state = pr?.state ?: "OPEN", url = target.url),
        PrListing(isCrossRepository = pr?.isCrossRepository ?: false),
    )
    val tasks = tasks(store, row)
    var text by rememberSaveable(target.url) { mutableStateOf("") }
    var starting by remember { mutableStateOf(false) }
    val context = LocalContext.current

    var gallery by remember { mutableStateOf<ImageRef?>(null) }
    CompositionLocalProvider(LocalOpenImage provides { ref: ImageRef -> gallery = ref }) {
    Column(Modifier.fillMaxSize().background(Wain.page).statusBarsPadding().navigationBarsPadding()) {
        Bar("#${target.number} · ${target.repo.substringAfterLast('/')}", back) {
            StartActions(share = { shareLink(context, pr?.let { "#${it.number} ${it.title}" } ?: "#${target.number}", target.url) }) { starting = true }
        }
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { refreshing = true; scope.launch { model.load(store); refreshing = false } },
            modifier = Modifier.weight(1f),
        ) {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = Wain.Space.xxl),
                verticalArrangement = Arrangement.spacedBy(28.dp),
            ) {
                val u = model.unavailable
                if (u != null || model.actionError != null) item("errors") {
                    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
                        u?.let { Text(inlineMarkdown(it.sentence), style = Wain.Font.footnote.copy(color = Wain.destructive)) }
                        model.actionError?.let { Text(sentence(it), style = Wain.Font.footnote.copy(color = Wain.destructive)) }
                    }
                }
                if (pr == null) {
                    item("reading") {
                        if (u?.keepsButton == true) MissingCli(u.kind, model)
                        else if (u == null) Row(horizontalArrangement = Arrangement.spacedBy(Wain.Space.s), verticalAlignment = Alignment.CenterVertically) {
                            Orb(OrbKind.Working)
                            Text(if (connected) "Reading the pull request…" else "Waiting for ${store.name(target.server)}…",
                                Modifier.shimmer(), style = Wain.Font.subhead.copy(color = Wain.secondary))
                        }
                    }
                    return@LazyColumn
                }
                item("header") { Header(pr, detail, target.branch) }
                if (tasks.isNotEmpty()) item("tasks") { TaskList(tasks, openSession) }
                if (pr.state != "MERGED") item("readiness") { PrReadiness(pr, model) }
                if (detail != null && detail.reviewers.isNotEmpty()) item("reviewers") { Reviewers(detail.reviewers) }
                item("description") {
                    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
                        Text("Description", Modifier.padding(horizontal = Wain.Space.xs), style = Wain.Font.footnote.copy(color = Wain.tertiary))
                        val body = detail?.body?.let { remember(it) { prBodyMarkdown(it) } }
                        when {
                            detail == null && model.older -> Text("Update ${store.name(target.server)} to read the description here.",
                                style = Wain.Font.subhead.copy(color = Wain.tertiary))
                            detail == null && model.extrasFailed -> Text("Couldn't read the description. Pull down to try again.",
                                style = Wain.Font.subhead.copy(color = Wain.tertiary))
                            detail == null -> Text("Reading…", Modifier.shimmer(), style = Wain.Font.subhead.copy(color = Wain.secondary))
                            body.isNullOrEmpty() -> Text("No description.", style = Wain.Font.subhead.copy(color = Wain.tertiary))
                            else -> Box(Modifier.prGroup()) { MarkdownText(body, style = Wain.Font.subhead) }
                        }
                    }
                }
                if (pr.checks.isNotEmpty()) item("checks") { PrChecks(pr) }
                if (pr.comments.isNotEmpty()) item("comments") { PrComments(pr) }
            }
        }
    }
    }
    if (starting) StartSheet("Start a task", { starting = false }) {
        if (pr == null) Text("Reading the pull request…", Modifier.shimmer(), style = Wain.Font.subhead.copy(color = Wain.secondary))
        else PrStartBox(row, pr, text, { text = it }, tasks.firstOrNull()?.let { store.items[it] }) { starting = false }
    }
    gallery?.let { ref -> ImageViewer(listOf(Shot(ref, "Image", ref.url)), 0) { gallery = null } }
}

/** Title, state, author, branches, size, labels and dates. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Header(pr: PullRequest, detail: PrDetail?, branch: String) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(pr.title, style = Wain.Font.title)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Wain.Space.s), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            StatePill(pr)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Avatar(detail?.authorAvatar, 20, pr.author)
                Text(pr.author, style = Wain.Font.subhead.copy(color = Wain.secondary), maxLines = 1)
            }
        }
        // Base first, as GitHub writes it: the head merges into the base.
        Row(
            Modifier.clip(RoundedCornerShape(Wain.Radius.sm)).background(Wain.raised).horizontalScroll(rememberScrollState())
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(pr.baseRefName, style = Wain.Font.code.copy(color = Wain.secondary), maxLines = 1)
            Text("←", style = Wain.Font.code.copy(color = Wain.tertiary))
            Text(pr.headRefName.ifEmpty { branch }, style = Wain.Font.code, maxLines = 1)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val foot = Wain.Font.footnote
            Text("${pr.changedFiles} ${if (pr.changedFiles == 1) "file" else "files"} changed", style = foot.copy(color = Wain.secondary))
            Text("+${pr.additions}", style = foot.copy(color = Wain.add))
            Text("−${pr.deletions}", style = foot.copy(color = Wain.destructive))
        }
        if (detail != null && detail.labels.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (l in detail.labels) LabelChip(l.name, l.color)
            }
        }
        val times = listOfNotNull(
            parseDate(detail?.createdAt)?.let { "Opened ${ago(it)}" },
            parseDate(pr.updatedAt)?.let { "${if (detail == null) "Updated" else "updated"} ${ago(it)}" },
        )
        if (times.isNotEmpty()) Text(times.joinToString(" · "), style = Wain.Font.footnote.copy(color = Wain.tertiary))
    }
}

private fun ago(ms: Long): String = shortAge(ms).let { if (it == "now") "just now" else "$it ago" }

/** Open, draft, merged or closed, in GitHub's colours. */
@Composable
private fun StatePill(pr: PullRequest) {
    val (label, tone) = when {
        pr.state == "MERGED" -> "Merged" to Wain.merged
        pr.state == "CLOSED" -> "Closed" to Wain.destructive
        pr.isDraft -> "Draft" to Wain.secondary
        else -> "Open" to Wain.add
    }
    Row(
        Modifier.height(26.dp).clip(CircleShape).background(tone.copy(alpha = 0.16f)).padding(start = 6.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        PrGlyph(pr.mark.copy(checksState = "CLEAR"), 14.dp)
        Text(label, style = Wain.Font.footnoteStrong.copy(color = tone))
    }
}

@Composable
fun LabelChip(name: String, hex: String) {
    val tone = Color(trackerColor(hex))
    Row(
        Modifier.height(26.dp).clip(CircleShape).background(Wain.raised).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(tone))
        Text(name, style = Wain.Font.footnote.copy(color = Wain.secondary), maxLines = 1)
    }
}

/**
 * A person's round GitHub or tracker picture, their initial under it until it loads and where it
 * never does. The picture stays invisible until loaded, since RemoteImage's own placeholder and
 * failure icon would cover the initial.
 */
@Composable
fun Avatar(url: String?, size: Int, name: String = "") {
    var loaded by remember(url) { mutableStateOf(false) }
    Box(Modifier.size(size.dp).clip(CircleShape).background(Wain.tile), contentAlignment = Alignment.Center) {
        if (!loaded) name.firstOrNull { it.isLetterOrDigit() }?.let {
            Text(it.uppercase(), style = Wain.Font.footnoteStrong.copy(color = Wain.secondary, fontSize = (size * 0.5f).sp, lineHeight = (size * 0.5f).sp))
        }
        url?.let {
            RemoteImage(ImageRef(url = it), Modifier.size(size.dp).alpha(if (loaded) 1f else 0f), contentScale = ContentScale.Crop, onLoaded = { loaded = true })
        }
    }
}

/** Who reviewed and how, and who is still asked. */
@Composable
private fun Reviewers(reviewers: List<PrReviewer>) {
    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        Text("Reviewers", Modifier.padding(horizontal = Wain.Space.xs), style = Wain.Font.footnote.copy(color = Wain.tertiary))
        Column(Modifier.prGroup(0.dp).padding(vertical = Wain.Space.xs)) {
            for (r in reviewers) Row(
                Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Wain.Space.m),
            ) {
                Avatar(r.avatar, 22, r.name)
                Text(r.name, Modifier.weight(1f), style = Wain.Font.body, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val (word, tone) = when (r.state) {
                    "approved" -> "Approved" to Wain.add
                    "changes_requested" -> "Changes requested" to Wain.destructive
                    "commented" -> "Commented" to Wain.secondary
                    "requested" -> "Review requested" to Wain.tertiary
                    else -> r.state.replace('_', ' ').replaceFirstChar { it.uppercase() } to Wain.tertiary
                }
                Text(word, style = Wain.Font.subhead.copy(color = tone), maxLines = 1)
            }
        }
    }
}

/** The PR's tasks, newest first. A settled one still opens: its work and conversation are there. */
@Composable
internal fun TaskList(tasks: List<SessionKey>, open: (SessionKey) -> Unit) {
    val store = LocalStore.current
    Column(verticalArrangement = Arrangement.spacedBy(Wain.Space.s)) {
        Text(if (tasks.size == 1) "Task" else "Tasks", Modifier.padding(horizontal = Wain.Space.xs), style = Wain.Font.footnote.copy(color = Wain.tertiary))
        Column(Modifier.prGroup(0.dp)) {
            tasks.forEachIndexed { i, key ->
                val item = store.items[key] ?: return@forEachIndexed
                if (i > 0) PickDivider()
                val bot = store.botOf(key)
                Row(
                    Modifier.clickable { open(key) }.rowFrame(),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Wain.Space.s),
                ) {
                    bot?.let { BotFace(it, 18.dp) }
                    Text(
                        bot?.let { "${it.name} · ${item.title}" } ?: item.title, Modifier.weight(1f),
                        style = Wain.Font.body.copy(color = if (item.archived == true) Wain.secondary else Wain.text),
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                    if (item.archived == true) Text("Settled", style = Wain.Font.subhead.copy(color = Wain.tertiary))
                    else if (item.busy) Orb(OrbKind.Working)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(20.dp), tint = Wain.tertiary)
                }
            }
        }
    }
}
